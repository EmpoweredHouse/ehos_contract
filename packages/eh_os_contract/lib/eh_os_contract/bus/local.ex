defmodule EhOsContract.Bus.Local do
  @moduledoc """
  An `EhOsContract.Bus` inside one BEAM: for tests, and for two applications run side by
  side in development. It keeps what it holds in memory, so it is **not** a transport
  for production — what it held is gone when the node stops.

  Start it in the host's tree, before anything that publishes or consumes, and name the
  same options in the config:

      children = [{EhOsContract.Bus.Local, []}, ...]
      config :eh_os_contract, bus: {EhOsContract.Bus.Local, []}

  Options: `:name`, the registered name (`EhOsContract.Bus.Local` by default), so two
  can run at once; and `:retry_after`, how long a message a handler did not acknowledge
  waits before it is delivered again, in milliseconds (1 000 by default).

  **Durable for as long as the node runs.** A consumer's subscription outlives its
  process: what is published while the consumer is stopped waits for it, and a message
  it had in hand when it stopped comes again after `:retry_after`. A consumer takes
  one message at a time, so a single consumer happens to see its messages in the order
  they were published until one is redelivered; `EhOsContract.Bus` promises no order,
  and nothing may rely on this one.

  **The payload goes through JSON** on the way, encoded in the publisher's process, so
  a term a real transport could not carry raises there, and what a handler gets is
  what `Jason` decodes. A message published twice is delivered twice: the inbox, not
  the transport, is what drops the second one.
  """

  @behaviour EhOsContract.Bus

  use GenServer

  alias EhOsContract.Bus.Message

  @default_retry 1_000

  @doc "The broker, to put in the host's supervision tree."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts),
    do: %{id: {__MODULE__, server(opts)}, start: {__MODULE__, :start_link, [opts]}}

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: server(opts))

  @impl EhOsContract.Bus
  @spec publish(keyword(), [Message.t()]) :: :ok
  def publish(opts, messages) do
    encoded = Enum.map(messages, &%{&1 | payload: Jason.encode!(&1.payload)})
    GenServer.call(server(opts), {:publish, encoded})
  end

  @impl EhOsContract.Bus
  @spec consumer(keyword(), EhOsContract.Bus.consumer()) :: Supervisor.child_spec()
  def consumer(opts, consumer) do
    %{
      id: {__MODULE__.Consumer, consumer.name},
      start: {__MODULE__.Consumer, :start_link, [server(opts), consumer]}
    }
  end

  defp server(opts), do: Keyword.get(opts, :name, __MODULE__)

  # The broker. `consumers` maps a consumer's name to the names it takes, its queue of
  # messages and the processes waiting for one; `in_hand` maps a delivery to the
  # consumer, the message and the process that took it.

  @impl GenServer
  def init(opts) do
    {:ok,
     %{
       retry_after: Keyword.get(opts, :retry_after, @default_retry),
       consumers: %{},
       in_hand: %{},
       monitored: MapSet.new()
     }}
  end

  @impl GenServer
  def handle_call({:subscribe, name, names}, {pid, _tag}, state) do
    consumers =
      Map.update(
        state.consumers,
        name,
        %{names: MapSet.new(names), queue: :queue.new(), waiting: MapSet.new()},
        &%{&1 | names: MapSet.new(names)}
      )

    {:reply, :ok, monitor(%{state | consumers: consumers}, pid)}
  end

  def handle_call({:publish, messages}, _from, state) do
    consumers =
      Enum.reduce(messages, state.consumers, fn message, consumers ->
        Map.new(consumers, fn {name, consumer} ->
          if MapSet.member?(consumer.names, message.name),
            do: {name, %{consumer | queue: :queue.in(message, consumer.queue)}},
            else: {name, consumer}
        end)
      end)

    {:reply, :ok, wake(%{state | consumers: consumers})}
  end

  # A consumer that sent itself `:take` before this broker restarted asks it for a
  # name it has never heard of; it is told so, and resubscribes when it restarts.
  def handle_call({:take, name}, _from, state) when not is_map_key(state.consumers, name),
    do: {:reply, {:error, :unsubscribed}, state}

  def handle_call({:take, name}, {pid, _tag}, state) do
    consumer = Map.fetch!(state.consumers, name)

    case :queue.out(consumer.queue) do
      {{:value, message}, queue} ->
        delivery = make_ref()
        consumers = Map.put(state.consumers, name, %{consumer | queue: queue})
        in_hand = Map.put(state.in_hand, delivery, {name, message, pid})
        {:reply, {:ok, delivery, message}, %{state | consumers: consumers, in_hand: in_hand}}

      {:empty, _queue} ->
        consumer = %{consumer | waiting: MapSet.put(consumer.waiting, pid)}
        {:reply, :empty, %{state | consumers: Map.put(state.consumers, name, consumer)}}
    end
  end

  def handle_call({:ack, delivery}, _from, state),
    do: {:reply, :ok, %{state | in_hand: Map.delete(state.in_hand, delivery)}}

  def handle_call({:nack, delivery}, _from, state) do
    case Map.pop(state.in_hand, delivery) do
      {{name, message, _pid}, in_hand} ->
        Process.send_after(self(), {:again, name, message}, state.retry_after)
        {:reply, :ok, %{state | in_hand: in_hand}}

      {nil, _in_hand} ->
        {:reply, :ok, state}
    end
  end

  @impl GenServer
  def handle_info({:again, name, message}, state),
    do: {:noreply, wake(update_queue(state, name, &:queue.in(message, &1)))}

  # What a consumer had in hand when it stopped comes back after `retry_after`, as a
  # nacked message does: a message that kills its consumer would otherwise be taken
  # again at once by the restarted one, and kill it again, faster than any
  # supervisor's restart intensity allows.
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {back, in_hand} =
      Enum.split_with(state.in_hand, fn {_delivery, {_n, _m, taker}} -> taker == pid end)

    for {_delivery, {name, message, _taker}} <- back,
        do: Process.send_after(self(), {:again, name, message}, state.retry_after)

    state = %{state | in_hand: Map.new(in_hand)}

    consumers =
      Map.new(state.consumers, fn {name, c} ->
        {name, %{c | waiting: MapSet.delete(c.waiting, pid)}}
      end)

    {:noreply,
     wake(%{state | consumers: consumers, monitored: MapSet.delete(state.monitored, pid)})}
  end

  defp update_queue(state, name, fun) do
    case state.consumers do
      %{^name => consumer} ->
        %{
          state
          | consumers: Map.put(state.consumers, name, %{consumer | queue: fun.(consumer.queue)})
        }

      _unknown ->
        state
    end
  end

  # Tells every process waiting on a queue that is no longer empty to take again.
  defp wake(state) do
    consumers =
      Map.new(state.consumers, fn {name, consumer} ->
        if :queue.is_empty(consumer.queue) do
          {name, consumer}
        else
          Enum.each(consumer.waiting, &send(&1, {__MODULE__, :ready}))
          {name, %{consumer | waiting: MapSet.new()}}
        end
      end)

    %{state | consumers: consumers}
  end

  defp monitor(state, pid) do
    if MapSet.member?(state.monitored, pid) do
      state
    else
      Process.monitor(pid)
      %{state | monitored: MapSet.put(state.monitored, pid)}
    end
  end
end
