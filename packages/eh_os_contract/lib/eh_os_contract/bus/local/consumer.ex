defmodule EhOsContract.Bus.Local.Consumer do
  @moduledoc false

  # One durable consumer of `EhOsContract.Bus.Local`: it subscribes under the
  # consumer's name, then takes one message at a time and hands it to the handler.
  # Anything but `:ack` — `:nack`, another value, a raise, an exit, a throw — sends
  # the message back for later; all but `:nack`, which the handler chose, are logged.
  # What it logs of a failure names the message and the
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
    Process.monitor(server)
    :ok = GenServer.call(server, {:subscribe, consumer.name, consumer.names})
    send(self(), :take)
    {:ok, %{server: server, consumer: consumer}}
  end

  @impl GenServer
  def handle_info(signal, state) when signal in [:take, {EhOsContract.Bus.Local, :ready}] do
    case GenServer.call(state.server, {:take, state.consumer.name}) do
      {:ok, delivery, message} ->
        verdict =
          deliver(state.consumer, %Message{message | payload: Jason.decode!(message.payload)})

        :ok = GenServer.call(state.server, {verdict, delivery})
        send(self(), :take)

      :empty ->
        :ok
    end

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _server, reason}, state), do: {:stop, reason, state}

  defp deliver(consumer, message) do
    case consumer.handler.(message) do
      verdict when verdict in [:ack, :nack] ->
        verdict

      other ->
        failed(consumer, message, "returned #{inspect(verdict_kind(other))}")
    end
  catch
    kind, reason ->
      failed(consumer, message, "#{kind} #{inspect(reason_kind(reason))}")
  end

  defp failed(consumer, message, what) do
    Logger.warning(
      "bus consumer #{consumer.name}: #{message.name} #{message.id} is delivered again later, " <>
        "its handler #{what}"
    )

    :nack
  end

  defp verdict_kind(other) when is_atom(other), do: other
  defp verdict_kind(other) when is_tuple(other), do: {:tuple, tuple_size(other)}
  defp verdict_kind(_other), do: :other

  defp reason_kind(%module{}), do: module
  defp reason_kind(reason) when is_atom(reason), do: reason
  defp reason_kind(_reason), do: :other
end
