defmodule EhOsContract.Subscription.Runner do
  # The process that feeds one subscription (v2 §12), on every node: it runs
  # `EhOsContract.Subscription.step/2` until there is nothing to read, then waits.
  #
  # It wakes on a notification after a commit, on Oban's notifier, and polls every
  # second besides, which covers a transaction the host's code owned and a notification
  # lost on the way. Dispatch sends one after a transaction it owns; inside a
  # transaction the engine owns — an inbox taking a message, a runner's step, a timer
  # firing — what was appended is marked (`notify_on_commit/0`), and the engine's
  # `transaction/2` sends it once that commits. Two nodes
  # running the same subscription do not collide: a step takes the row `FOR UPDATE
  # SKIP LOCKED`, and the node that gets nothing waits for the next wake.
  #
  # An event that fails is retried after a pause that doubles with each attempt, and
  # a step that raises for another reason — the database gone, say — is logged and
  # retried after five seconds, so a runner never takes the host's tree down with it.
  # A relay whose transport does not take a batch tries again after five seconds too,
  # with no attempt counted (`EhOsContract.Relay`).
  @moduledoc false

  use GenServer

  alias EhOsContract.{Implementations, Subscription}

  require Logger

  @channel :eh_os_contract
  @pending {__MODULE__, :notify_on_commit}
  @poll 1_000
  @after_crash 5_000
  @unavailable 5_000

  @doc false
  @spec start_link(String.t()) :: GenServer.on_start()
  def start_link(key), do: GenServer.start_link(__MODULE__, key)

  @doc false
  @spec child_spec(String.t()) :: Supervisor.child_spec()
  def child_spec(key), do: %{id: {__MODULE__, key}, start: {__MODULE__, :start_link, [key]}}

  @doc """
  Wakes every runner, on every node, through Oban's notifier. `transaction/2` calls it
  once a transaction that marked an append commits. A host without a running notifier
  loses nothing but the wake: runners poll.
  """
  @spec notify() :: :ok
  def notify do
    _ = Oban.Notifier.notify(Oban, @channel, %{})
    :ok
  catch
    _kind, _reason -> :ok
  end

  @doc """
  Marks that the transaction this process is in appended something a runner reads, so
  that `transaction/2` around it wakes the runners once it commits. Inside a
  transaction the host's code owns the mark is never read: the runners poll.
  """
  @spec notify_on_commit() :: :ok
  def notify_on_commit do
    Process.put(@pending, true)
    :ok
  end

  @doc """
  Runs `fun` in a transaction of `repo`, as `c:Ecto.Repo.transaction/2`, and wakes
  every runner once it commits if anything inside marked an append
  (`notify_on_commit/0`). Inside another transaction it only runs `fun`: the mark is
  left to whoever commits.
  """
  @spec transaction(module(), (-> result)) :: {:ok, result} | {:error, term()}
        when result: term()
  def transaction(repo, fun) do
    if repo.in_transaction?() do
      repo.transaction(fun)
    else
      # A mark left by a transaction that never came here — the host's own, or one
      # rolled back — is not this one's.
      Process.delete(@pending)

      try do
        with {:ok, _} = committed <- repo.transaction(fun) do
          if Process.get(@pending), do: notify()
          committed
        end
      after
        Process.delete(@pending)
      end
    end
  end

  @typedoc false
  @type state :: %{
          key: String.t(),
          timer: reference() | nil,
          resting: boolean(),
          waiting: pos_integer() | nil
        }

  @doc "Listens for dispatch's notification, and runs the subscription `key` at once."
  @impl GenServer
  @spec init(String.t()) :: {:ok, state()}
  def init(key) do
    try do
      Oban.Notifier.listen(Oban, [@channel])
    catch
      _kind, _reason -> :ok
    end

    {:ok, schedule(%{key: key, timer: nil, resting: false, waiting: nil}, 0)}
  end

  @doc "Runs the subscription on a notification or its own timer; ignores anything else."
  @impl GenServer
  @spec handle_info(term(), state()) :: {:noreply, state()}
  # A runner that paused after a failure or an unreachable transport waits the pause
  # out: every dispatch notifies, and would otherwise make it try again at once.
  def handle_info({:notification, @channel, _payload}, %{resting: true} = state),
    do: {:noreply, state}

  # One run reads everything the notifications waiting behind this one announce: a
  # runner catching up on a backlog is sent one per commit, its own among them.
  def handle_info({:notification, @channel, _payload}, state) do
    flush_notifications()
    {:noreply, run(state)}
  end

  def handle_info(:run, state), do: {:noreply, run(%{state | timer: nil, resting: false})}
  def handle_info(_other, state), do: {:noreply, state}

  defp flush_notifications do
    receive do
      {:notification, @channel, _payload} -> flush_notifications()
    after
      0 -> :ok
    end
  end

  defp run(state) do
    case Implementations.consumer(state.key) do
      nil ->
        state

      consumer ->
        case catch_up(consumer, repo()) do
          {:waiting, position} ->
            %{schedule(waiting(state, position), @unavailable) | resting: true}

          {:rest, after_ms} ->
            %{schedule(state, after_ms) | resting: true, waiting: nil}

          after_ms ->
            %{schedule(state, after_ms) | waiting: nil}
        end
    end
  rescue
    exception -> crashed(state, inspect(exception.__struct__))
  catch
    # The kind only: a thrown value or an exit's reason may carry what was read.
    kind, _reason -> crashed(state, inspect(kind))
  end

  defp crashed(state, what) do
    Logger.error(
      "subscription #{state.key}: the runner failed outside a step " <>
        "(#{what}); it runs again in #{@after_crash} ms"
    )

    %{schedule(state, @after_crash) | resting: true}
  end

  # Steps until there is nothing to read; returns how long to wait before the next.
  defp catch_up(consumer, repo) do
    case Subscription.step(repo, consumer) do
      {:applied, _n} ->
        catch_up(consumer, repo)

      {:failed, _position} ->
        attempts =
          case repo.get(EhOsContract.SubscriptionRecord, consumer.key) do
            %{attempts: attempts} -> attempts
            nil -> 1
          end

        {:rest, min(100 * Integer.pow(2, attempts), 30_000)}

      # A relay whose transport did not take the batch: nothing moved, and no attempt
      # is counted, so it tries again after a pause rather than stopping.
      {:unavailable, position} ->
        Logger.warning(
          "subscription #{consumer.key}: the bus did not take the batch from position " <>
            "#{position}; it tries again in #{@unavailable} ms"
        )

        {:rest, @unavailable}

      # Plan W1: newer code wrote the event; nothing moved and no attempt is counted,
      # so it waits for this node to be upgraded rather than stopping.
      {:waiting, position} ->
        {:waiting, position}

      :idle ->
        @poll
    end
  end

  # Said once per position, not every 5 s: a node left on older code for a whole deploy
  # would otherwise fill the log with one warning per consumer every few seconds.
  defp waiting(%{waiting: position} = state, position), do: state

  defp waiting(state, position) do
    Logger.warning(
      "subscription #{state.key}: the event at position #{position} was written by newer " <>
        "code than this node runs (EhOsContract.NewerSchemaError); it waits there, trying " <>
        "every #{@unavailable} ms, until this node runs that code"
    )

    %{state | waiting: position}
  end

  defp schedule(state, after_ms) do
    if state.timer, do: Process.cancel_timer(state.timer)
    %{state | timer: Process.send_after(self(), :run, after_ms)}
  end

  defp repo, do: EhOsContract.Config.fetch!(:repo)
end
