defmodule EhOsContract.Subscription do
  # A consumer fed from the log in order (v2 §12): a read model or a policy delivered
  # `:at_least_once`, a process manager, a `publish`'s relay (`EhOsContract.Relay`),
  # and a read model delivered `:in_transaction` while it is rebuilt.
  # Its row in `eh_os_contract_subscriptions` holds the position of the last event it
  # applied.
  #
  # **One step is one transaction.** It takes the row `FOR UPDATE SKIP LOCKED`, so a
  # second runner, on this node or another, gets nothing instead of the same batch;
  # reads the next events of the consumer's types after the position; applies them;
  # and advances the position in the same transaction, so a batch is applied exactly
  # once. A batch is 500 events for a read model and 1 for a policy, because a policy
  # dispatches, takes the append lock before it decides, and a batch would hold the
  # lock throughout.
  #
  # **An event that fails is retried, then isolated, never skipped.** The failing
  # step rolls back, and the row records the event's position, the exception's module
  # and one more attempt. The next step applies what comes before that event, then
  # tries it alone. After three attempts the row is `failing` at that position and the
  # consumer stops there: an ordered consumer that skips is a read model that silently
  # lies. Skipping it, or rebuilding, is a person's decision
  # (`mix eh_os_contract.subscriptions`). The row keeps the status it failed in, and a
  # skip goes back to it (issue #550): a rebuild interrupted by a failure goes on
  # rebuilding past the skipped event, and a process manager's replay goes on without
  # reacting. Back at `running`, an inline read model would never read the rest of the
  # log, since dispatch projects only what it appends, and a process manager would
  # react to the history left in it. Dispatch leaves a failing inline read model alone,
  # as a rebuilding one, since it failed in a rebuild: what it would project, the
  # runner takes after the skip.
  #
  # **Rebuild.** A read model whose declaration changed — its version is the digest of
  # the declaration and of every event it takes — is `stale` from the next
  # registration, and goes on taking events until it is rebuilt. `rebuild/2` empties it through its `reset/0` and replays the log: one
  # delivered `:at_least_once` starts again from position 0; one delivered
  # `:in_transaction` is marked `rebuilding` under the append lock, so dispatch stops
  # projecting it, is caught up by steps, and goes back to `running` under the append
  # lock again, once nothing is left to read. A read model without `reset/0` cannot be
  # rebuilt and stays `stale`.
  #
  # **Where a new consumer starts.** What is in the log when a consumer is first
  # registered is history, and nothing new reacts to history by itself. A new policy
  # starts at the head of the log: it keeps no state, so replaying the log with its
  # reactions suppressed would come to the same position. A new process manager
  # replays the log with its reactions suppressed: it learns the runs already there and
  # steers none of them, and a timer of theirs that came due before the deploy is
  # dropped (`EhOsContract.ProcessManager.reconcile!/2`). A deploy onto a year of
  # history therefore issues nothing for that year. An ordered read model starts at
  # position 0 and takes the whole log, since projecting history is what it is for. An
  # inline read model starts at the head, since dispatch has been projecting it all
  # along; one added to a log that already has its events is rebuilt by hand.
  #
  # Reacting to history is a person's decision: `rebuild/2` of a policy moves it back
  # to position 0, and it reacts to every event from there, with the keys derived from
  # each event, so what it issued before is not issued twice.
  @moduledoc false

  import Ecto.Query

  alias EhOsContract.{Bus, Consumer, Implementations, Model, ProcessManager, Relay, Store}
  alias EhOsContract.SubscriptionRecord
  alias EhOsContract.Subscription.Runner

  require Logger

  @attempts 3

  # A stale subscription goes on taking events: it only waits to be rebuilt.
  @fed ~w(running stale rebuilding)

  @typedoc """
  What one step did. `{:unavailable, position}` is a relay's: the transport did not
  take the batch from `position` on, and nothing moved (`EhOsContract.Relay`).
  `{:waiting, position}`: the event at `position` was written with a newer version of
  its fields than this node declares (`EhOsContract.NewerSchemaError`, plan W1), so
  nothing moved and no attempt is counted until the node runs the newer code.
  """
  @type step ::
          :idle
          | {:applied, pos_integer()}
          | {:failed, pos_integer()}
          | {:unavailable, pos_integer()}
          | {:waiting, pos_integer()}

  @doc """
  Writes a row for every consumer in `consumers` that has none, and marks a read
  model whose version changed `stale` — a policy has nothing to rebuild, so its row
  just takes the new version. Returns the rows as they are now.
  """
  @spec register!(module(), [Implementations.consumer()]) :: [SubscriptionRecord.t()]
  def register!(repo, consumers \\ Implementations.subscribed()) do
    for consumer <- consumers do
      case repo.get(SubscriptionRecord, consumer.key) do
        nil ->
          repo.insert!(
            %SubscriptionRecord{
              name: consumer.key,
              kind: Atom.to_string(consumer.kind),
              mode: mode(consumer),
              version: consumer.version,
              position: start(repo, consumer),
              status: first_status(consumer),
              updated_at: DateTime.utc_now()
            },
            on_conflict: :nothing
          )

          repo.get!(SubscriptionRecord, consumer.key)

        %{version: version} = row when version == consumer.version ->
          row

        %{status: status} = row
        when consumer.kind in [:read_model, :process_manager] and status != "rebuilding" ->
          repo.update!(SubscriptionRecord.changeset(row, %{status: "stale", resume_status: nil}))

        row ->
          repo.update!(SubscriptionRecord.changeset(row, %{version: consumer.version}))
      end
    end
  end

  defp mode(%{delivery: :in_transaction}), do: "inline"
  defp mode(_ordered), do: "ordered"

  # A policy starts at the head as an inline read model does, for another reason: what
  # is in the log is history, and it reacts to none of it (see the moduledoc). So does
  # a relay: nothing publishes history by itself.
  defp start(repo, consumer)
       when consumer.delivery == :in_transaction or consumer.kind in [:policy, :relay],
       do: repo.one(from(e in EhOsContract.Event, select: coalesce(max(e.position), 0)))

  defp start(_repo, _ordered), do: 0

  # A new process manager learns the runs already in the log by a replay, so it steers
  # none of them: a deploy onto a year of history issues nothing for that year.
  defp first_status(%{kind: :process_manager}), do: "rebuilding"
  defp first_status(_consumer), do: "running"

  @doc """
  One step of `consumer` (see the moduledoc): `:idle` when another runner holds it,
  it is not running, or nothing is left to read; `{:applied, n}`; or `{:failed,
  position}` when the event at `position` raised and the step rolled back.
  """
  @spec step(module(), Implementations.consumer()) :: step()
  def step(repo, consumer) do
    # A relay with no bus has nothing to do, and needs no transaction and no lock on
    # its row to find that out, every second and on every dispatch.
    if consumer.kind == :relay and Bus.adapter() == nil,
      do: :idle,
      else: stepped(repo, consumer)
  end

  # A policy's or a process manager's commands wake the runners once the step commits.
  defp stepped(repo, consumer) do
    result =
      Runner.transaction(repo, fn ->
        case take(repo, consumer.key, fed(consumer)) do
          nil -> :idle
          row -> apply_next(repo, consumer, row)
        end
      end)

    case result do
      {:ok, :at_head} ->
        caught_up!(repo, consumer)

      # A relay's batch went one event at a time: what passed is committed, and the
      # event that raised is recorded as a failure of its own.
      {:ok, {:applied_then_failed, _applied, position, exception}} ->
        failed!(repo, consumer, position, exception)
        {:failed, position}

      {:ok, step} ->
        step

      {:error, {:waiting, position}} ->
        {:waiting, position}

      {:error, {:failed, position, exception}} ->
        failed!(repo, consumer, position, exception)
        {:failed, position}
    end
  end

  # A relay publishes what it read, and moves only once the transport holds it
  # (`EhOsContract.Relay`); `step/2` has already seen that a bus is configured.
  defp apply_next(repo, %{kind: :relay} = consumer, row) do
    with [first | _] = events <-
           fenced(
             Store.read_all(repo, row.position, Relay.batch(), Map.keys(consumer.callbacks)),
             row
           ) do
      case relay(consumer, events) do
        :ok ->
          advance!(repo, row, List.last(events).position)
          {:applied, length(events)}

        {:error, _reason} ->
          {:unavailable, first.position}

        {:waiting, position} when position == first.position ->
          {:waiting, position}

        # Those before the newer event go, one at a time, and the relay waits at it.
        {:waiting, _position} ->
          one_by_one(repo, consumer, row, events, 0)

        {:raised, exception} when length(events) == 1 ->
          repo.rollback({:failed, first.position, exception})

        {:raised, _exception} ->
          one_by_one(repo, consumer, row, events, 0)
      end
    else
      _nothing -> :idle
    end
  end

  defp apply_next(repo, consumer, row) do
    types = Map.keys(consumer.callbacks)

    # A policy dispatches inside this transaction, where dispatch does not retry a
    # conflict. Holding the append lock from before the decision means no stream can
    # move under it, as inside a dispatch transaction; otherwise another writer of the
    # same stream would count as a failure of the event, and three would stop it.
    # A process manager's replay dispatches nothing, so it takes neither the lock nor
    # one event at a time.
    replay? = consumer.kind == :process_manager and row.status == "rebuilding"
    if consumer.kind in [:policy, :process_manager] and not replay?, do: :ok = Store.lock(repo)
    batch = if replay?, do: 500, else: batch(consumer)

    case fenced(Store.read_all(repo, row.position, batch, types), row) do
      [] when row.status == "rebuilding" ->
        :at_head

      [] ->
        :idle

      events ->
        # Plan W1: a batch stops before a newer row, so what precedes it commits and
        # the next step waits at it, as a relay does; rolled back with it, the same
        # batch would be read and undone again until this node is upgraded.
        case Enum.split_while(events, &(not Consumer.newer?(&1))) do
          {[], [newer | _]} ->
            repo.rollback({:waiting, newer.position})

          {current, _rest} ->
            Enum.each(current, &apply!(repo, consumer, &1, row.status))
            advance!(repo, row, List.last(current).position)
            {:applied, length(current)}
        end
    end
  end

  # After a failure the events before the failing one are applied without it, and
  # then the failing one alone, so a failure never takes its predecessors with it.
  defp fenced(events, %{failed_position: nil}), do: events

  defp fenced([first | _] = events, %{failed_position: fence}) when first.position < fence,
    do: Enum.take_while(events, &(&1.position < fence))

  defp fenced(events, _row), do: Enum.take(events, 1)

  # `status` is the subscription's: a process manager being rebuilt replays without
  # reacting.
  defp apply!(repo, consumer, row, status) do
    consumer = Implementations.taking(consumer, row.type)
    chain = Map.get(row.metadata || %{}, "chain", [])

    handled =
      case consumer.kind do
        :process_manager ->
          ProcessManager.handle!(repo, consumer, row, chain, status == "rebuilding")

        _other ->
          Consumer.handle!(consumer, Consumer.decode!(row), chain)
      end

    case handled do
      :ok ->
        :ok

      {:error, reason} ->
        raise ArgumentError, "#{Consumer.label(consumer)} answered #{inspect(reason)}"
    end
  rescue
    # Plan W1: newer code wrote it; waiting is not a failure, and counts no attempt.
    _newer in EhOsContract.NewerSchemaError -> repo.rollback({:waiting, row.position})
    exception -> repo.rollback({:failed, row.position, exception})
  end

  # A batch that raised says nothing of which event is at fault, so it goes again one
  # event at a time: those before the culprit are published and passed, and the
  # culprit is the failure, counted where it is, as a policy's is.
  defp one_by_one(repo, consumer, row, [event | rest], applied) do
    case relay(consumer, [event]) do
      :ok ->
        advance!(repo, row, event.position)

        if rest == [],
          do: {:applied, applied + 1},
          else: one_by_one(repo, consumer, row, rest, applied + 1)

      {:error, _reason} when applied > 0 ->
        {:applied, applied}

      {:error, _reason} ->
        {:unavailable, event.position}

      {:waiting, _position} when applied > 0 ->
        {:applied, applied}

      {:waiting, position} ->
        {:waiting, position}

      {:raised, exception} when applied > 0 ->
        {:applied_then_failed, applied, event.position, exception}

      {:raised, exception} ->
        repo.rollback({:failed, event.position, exception})
    end
  end

  # A raise is a defect, and so is a throw, recorded as an `ErlangError` without the
  # thrown value; an exit is an adapter breaking `c:EhOsContract.Bus.publish/2`'s
  # promise to return an error instead.
  defp relay(consumer, events) do
    # Plan W1: a message carries the payload as stored, so an event written with
    # fields newer than this code declares would leave with the old meaning.
    # An older one goes out in the declared shape, as consumers read it (plan DD, V1, #333).
    model = Model.fetch(consumer.contract)
    Enum.each(events, &Consumer.current!(model, &1))
    Bus.publish(Enum.map(events, &Relay.message(consumer, Consumer.upcast(model, &1))))
  rescue
    newer in EhOsContract.NewerSchemaError -> {:waiting, newer.position}
    exception -> {:raised, exception}
  catch
    :exit, _reason -> {:error, :exit}
    :throw, _value -> {:raised, %ErlangError{original: :nocatch}}
  end

  defp advance!(repo, row, position) do
    changes =
      if row.failed_position && position >= row.failed_position,
        do: %{
          position: position,
          failed_position: nil,
          failure: nil,
          attempts: 0,
          resume_status: nil
        },
        else: %{position: position}

    repo.update!(SubscriptionRecord.changeset(row, changes))
  end

  # A process manager at the head of its replay: back to `running`, with every
  # pending timer scheduled again. Dispatch never feeds it, so no append lock.
  defp caught_up!(repo, %{kind: :process_manager} = consumer) do
    {:ok, step} =
      repo.transaction(fn ->
        case take(repo, consumer.key, ["rebuilding"], :wait) do
          nil ->
            :idle

          row ->
            repo.update!(SubscriptionRecord.changeset(row, %{status: "running"}))
            ProcessManager.reconcile!(repo, consumer)
            {:applied, 0}
        end
      end)

    step
  end

  # A rebuilding inline read model at the head: back to `running` under the append
  # lock, after whatever was appended since the last read, so dispatch projects the
  # next event and no event falls between the runner and dispatch. Its own
  # transaction, taking the append lock before the row's — the order dispatch and
  # `rebuild/2` take them in; holding the row from the step first could deadlock with
  # a rebuild.
  defp caught_up!(repo, consumer) do
    result =
      repo.transaction(fn ->
        :ok = Store.lock(repo)

        case take(repo, consumer.key, ["rebuilding"], :wait) do
          # Another runner handed it back first.
          nil ->
            :idle

          row ->
            tail = Store.read_all(repo, row.position, 1_000_000, Map.keys(consumer.callbacks))
            Enum.each(tail, &apply!(repo, consumer, &1, row.status))
            position = if tail == [], do: row.position, else: List.last(tail).position
            changes = %{position: position, status: "running"}
            repo.update!(SubscriptionRecord.changeset(row, changes))
            {:applied, length(tail)}
        end
      end)

    case result do
      {:ok, step} ->
        step

      {:error, {:waiting, position}} ->
        {:waiting, position}

      {:error, {:failed, position, exception}} ->
        failed!(repo, consumer, position, exception)
        {:failed, position}
    end
  end

  defp failed!(repo, consumer, position, exception) do
    repo.transaction(fn ->
      with %{} = row <- take(repo, consumer.key, fed(consumer)) do
        attempts = if row.failed_position == position, do: row.attempts + 1, else: 1
        failing = attempts >= @attempts

        changes = %{
          failed_position: position,
          failure: inspect(exception.__struct__),
          attempts: attempts
        }

        changes =
          if failing,
            do: Map.merge(changes, %{status: "failing", resume_status: row.status}),
            else: changes

        repo.update!(SubscriptionRecord.changeset(row, changes))

        # The module only: a message may quote the event's values (v2 §17).
        if failing do
          Logger.error(
            "subscription #{consumer.key} is failing at position #{position} after " <>
              "#{attempts} attempts (#{inspect(exception.__struct__)}); it stops there " <>
              "until someone skips the event or rebuilds it"
          )
        end
      end
    end)
  end

  @doc """
  Empties `key`'s read model through its `reset/0`, or forgets every run of a
  process manager, and replays the log into it; moves a policy back to position 0,
  so it reacts to the whole log (see the moduledoc). `{:error, :no_reset}` for a
  read model without `reset/0`.
  """
  @spec rebuild(module(), String.t()) :: :ok | {:error, :no_reset | :not_registered}
  def rebuild(repo, key) do
    consumer = Implementations.consumer(key)

    cond do
      consumer == nil or repo.get(SubscriptionRecord, key) == nil ->
        {:error, :not_registered}

      consumer.kind == :read_model and
          not (consumer.module && function_exported?(consumer.module, :reset, 0)) ->
        {:error, :no_reset}

      true ->
        {:ok, :ok} =
          repo.transaction(fn ->
            if consumer.delivery == :in_transaction, do: :ok = Store.lock(repo)
            row = take(repo, key, ~w(running stale rebuilding failing), :wait)
            # A process manager replays with its reactions suppressed, so it is
            # `rebuilding` until the head, where its timers are scheduled again.
            status =
              case consumer do
                %{kind: :process_manager} ->
                  :ok = ProcessManager.reset!(repo, consumer)
                  "rebuilding"

                %{delivery: :in_transaction} ->
                  :ok = consumer.module.reset()
                  "rebuilding"

                # Nothing to empty: its keys keep what it already issued from being
                # issued again, and a relay's ids what it already published from
                # counting twice at the subscriber.
                %{kind: kind} when kind in [:policy, :relay] ->
                  "running"

                _ordered ->
                  :ok = consumer.module.reset()
                  "running"
              end

            repo.update!(
              SubscriptionRecord.changeset(row, %{
                position: 0,
                status: status,
                version: consumer.version,
                failed_position: nil,
                failure: nil,
                attempts: 0,
                resume_status: nil
              })
            )

            :ok
          end)

        :ok
    end
  end

  @doc """
  Moves a `failing` subscription past the event it fails on, and runs it again in the
  status it failed in: one that failed while it was rebuilt goes on rebuilding. The
  event is never applied: this is for a person who decided it should not be.
  """
  @spec skip(module(), String.t()) :: :ok | {:error, :not_failing | :not_registered}
  def skip(repo, key) do
    {:ok, result} =
      repo.transaction(fn ->
        case take(repo, key, ["failing"], :wait) do
          nil ->
            not_failing(repo, key)

          # A row that was failing before storage version 5 says nothing of its status.
          row ->
            repo.update!(
              SubscriptionRecord.changeset(row, %{
                position: row.failed_position,
                status: row.resume_status || "running",
                failed_position: nil,
                failure: nil,
                attempts: 0,
                resume_status: nil
              })
            )

            :ok
        end
      end)

    result
  end

  defp not_failing(repo, key) do
    if repo.get(SubscriptionRecord, key),
      do: {:error, :not_failing},
      else: {:error, :not_registered}
  end

  @doc "Every subscription row, by name."
  @spec all(module()) :: [SubscriptionRecord.t()]
  def all(repo), do: repo.all(from(s in SubscriptionRecord, order_by: s.name))

  defp take(repo, key, statuses, mode \\ :skip) do
    query = from(s in SubscriptionRecord, where: s.name == ^key and s.status in ^statuses)

    case mode do
      :skip -> repo.one(lock(query, "FOR UPDATE SKIP LOCKED"))
      :wait -> repo.one(lock(query, "FOR UPDATE"))
    end
  end

  # Dispatch projects an inline read model; a runner only while it is rebuilt.
  defp fed(%{delivery: :in_transaction}), do: ["rebuilding"]
  defp fed(_ordered), do: @fed

  defp batch(%{kind: :read_model}), do: 500
  defp batch(_dispatches), do: 1
end
