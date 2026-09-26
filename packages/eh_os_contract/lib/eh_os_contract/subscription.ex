defmodule EhOsContract.Subscription do
  @moduledoc """
  A consumer fed from the log in order (v2 §12): a read model or a policy delivered
  `:at_least_once`, and a read model delivered `:in_transaction` while it is rebuilt.
  Its row in `eh_os_contract_subscriptions` holds the position of the last event it
  applied.

  **One step is one transaction.** It takes the row `FOR UPDATE SKIP LOCKED`, so a
  second runner, on this node or another, gets nothing instead of the same batch;
  reads the next events of the consumer's types after the position; applies them;
  and advances the position in the same transaction, so a batch is applied exactly
  once. A batch is 500 events for a read model and 1 for a policy, because a policy
  dispatches, takes the append lock before it decides, and a batch would hold the
  lock throughout.

  **An event that fails is retried, then isolated, never skipped.** The failing
  step rolls back, and the row records the event's position, the exception's module
  and one more attempt. The next step applies what comes before that event, then
  tries it alone. After three attempts the row is `failing` at that position and the
  consumer stops there: an ordered consumer that skips is a read model that silently
  lies. Skipping it, or rebuilding, is a person's decision
  (`mix eh_os_contract.subscriptions`).

  **Rebuild.** A read model whose declaration changed — its version is the digest of
  the declaration and of every event it takes — is `stale` from the next
  registration, and goes on taking events until it is rebuilt. `rebuild/2` empties it through its `reset/0` and replays the log: one
  delivered `:at_least_once` starts again from position 0; one delivered
  `:in_transaction` is marked `rebuilding` under the append lock, so dispatch stops
  projecting it, is caught up by steps, and goes back to `running` under the append
  lock again, once nothing is left to read. A read model without `reset/0` cannot be
  rebuilt and stays `stale`.

  **Where a new consumer starts.** An ordered one at position 0, so it takes the
  whole log — a new policy reacts to history, with keys derived from each event, as
  Commanded's handlers start from the origin by default. An inline read model at the
  head of the log, since dispatch has been projecting it all along; one added to a
  log that already has its events is rebuilt by hand.
  """

  import Ecto.Query

  alias EhOsContract.{Consumer, Implementations, ProcessManager, Store, SubscriptionRecord}

  require Logger

  @attempts 3

  # A stale subscription goes on taking events: it only waits to be rebuilt.
  @fed ~w(running stale rebuilding)

  @typedoc "What one step did."
  @type step :: :idle | {:applied, pos_integer()} | {:failed, pos_integer()}

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
              updated_at: DateTime.utc_now()
            },
            on_conflict: :nothing
          )

          repo.get!(SubscriptionRecord, consumer.key)

        %{version: version} = row when version == consumer.version ->
          row

        %{status: status} = row
        when consumer.kind in [:read_model, :process_manager] and status != "rebuilding" ->
          repo.update!(SubscriptionRecord.changeset(row, %{status: "stale"}))

        row ->
          repo.update!(SubscriptionRecord.changeset(row, %{version: consumer.version}))
      end
    end
  end

  defp mode(%{delivery: :in_transaction}), do: "inline"
  defp mode(_ordered), do: "ordered"

  defp start(repo, %{delivery: :in_transaction}),
    do: repo.one(from(e in EhOsContract.Event, select: coalesce(max(e.position), 0)))

  defp start(_repo, _ordered), do: 0

  @doc """
  One step of `consumer` (see the moduledoc): `:idle` when another runner holds it,
  it is not running, or nothing is left to read; `{:applied, n}`; or `{:failed,
  position}` when the event at `position` raised and the step rolled back.
  """
  @spec step(module(), Implementations.consumer()) :: step()
  def step(repo, consumer) do
    result =
      repo.transaction(fn ->
        case take(repo, consumer.key, fed(consumer)) do
          nil -> :idle
          row -> apply_next(repo, consumer, row)
        end
      end)

    case result do
      {:ok, :at_head} ->
        caught_up!(repo, consumer)

      {:ok, step} ->
        step

      {:error, {:failed, position, exception}} ->
        failed!(repo, consumer, position, exception)
        {:failed, position}
    end
  end

  defp apply_next(repo, consumer, row) do
    types = Map.keys(consumer.callbacks)

    # A policy dispatches inside this transaction, where dispatch does not retry a
    # conflict. Holding the append lock from before the decision means no stream can
    # move under it, as inside a dispatch transaction; otherwise another writer of the
    # same stream would count as a failure of the event, and three would stop it.
    if consumer.kind in [:policy, :process_manager], do: :ok = Store.lock(repo)

    case fenced(Store.read_all(repo, row.position, batch(consumer), types), row) do
      [] when row.status == "rebuilding" ->
        :at_head

      [] ->
        :idle

      events ->
        Enum.each(events, &apply!(repo, consumer, &1, row.status))
        last = List.last(events).position
        advance!(repo, row, last)
        {:applied, length(events)}
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
    exception -> repo.rollback({:failed, row.position, exception})
  end

  defp advance!(repo, row, position) do
    changes =
      if row.failed_position && position >= row.failed_position,
        do: %{position: position, failed_position: nil, failure: nil, attempts: 0},
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

        changes = if failing, do: Map.put(changes, :status, "failing"), else: changes
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
  process manager, and replays the log into it (see the moduledoc).
  `{:error, :no_reset}` for a read model without `reset/0`, `{:error,
  :not_a_read_model}` for a policy, which keeps nothing to rebuild.
  """
  @spec rebuild(module(), String.t()) ::
          :ok | {:error, :no_reset | :not_a_read_model | :not_registered}
  def rebuild(repo, key) do
    consumer = Implementations.consumer(key)

    cond do
      consumer == nil or repo.get(SubscriptionRecord, key) == nil ->
        {:error, :not_registered}

      consumer.kind == :policy ->
        {:error, :not_a_read_model}

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
                attempts: 0
              })
            )

            :ok
          end)

        :ok
    end
  end

  @doc """
  Moves a `failing` subscription past the event it fails on, and runs it again. The
  event is never applied: this is for a person who decided it should not be.
  """
  @spec skip(module(), String.t()) :: :ok | {:error, :not_failing}
  def skip(repo, key) do
    {:ok, result} =
      repo.transaction(fn ->
        case take(repo, key, ["failing"], :wait) do
          nil ->
            {:error, :not_failing}

          row ->
            repo.update!(
              SubscriptionRecord.changeset(row, %{
                position: row.failed_position,
                status: "running",
                failed_position: nil,
                failure: nil,
                attempts: 0
              })
            )

            :ok
        end
      end)

    result
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
