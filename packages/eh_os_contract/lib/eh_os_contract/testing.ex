defmodule EhOsContract.Testing do
  @moduledoc """
  Helpers for a host's tests of what runs after the dispatch transaction (v2 §12,
  §17).

  A test runs inside the Ecto SQL sandbox, where a runner in another process would
  not see its rows and a notification would never fire. So a test configures

      config :eh_os_contract, subscriptions: :manual

  and nothing runs by itself: no runner starts, and the boot registers nothing. The
  test pushes the work through with `drain/1`, in its own process and its own
  sandbox transaction.

  **The first `drain/1` is the deploy.** It registers the subscriptions, and what is
  in the log by then is history, which a new policy or process manager does not
  react to (`EhOsContract.Subscription`). A test of a policy's reaction drains once
  before it dispatches what the policy reacts to.
  """

  alias EhOsContract.{Implementations, Subscription, SubscriptionRecord}

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

  **A timer fires only when it is due by `EhOsContract.Clock.now/0`**; an earlier
  one snoozes and stays queued. To see a process manager's 24 hours pass, drain at
  the time the test chooses:

      EhOsContract.Clock.at(DateTime.add(opened, 25 * 3600), fn ->
        EhOsContract.Testing.drain()
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
    repo = Application.fetch_env!(:eh_os_contract, :repo)
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
          "EhOsContract.Testing.drain/1 still found work after #{@rounds} rounds: a consumer " <>
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
end
