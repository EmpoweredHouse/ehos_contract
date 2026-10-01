defmodule EhOsContract.Inbox.Keeper do
  @moduledoc """
  Keeps one inbox's consumer running, as the engine's child for it
  (`EhOsContract.Inbox`, "When it subscribes").

  It starts the adapter's child, `EhOsContract.Bus.consumer/1`, in its own `init`, so
  a reachable transport is subscribed before the engine starts any relay. A child that
  does not start, or stops, is logged and started again five seconds later: a
  transport that is down neither stops the boot nor, by a supervisor's restart
  intensity, takes every runner and relay down with it, as a relay with no bus waits
  rather than refusing. What it logs is the kind of failure, never its reason, which
  may carry a connection's options.
  """

  use GenServer

  alias EhOsContract.{Bus, Inbox}

  require Logger

  @again 5_000

  @doc false
  @spec child_spec(EhOsContract.Implementations.inbox()) :: Supervisor.child_spec()
  def child_spec(inbox),
    do: %{id: {__MODULE__, inbox.key}, start: {__MODULE__, :start_link, [inbox]}}

  @doc false
  @spec start_link(EhOsContract.Implementations.inbox()) :: GenServer.on_start()
  def start_link(inbox), do: GenServer.start_link(__MODULE__, inbox)

  @impl GenServer
  def init(inbox) do
    # The child is linked, so its exit arrives here as a message; the parent's exit
    # stops this process, and the child with it.
    Process.flag(:trap_exit, true)
    {:ok, start(%{inbox: inbox, child: nil})}
  end

  @impl GenServer
  def handle_info(:start, %{child: nil} = state), do: {:noreply, start(state)}
  def handle_info(:start, state), do: {:noreply, state}

  def handle_info({:EXIT, child, reason}, %{child: child} = state) do
    again(state, "stopped (#{kind(reason)})")
    {:noreply, %{state | child: nil}}
  end

  # A child that failed in its own start sends its exit as well, after the start
  # returned the error.
  def handle_info(_other, state), do: {:noreply, state}

  defp start(state) do
    %{start: {module, function, args}} =
      Supervisor.child_spec(Bus.consumer(Inbox.consumer(state.inbox)), [])

    case apply(module, function, args) do
      {:ok, child} when is_pid(child) ->
        %{state | child: child}

      other ->
        again(state, "did not start (#{kind(other)})")
        state
    end
  catch
    kind, reason ->
      again(state, "did not start (#{kind} #{kind(reason)})")
      state
  end

  defp again(state, what) do
    Logger.warning(
      "inbox #{state.inbox.key}: its consumer #{what}; it starts again in #{@again} ms"
    )

    Process.send_after(self(), :start, @again)
  end

  defp kind({:error, reason}), do: kind(reason)
  defp kind({:shutdown, reason}), do: kind(reason)
  defp kind(%module{}), do: inspect(module)
  defp kind({reason, _detail}) when is_atom(reason), do: inspect(reason)
  defp kind(reason) when is_atom(reason), do: inspect(reason)
  defp kind(_reason), do: "another reason"
end
