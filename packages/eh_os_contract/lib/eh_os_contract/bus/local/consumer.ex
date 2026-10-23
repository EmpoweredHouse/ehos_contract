defmodule EhOsContract.Bus.Local.Consumer do
  @moduledoc false

  # One durable consumer of `EhOsContract.Bus.Local`: it subscribes under the
  # consumer's name, then takes one message at a time and hands it to the handler.
  # Anything but `:ack` — `:nack`, another value, a raise, an exit, a throw, a linked
  # process crashing — sends the message back for later; all but `:nack`, which the
  # handler chose, are logged. What it logs of a failure names the message and the
  # kind of what failed, never a value: a payload has no personal field (D11), but a
  # handler's exception may carry whatever the handler held.

  use GenServer

  alias EhOsContract.Bus.Message

  require Logger

  @doc false
  @spec start_link(GenServer.server(), EhOsContract.Bus.consumer()) :: GenServer.on_start()
  def start_link(server, consumer), do: GenServer.start_link(__MODULE__, {server, consumer})

  @impl GenServer
  def init({server, consumer}) do
    broker = Process.monitor(server)
    :ok = GenServer.call(server, {:subscribe, consumer.name, consumer.names})
    send(self(), :take)
    {:ok, %{server: server, broker: broker, consumer: consumer, parent: parent()}}
  end

  @impl GenServer
  def handle_info(signal, state) when signal in [:take, {EhOsContract.Bus.Local, :ready}] do
    case GenServer.call(state.server, {:take, state.consumer.name}) do
      {:ok, delivery, message} ->
        {verdict, stop} = deliver(state, message)
        :ok = GenServer.call(state.server, {verdict, delivery})
        send(self(), :take)

        case stop do
          :continue -> {:noreply, state}
          {:stop, reason} -> {:stop, reason, state}
        end

      :empty ->
        {:noreply, state}

      {:error, :unsubscribed} ->
        {:stop, {:shutdown, :unsubscribed}, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _server, reason}, %{broker: ref} = state),
    do: {:stop, reason, state}

  # The handler runs in this process, so what it monitors or is sent lands here.
  def handle_info(_other, state), do: {:noreply, state}

  # Exits are trapped while the handler runs, as `EhOsContract.EffectJob` does it: a
  # process the handler linked to that crashes is a failed delivery, not a signal
  # that kills the consumer with the crash's reason in hand. The decoding is inside
  # too, since a message a transport cannot decode is a failed delivery as well.
  defp deliver(state, raw) do
    trapping = Process.flag(:trap_exit, true)

    verdict =
      try do
        %Message{} = raw
        message = %Message{raw | payload: Jason.decode!(raw.payload)}

        case state.consumer.handler.(message) do
          verdict when verdict in [:ack, :nack] -> verdict
          other -> failed(state.consumer, raw, "returned #{inspect(verdict_kind(other))}")
        end
      catch
        kind, reason -> failed(state.consumer, raw, "#{kind} #{inspect(reason_kind(reason))}")
      after
        Process.flag(:trap_exit, trapping)
      end

    exits(state, raw, verdict, :continue)
  end

  # What arrived while exits were trapped: a linked process's crash fails the
  # delivery; the parent's exit is honoured once the verdict is in.
  defp exits(state, raw, verdict, stop) do
    receive do
      {:EXIT, parent, reason} when parent == state.parent ->
        exits(state, raw, verdict, {:stop, reason})

      {:EXIT, _pid, :normal} ->
        exits(state, raw, verdict, stop)

      {:EXIT, _pid, reason} ->
        what = "had a linked process exit with #{inspect(reason_kind(reason))}"
        exits(state, raw, failed(state.consumer, raw, what), stop)
    after
      0 -> {verdict, stop}
    end
  end

  defp parent do
    case Process.get(:"$ancestors") do
      [parent | _] when is_pid(parent) -> parent
      [parent | _] when is_atom(parent) -> Process.whereis(parent)
      _none -> nil
    end
  end

  defp failed(consumer, message, what) do
    Logger.warning(
      "bus consumer #{inspect(consumer.name)}: #{inspect(message.name)} #{inspect(message.id)} " <>
        "is delivered again later, " <>
        "its handler #{what}"
    )

    :nack
  end

  defp verdict_kind(other) when is_atom(other), do: other
  defp verdict_kind(other) when is_tuple(other), do: {:tuple, tuple_size(other)}
  defp verdict_kind(_other), do: :other

  defp reason_kind(%module{}), do: module
  defp reason_kind({%module{}, stacktrace}) when is_list(stacktrace), do: module
  defp reason_kind({reason, stacktrace}) when is_atom(reason) and is_list(stacktrace), do: reason
  defp reason_kind(reason) when is_atom(reason), do: reason
  defp reason_kind(_reason), do: :other
end
