defmodule EhOsContract.Inbox.Keeper do
  @moduledoc """
  Keeps one inbox's consumer running, as the engine's child for it
  (`EhOsContract.Inbox`, "When it subscribes").

  It starts the adapter's child, `EhOsContract.Bus.consumer/1`, in its own `init`, so
  a reachable transport is subscribed before the engine starts any relay. A child that
  stops is started again at once, as a supervisor would; one that does not start, or
  stops again within the pause, is logged and started again five seconds later. So a
  transport that refuses neither stops the boot nor, by a supervisor's restart
  intensity, takes every runner and relay down with it, as a relay with no bus waits
  rather than refusing. A child that answers `:ignore` declines to run, and is left
  alone.

  Stopped, it stops its child first and waits for it as long as the child's own
  `shutdown` says, as a supervisor would, so a delivery in hand finishes before the
  host's repo goes.

  Its own warnings name the kind of failure, never the reason, which may carry a
  connection's options. What OTP reports of the adapter's child itself is the
  adapter's (`EhOsContract.Bus`, `c:EhOsContract.Bus.consumer/2`).
  """

  use GenServer

  alias EhOsContract.{Bus, Inbox}

  require Logger

  @again 5_000

  @doc false
  @spec child_spec(EhOsContract.Implementations.inbox()) :: Supervisor.child_spec()
  def child_spec(inbox) do
    # It waits for its child in `terminate/2`, as long as the child's `shutdown` says.
    %{
      id: {__MODULE__, inbox.key},
      start: {__MODULE__, :start_link, [inbox]},
      shutdown: :infinity
    }
  end

  @doc false
  @spec start_link(EhOsContract.Implementations.inbox()) :: GenServer.on_start()
  def start_link(inbox), do: GenServer.start_link(__MODULE__, inbox)

  @impl GenServer
  def init(inbox) do
    # The child is linked, so its exit arrives here as a message; the parent's exit
    # reaches `terminate/2`, which stops the child first.
    Process.flag(:trap_exit, true)
    {:ok, start(%{inbox: inbox, child: nil, shutdown: 5_000, started_at: nil})}
  end

  @impl GenServer
  def handle_info(:start, %{child: nil} = state), do: {:noreply, start(state)}
  def handle_info(:start, state), do: {:noreply, state}

  # A child that ran for a while is started again at once, as a supervisor would; one
  # that stops again within the pause waits it out, so it cannot loop.
  def handle_info({:EXIT, child, reason}, %{child: child} = state) do
    state = %{state | child: nil}

    if System.monotonic_time(:millisecond) - state.started_at >= @again do
      {:noreply, start(state)}
    else
      again(state, "stopped (#{kind(reason)})")
      {:noreply, state}
    end
  end

  # A child that failed in its own start sends its exit as well, after the start
  # returned the error.
  def handle_info(_other, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, %{child: child, shutdown: shutdown}) when is_pid(child) do
    Process.exit(child, :shutdown)

    receive do
      {:EXIT, ^child, _reason} -> :ok
    after
      shutdown ->
        Process.exit(child, :kill)

        receive do
          {:EXIT, ^child, _reason} -> :ok
        end
    end
  end

  def terminate(_reason, _state), do: :ok

  defp start(state) do
    spec = Supervisor.child_spec(Bus.consumer(Inbox.consumer(state.inbox)), [])
    %{start: {module, function, args}} = spec

    shutdown =
      Map.get(
        spec,
        :shutdown,
        if(Map.get(spec, :type) == :supervisor, do: :infinity, else: 5_000)
      )

    case apply(module, function, args) do
      {:ok, child} when is_pid(child) -> started(state, child, shutdown)
      {:ok, child, _info} when is_pid(child) -> started(state, child, shutdown)
      :ignore -> state
      other -> failed(state, "did not start (#{kind(other)})")
    end
  catch
    kind, reason -> failed(state, "did not start (#{kind} #{kind(reason)})")
  end

  defp started(state, child, shutdown),
    do: %{
      state
      | child: child,
        shutdown: shutdown,
        started_at: System.monotonic_time(:millisecond)
    }

  defp failed(state, what) do
    again(state, what)
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
