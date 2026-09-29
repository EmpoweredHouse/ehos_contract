defmodule EhOsContract.PromiseEdgesTest do
  @moduledoc """
  **The boundaries of a v2 `promise`, pinned as they behave today** — the edges
  `trace_edges_test.exs` pinned for v1's `trace`, on a v2 contract (plan E11a).

  A promise and a trace share their arithmetic (`EhOsContract.Trace`: `verdict/6`,
  `in_window?`, `pending?`, `suspended?`); only the rows differ, which a v2 promise
  reads from the runs `eh_os_contract_event_runs` records. So the edges are the same
  edges, and they are pinned again here because the v1 fixture that pinned them goes
  with v1. Every test below is an edge — the instant the window closes, a hit in the
  same microsecond as the thing it answers, a `from` dated in the future, a window of
  length zero, an outage at either end.

  Read every test as a description of what happens, never as an argument that it
  should. They exist because the verdicts are otherwise protected by nothing, and a
  comparison flipped by somebody tidying up would move thousands of runs from
  satisfied to violated with no test going red.

  ## The one asymmetry, and it is deliberate

  A **hit** exactly at the deadline is inside the window (`in_window?` compares with
  `!= :gt`). The **clock** exactly at the deadline is past it (`pending?` compares
  with `== :lt`). At the instant `deadline_at`, an event that has arrived counts and
  one that has not is already too late: the window is the closed interval and it has
  fully elapsed. Both halves are pinned separately, because reading either one alone
  invites making it agree with the other.

  ## Suspension

  Until this file, no test reached a v2 promise's suspension, and nothing could: the
  observation that a dependency was unavailable was accepted only for a v1 contract.
  `EhOsContract.Dependency.unavailable!/4` now takes a v2 contract whose event
  `depends_on` the external, which is the only way the observation reaches a promise.

  ## The fixture

  Invented, and deliberately out of the registry: every promise below is a shape
  nobody would write on purpose, and in `test/support/` each would become a line on
  every `mix eh_os_contract.check` run in this repository. Evaluation takes its
  contract as an argument, so nothing here needs the registry.
  """

  use EhOsContract.DataCase, async: false

  alias EhOsContract.{Dependency, Trace}

  defmodule Domain do
    @moduledoc """
    # INVENTED. NOT A DOMAIN.

    The two externals the edges need: one the wanted route depends on, one only the
    fallback does.
    """

    use EhOsContract.Domain, name: :promise_edges, language: :en

    context :edge, "Edge", subdomain: :core

    actor :observer, :system, "Observer"

    external :inspector, "Inspector", direction: :outbound
    external :chaser, "Chaser", direction: :outbound
    # Called by an effect and depended on by no event: observed, never awaited.
    external :notifier, "Notifier", direction: :outbound
    # Declared by the domain and used by nothing of the contract.
    external :archive, "Archive", direction: :outbound

    subdomain :core, "Core", type: :core
  end

  defmodule Edges do
    @moduledoc """
    # INVENTED. NOT A DOMAIN.

    A rig for promise windows. The names say nothing about anybody's business,
    because nothing here is a claim about one — these are the corners of an interval.
    """

    use EhOsContract.Contract, domain: EhOsContract.PromiseEdgesTest.Domain, context: :edge

    aggregate :case, "Case" do
      identity :case_id

      event :opened, "Opened", recorded_by: :observer
      event :closed, "Closed", recorded_by: :observer
      event :inspected, "Inspected", recorded_by: :observer, depends_on: :inspector
      event :chased, "Chased", recorded_by: :observer, depends_on: :chaser
    end

    effect :notify_closing, "Notify a closing",
      handles: :closed,
      calls: :notifier,
      idempotency: :event_id

    process :edge, "Edge" do
      correlate :case_id

      promise :closes_within_a_day do
        from :opened
        eventually :closed
        within {1, :day}
      end

      # A window of length zero. It compiles, which is one of the things under test.
      promise :closes_instantly do
        from :opened
        eventually :closed
        within {0, :day}
      end

      # The consequent reaches outside; there is no fallback. For the outage edges.
      promise :inspected_within_a_day do
        from :opened
        eventually :inspected
        within {1, :day}
      end

      # The dependency is on the **fallback** only. The wanted route depends on nothing.
      promise :closed_or_chased do
        from :opened
        eventually :closed
        within {1, :day}
        or_else :chased
      end

      # Three self-referential shapes. Two of them cannot fail.
      promise :from_is_also_eventually do
        from :opened
        eventually :opened
        within {1, :day}
      end

      promise :from_is_also_or_else do
        from :opened
        eventually :closed
        within {1, :day}
        or_else :opened
      end

      promise :eventually_is_also_or_else do
        from :opened
        eventually :closed
        within {1, :day}
        or_else :closed
      end

      # Not confirmed by anybody, so the report leaves it out; it is still evaluated.
      promise :guessed do
        unverified true
        from :opened
        eventually :closed
        within {1, :day}
      end
    end
  end

  @opened ~U[2026-07-01 09:00:00.000000Z]
  # `within {1, :day}` is 86 400 seconds, so every window below closes here.
  @deadline ~U[2026-07-02 09:00:00.000000Z]
  @one_microsecond_early ~U[2026-07-02 08:59:59.999999Z]
  @one_microsecond_late ~U[2026-07-02 09:00:00.000001Z]
  @long_after ~U[2026-07-10 09:00:00.000000Z]

  # Through the store, as `ProcessShapes.Seed.fact/3` writes a fact: the append is what
  # puts the event in its run, and a v2 promise reads nothing else.
  defp insert(name, at, case_id \\ "c-1") do
    repo = Application.fetch_env!(:eh_os_contract, :repo)

    entry = %{
      type: "edge.#{name}",
      contract: inspect(Edges),
      contract_version: EhOsContract.Model.fetch(Edges).version,
      process: "edge",
      instance_id: "edge|#{case_id}",
      correlation_id: Ecto.UUID.generate(),
      actor: EhOsContract.Event.system_actor(),
      payload: %{"case_id" => case_id},
      occurred_at: at
    }

    {:ok, {:ok, [event]}} =
      repo.transaction(fn -> EhOsContract.Store.append(repo, [entry], :none) end)

    event
  end

  defp verdict(promise, now \\ @long_after) do
    assert [verdict] = Trace.evaluate(Edges, promise, now: now)
    verdict
  end

  describe "the instant the window closes" do
    test "a hit exactly at the deadline is satisfied" do
      # The boundary a client argues about. If this flipped, every run that answered on
      # the last second of an agreed window would be reported as a breach.
      insert(:opened, @opened)
      insert(:closed, @deadline)

      assert %{verdict: :satisfied, via: :eventually, resolved_at: @deadline} =
               verdict(:closes_within_a_day)
    end

    test "a hit one microsecond later is violated" do
      # The control on the test above: without it, "satisfied at the deadline" would
      # also pass against an evaluator that had stopped looking at the deadline at all.
      insert(:opened, @opened)
      insert(:closed, @one_microsecond_late)

      assert verdict(:closes_within_a_day).verdict == :violated
    end

    test "`now` exactly at the deadline, with no hit, is violated rather than pending" do
      # The other half of the asymmetry in the moduledoc.
      insert(:opened, @opened)

      assert verdict(:closes_within_a_day, @deadline).verdict == :violated
    end

    test "`now` one microsecond earlier, with no hit, is still pending" do
      # The control: the verdict above has to come from the deadline having passed,
      # not from the evaluator having given up on an empty run.
      insert(:opened, @opened)

      assert verdict(:closes_within_a_day, @one_microsecond_early).verdict == :pending
    end
  end

  describe "a hit at or before the moment that opened the window" do
    test "the same microsecond as `from` satisfies" do
      # Two facts written in one transaction share a timestamp far more often than
      # anybody expects; a strict `>` would report those runs as breaches of a promise
      # they kept instantaneously.
      insert(:opened, @opened)
      insert(:closed, @opened)

      assert %{verdict: :satisfied, resolved_at: @opened} = verdict(:closes_within_a_day)
    end

    test "one microsecond before `from` is violated, although the fact exists" do
      # The window opens at `from`, so an answer that predates its question does not
      # count; counting it would let last month's closing satisfy this month's promise.
      insert(:opened, @opened)
      insert(:closed, ~U[2026-07-01 08:59:59.999999Z])

      assert verdict(:closes_within_a_day).verdict == :violated
    end
  end

  describe "the shape of the data underneath" do
    test "two `from` events at identical timestamps still produce exactly one verdict" do
      # A duplicate — a retry, an import run twice — must not double a run's weight in
      # the summary, and must not move the deadline.
      insert(:opened, @opened)
      insert(:opened, @opened)

      assert [one] = Trace.evaluate(Edges, :closes_within_a_day, now: @long_after)
      assert one.from_at == @opened
      assert one.deadline_at == @deadline
    end

    test "a `from` dated in the future leaves the run pending rather than judged" do
      # Clock skew and backdated imports both produce this; treating an impossible date
      # as a violation would turn one bad clock into a page of findings.
      insert(:opened, ~U[2027-01-01 00:00:00.000000Z])

      assert verdict(:closes_within_a_day).verdict == :pending
    end
  end

  describe "a window of length zero" do
    test "`within {0, :day}` compiles, deliberately" do
      # Zero reads as "in the same instant" — a real, if rare, promise. A negative count
      # is what R6 refuses (`contract_process_test.exs`).
      promise =
        Enum.find(
          EhOsContract.Model.fetch(Edges).process.promises,
          &(&1.name == :closes_instantly)
        )

      assert {promise.within.amount, promise.within.unit} == {0, :day}
    end

    test "the deadline is the opening moment, so only a simultaneous hit satisfies" do
      insert(:opened, @opened)
      insert(:closed, @opened)

      assert %{verdict: :satisfied, deadline_at: @opened} = verdict(:closes_instantly)
    end

    test "anything later is violated, and a run with nothing is violated immediately" do
      # Evaluated at the very instant the run opened, it is already a breach: such a
      # promise can only be kept by events written in the same transaction.
      insert(:opened, @opened, "c-2")
      insert(:closed, @one_microsecond_late, "c-2")

      assert [verdict] =
               Trace.evaluate(Edges, :closes_instantly, now: @opened, instance: "edge|c-2")

      assert verdict.verdict == :violated
    end
  end

  describe "an outage at the edge of the window" do
    setup do
      insert(:opened, @opened)
      :ok
    end

    test "an outage observed exactly when the window opens suspends the run" do
      # `EhOsContract.Dependency` records moments, not intervals, and both ends of the
      # window are inclusive — generous by one instant, in the direction that removes
      # findings, which is why it is written down rather than assumed.
      Dependency.unavailable!(Edges, :inspector, "test", @opened)

      assert verdict(:inspected_within_a_day).verdict == :suspended
    end

    test "an outage observed exactly at the deadline also suspends" do
      Dependency.unavailable!(Edges, :inspector, "test", @deadline)

      assert verdict(:inspected_within_a_day).verdict == :suspended
    end

    test "one microsecond outside either end does not" do
      # The control that makes the two tests above mean anything: an evaluator that
      # suspended on any outage ever recorded would pass both.
      Dependency.unavailable!(Edges, :inspector, "test", ~U[2026-07-01 08:59:59.999999Z])
      Dependency.unavailable!(Edges, :inspector, "test", @one_microsecond_late)

      assert verdict(:inspected_within_a_day).verdict == :violated
    end

    test "an outage of an external no awaited event depends on does not suspend" do
      # `chased` depends on the chaser, but this promise awaits only `inspected`.
      Dependency.unavailable!(Edges, :chaser, "test", ~U[2026-07-01 15:00:00.000000Z])

      assert verdict(:inspected_within_a_day).verdict == :violated
    end
  end

  describe "a suspension replaces a breach, and nothing else" do
    setup do
      insert(:opened, @opened)
      Dependency.unavailable!(Edges, :inspector, "test", ~U[2026-07-01 12:00:00.000000Z])
      :ok
    end

    test "a promise kept in spite of the outage is satisfied" do
      # The dependency came back and the run answered in time: that is a kept promise,
      # and calling it suspended would take a success out of the count.
      insert(:inspected, ~U[2026-07-01 15:00:00.000000Z])

      assert %{verdict: :satisfied, via: :eventually} = verdict(:inspected_within_a_day)
    end

    test "a run whose window is still open is pending, outage or not" do
      # Nothing is decided yet, so there is nothing for the outage to excuse.
      assert verdict(:inspected_within_a_day, ~U[2026-07-01 18:00:00.000000Z]).verdict ==
               :pending
    end
  end

  describe "a dependency on the fallback only" do
    test "an outage of it suspends the run, although the wanted route depended on nothing" do
      # Decided, 21 August 2026, for v1's `awaited_outages/2`, and kept by v2's
      # `promised_outages/2`: the dependencies of both awaited events count, because
      # the promise is the disjunction, not its first half.
      insert(:opened, @opened)
      Dependency.unavailable!(Edges, :chaser, "test", ~U[2026-07-01 15:00:00.000000Z])

      assert verdict(:closed_or_chased).verdict == :suspended
    end
  end

  describe "recording an observation" do
    test "an external the contract does not use is refused, even one its domain declares" do
      # Written, it would be about nothing the contract does: a row in a place nothing
      # reads. The domain declaring it is not enough, and neither is a name nobody
      # declares.
      for external <- [:archive, :nobody] do
        assert_raise ArgumentError,
                     ~r/EhOsContract.PromiseEdgesTest.Edges uses no external :#{external}/,
                     fn -> Dependency.unavailable!(Edges, external, "test", @opened) end
      end
    end

    test "an external only an effect calls is recorded, and suspends nothing" do
      # Decided by the user in the review of E11a: the adapter an effect wraps in
      # `observe/3` gets its `{:error, :unavailable}` back instead of a crash in the
      # middle of the outage. No event depends on the notifier, so no promise waits
      # on it, and the run is judged as if nothing had been observed.
      insert(:opened, @opened)

      assert Dependency.observe(Edges, :notifier, fn -> {:error, :unavailable} end) ==
               {:error, :unavailable}

      assert %{"notifier" => [_one]} = Dependency.observations_by_external(Edges)
      assert verdict(:closes_within_a_day).verdict == :violated
    end

    test "a domain is refused by name, not with a match error" do
      assert_raise ArgumentError, ~r/is a domain, not a contract/, fn ->
        Dependency.unavailable!(Domain, :inspector, "test", @opened)
      end
    end

    test "an adapter's `{:error, :unavailable}` is recorded, anything else is not" do
      assert Dependency.observe(Edges, :inspector, fn -> {:error, :unavailable} end) ==
               {:error, :unavailable}

      assert Dependency.observe(Edges, :inspector, fn -> {:error, :timeout} end) ==
               {:error, :timeout}

      assert %{"inspector" => [_one]} = Dependency.observations_by_external(Edges)
    end

    test "an adapter's `{:ok, _}` passes through, and records nothing" do
      # The common case, and the one that must cost nothing: a row per successful call
      # would make the table of outages the busiest table of the application.
      assert Dependency.observe(Edges, :inspector, fn -> {:ok, :inspected} end) ==
               {:ok, :inspected}

      assert Dependency.observations_by_external(Edges) == %{}
    end
  end

  describe "a promise that names one event twice" do
    test "`from` is also `eventually` — satisfied the instant it opens, always" do
      # A promise that cannot fail, and it compiles: its line in the report is a
      # constant with a percentage sign after it.
      insert(:opened, @opened)

      assert %{verdict: :satisfied, via: :eventually, resolved_at: @opened} =
               verdict(:from_is_also_eventually)
    end

    test "`from` is also `or_else` — the same, one route further down" do
      # Worse to read, because "satisfied through or_else" is real business information
      # everywhere else. Here it means nothing happened at all.
      insert(:opened, @opened)

      assert %{verdict: :satisfied, via: :or_else} = verdict(:from_is_also_or_else)
    end

    test "`eventually` is also `or_else` — not degenerate, but `via` can never say `or_else`" do
      insert(:opened, @opened)
      insert(:closed, ~U[2026-07-01 12:00:00.000000Z])

      assert %{verdict: :satisfied, via: :eventually} = verdict(:eventually_is_also_or_else)

      assert Trace.evaluate(Edges, :eventually_is_also_or_else, now: @long_after)
             |> Trace.summary()
             |> Map.fetch!(:satisfied_via_or_else) == 0
    end

    test "and it can still be violated, which the other two cannot" do
      insert(:opened, @opened, "c-3")

      assert [verdict] =
               Trace.evaluate(Edges, :eventually_is_also_or_else,
                 now: @long_after,
                 instance: "edge|c-3"
               )

      assert verdict.verdict == :violated
    end
  end

  describe "an unverified promise" do
    test "is left out of the report, beside one that is confirmed" do
      # Nobody confirmed it, so a client never reads a percentage of it.
      [process] = EhOsContract.Conformance.report(Edges).processes
      names = Enum.map(process.promises, & &1.promise)

      assert :closes_within_a_day in names
      refute :guessed in names
    end

    test "is still evaluated, so confirming it later has its history" do
      insert(:opened, @opened)

      assert [%{verdict: :pending}] = Trace.evaluate(Edges, :guessed, now: @opened)
    end
  end
end
