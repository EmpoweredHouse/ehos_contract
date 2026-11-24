defmodule EhosContract.Testing do
  @moduledoc """
  Helpers for a host's tests of what runs after the dispatch transaction.

  A test runs inside the Ecto SQL sandbox, where a runner in another process would
  not see its rows and a notification would never fire. So a test configures

      config :ehos_contract, subscriptions: :manual

  and nothing runs by itself: no runner starts, and the boot registers nothing. The
  test pushes the work through with `drain/1`, in its own process and its own
  sandbox transaction.

  **The first `drain/1` is the deploy.** It registers the subscriptions, and what is
  in the log by then is history: a new policy starts at the head of the log and
  reacts to none of it, a new process manager replays it without reacting, and a new
  read model takes all of it. A test of a policy's reaction drains once before it
  dispatches what the policy reacts to.
  """

  alias EhosContract.{Implementations, Subscription, SubscriptionRecord}

  @rounds 100

  @typedoc "What `drain/1` did."
  @type drained :: %{
          applied: non_neg_integer(),
          effects: non_neg_integer(),
          failing: [String.t()]
        }

  @doc """
  Runs everything that is waiting until nothing is: every subscription catches up
  with the head of the log, and every effect and timer job in Oban's `:events` queue
  runs, retries included, since either can append what the other then takes.
  Registers the subscription rows it needs first, inside the caller's transaction.

  **A timer fires only when it is due by `EhosContract.Clock.now/0`**; an earlier
  one snoozes and stays queued. To see a process manager's 24 hours pass, drain at
  the time the test chooses:

      EhosContract.Clock.at(DateTime.add(opened, 25 * 3600), fn ->
        EhosContract.Testing.drain()
      end)

  `only:` narrows it to the consumers with those keys (`"<contract id>:<kind>:<name>"`).
  Effect jobs are Oban's and run queue-wide, so with `only:` they run only when it
  names an effect.

  Returns how many events the subscriptions applied, how many jobs ran, and
  the keys of the subscriptions that are `failing` afterwards. Raises after #{@rounds}
  rounds that still found work, which is a cycle no guard caught.
  """
  @spec drain(keyword()) :: drained()
  def drain(opts \\ []) do
    repo = EhosContract.Config.fetch!(:repo)
    only = Keyword.get(opts, :only)
    wanted = fn key -> only == nil or key in List.wrap(only) end

    subscribed = Enum.filter(Implementations.subscribed(), &wanted.(&1.key))
    Subscription.register!(repo, subscribed)

    effects? =
      only == nil or
        Enum.any?(List.wrap(only), &match?(%{kind: :effect}, Implementations.consumer(&1)))

    totals = rounds(repo, subscribed, effects?, %{applied: 0, effects: 0}, @rounds)

    failing =
      for %SubscriptionRecord{status: "failing", name: name} <- Subscription.all(repo),
          wanted.(name),
          do: name

    Map.put(totals, :failing, failing)
  end

  defp rounds(_repo, _subscribed, _effects?, _totals, 0) do
    raise ArgumentError,
          "EhosContract.Testing.drain/1 still found work after #{@rounds} rounds: a consumer " <>
            "keeps producing what another takes, and no guard stopped it"
  end

  defp rounds(repo, subscribed, effects?, totals, left) do
    applied = Enum.sum(Enum.map(subscribed, &catch_up(repo, &1, 0)))
    ran = if effects?, do: effects(), else: 0
    totals = %{applied: totals.applied + applied, effects: totals.effects + ran}

    if applied == 0 and ran == 0,
      do: totals,
      else: rounds(repo, subscribed, effects?, totals, left - 1)
  end

  defp catch_up(repo, consumer, applied) do
    case Subscription.step(repo, consumer) do
      :idle -> applied
      :held -> applied
      {:applied, n} -> catch_up(repo, consumer, applied + n)
      {:failed, _position} -> catch_up(repo, consumer, applied)
      {:unavailable, _position} -> applied
      {:waiting, _position} -> applied
    end
  end

  defp effects do
    result = Oban.drain_queue(queue: :events, with_scheduled: true)
    result |> Map.drop([:snoozed]) |> Map.values() |> Enum.sum()
  end

  @doc """
  Asserts that every read model with a `table:` has a table its `Row` fits, in the
  database the configured repo reads: the table exists; each field has a column of
  the type the field is stored as, which takes `NULL` only where the field is
  optional or personal; and the primary key is the read model's `key:`. Call it in a
  host's test, where the test database has run every migration:

      test "the read models' tables fit their contracts" do
        EhosContract.Testing.assert_read_model_tables()
      end

  `contracts` are the contracts to check, every registered one by default. A column
  the read model does not declare is the projection's own and is let be, unless it is
  `NOT NULL` with no default, which no row written through `Row` fills.

  Raises `ExUnit.AssertionError` naming every table and every problem, so a field
  added to a contract and not to its migration fails here, not at the first write.
  Returns `:ok` otherwise. The table is read from `information_schema` of the current
  schema; a repo's `prefix:` is not followed.
  """
  @spec assert_read_model_tables([module()]) :: :ok
  def assert_read_model_tables(contracts \\ EhosContract.Registry.contracts()) do
    repo = EhosContract.Config.fetch!(:repo)

    problems =
      for table <- EhosContract.ReadModelTable.of(contracts),
          problem <- EhosContract.ReadModelTable.problems(table, repo),
          do: "read model #{inspect(table.read_model)} of #{inspect(table.contract)}: #{problem}"

    if problems != [] do
      raise ExUnit.AssertionError,
        message:
          "the read models' tables do not fit their contracts:\n\n" <>
            Enum.map_join(problems, "\n", &("  - " <> &1))
    end

    :ok
  end
end
