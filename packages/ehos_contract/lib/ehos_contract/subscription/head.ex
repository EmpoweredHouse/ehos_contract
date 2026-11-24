defmodule EhosContract.Subscription.Head do
  # The poll of the subscription runners, one process per node (#635). Every `poll:` it
  # reads the head of the log and every subscription's row, with two plain SELECTs
  # outside any transaction and without logging, and wakes only the runners that have
  # something to do. An idle runner therefore starts no transaction: a step takes its
  # row `FOR UPDATE SKIP LOCKED`, and that lock writes the row even when nothing is new.
  #
  # A runner is woken when its row is behind the head (`Subscription.due?/2`) and the
  # head or the row changed since this process last woke it. The second condition is
  # what keeps it quiet: a consumer of a few types stays behind the head of the whole
  # log between its events, and one look at what was appended is enough. A change to
  # the row — a rebuild, a skip, a step on another node — wakes it again.
  #
  # A runner resting after a failure, an unreachable transport or an event written by
  # newer code ignores the wake and keeps its own timer. Notifications after a commit
  # still wake every runner at once (`EhosContract.Subscription.Runner`): this is the
  # safety net under them, for an append in a transaction the host owns and a
  # notification lost on the way.
  #
  # It finds the runner of a row among the children of the runners' supervisor, named
  # by `runners:`: a runner restarted there is found at the next poll, with nothing for
  # it to register again.
  #
  # Each poll also sends every subscription's lag as `[:ehos_contract, :subscription,
  # :lag]`, documented in `docs/subscriptions.md`.
  @moduledoc false

  use GenServer

  import Ecto.Query

  alias EhosContract.{Event, Subscription, SubscriptionRecord}

  require Logger

  @runners EhosContract.Subscription.Runners
  @poll 30_000

  @typedoc false
  @type state :: %{
          repo: module(),
          poll: pos_integer(),
          runners: GenServer.name(),
          woken: %{String.t() => term()},
          failing: boolean()
        }

  @doc false
  @spec runners() :: atom()
  def runners, do: @runners

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc """
  Takes `repo:`, `poll:` (milliseconds, 30,000 by default) and `runners:`, the name of
  the runners' supervisor, and polls at once.
  """
  @impl GenServer
  @spec init(keyword()) :: {:ok, state()}
  def init(opts) do
    state = %{
      repo: Keyword.fetch!(opts, :repo),
      poll: Keyword.get(opts, :poll, @poll),
      runners: Keyword.get(opts, :runners, @runners),
      woken: %{},
      failing: false
    }

    send(self(), :poll)
    {:ok, state}
  end

  @doc "Polls on its own timer; ignores anything else."
  @impl GenServer
  @spec handle_info(term(), state()) :: {:noreply, state()}
  # The next poll is set once this one ends: on a slow database, a timer set before it
  # would have fired already, and the polls would hold a connection back to back.
  def handle_info(:poll, state) do
    state = poll(state)
    Process.send_after(self(), :poll, state.poll)
    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp poll(state) do
    head = state.repo.one(from(e in Event, select: coalesce(max(e.position), 0)), log: false)
    rows = state.repo.all(SubscriptionRecord, log: false)
    Enum.each(rows, &lag(&1, head))
    pids = running(state.runners)
    %{state | woken: Map.new(rows, &wake(&1, head, state.woken, pids)), failing: false}
  rescue
    exception -> failed(state, inspect(exception.__struct__))
  catch
    # The kind only, as a runner does: an exit's reason may carry what was read.
    kind, _reason -> failed(state, inspect(kind))
  end

  # Said once until a poll succeeds again: a database gone for a minute would otherwise
  # write sixty of them.
  defp failed(%{failing: true} = state, _what), do: state

  defp failed(state, what) do
    Logger.error(
      "subscriptions: the poll could not read the head of the log (#{what}); it tries " <>
        "again every #{state.poll} ms"
    )

    %{state | failing: true}
  end

  # A supervisor restarting its children is not there for a moment: the next poll
  # finds them. One that is not there, or stops during the call, exits the call, which
  # is caught here rather than by `poll/1`: the head of the log was read.
  defp running(runners) do
    for {{Subscription.Runner, key}, pid, _type, _modules} <- Supervisor.which_children(runners),
        is_pid(pid),
        into: %{},
        do: {key, pid}
  catch
    :exit, _reason -> %{}
  end

  defp wake(row, head, woken, pids) do
    seen = {head, row.status, row.position, row.updated_at}
    pid = Map.get(pids, row.name)

    # A row of a consumer this node does not run has no pid here.
    if pid != nil and Subscription.due?(row, head) and Map.get(woken, row.name) != seen,
      do: send(pid, :wake)

    {row.name, seen}
  end

  # A read model dispatch projects keeps no position the runner moves, so it has no lag
  # to report until it is rebuilt.
  defp lag(%{mode: "inline", status: "running"}, _head), do: :ok
  defp lag(%{mode: "inline", status: "stale"}, _head), do: :ok

  defp lag(row, head) do
    :telemetry.execute(
      [:ehos_contract, :subscription, :lag],
      %{lag: max(head - row.position, 0), position: row.position, head: head},
      %{subscription: row.name, status: row.status}
    )
  end
end
