defmodule EhOsContract.TraceEdgesTest do
  @moduledoc """
  **The boundaries of `EhOsContract.Trace`, pinned as they behave today.**

  Both example domains only ever exercised the comfortable middle of an assertion
  window: an event well inside it, or nothing at all. Everything here is an edge —
  the instant the window closes, a hit in the same microsecond as the thing it
  answers, a `from` dated in the future, a window of length zero.

  Read every test below as a description of what happens, never as an argument that
  it should. None of them was written to change a verdict; they exist because the
  verdicts are currently protected by nothing, and a comparison operator flipped from
  `!=` to `==` by somebody tidying up would move thousands of runs from satisfied to
  violated with no test going red.

  ## The one asymmetry, and it is deliberate rather than accidental

  A **hit** exactly at the deadline is inside the window (`in_window?` compares with
  `!= :gt`). The **clock** exactly at the deadline is past it (`pending?` compares
  with `== :lt`). So at the instant `deadline_at`, an event that has arrived counts
  and an event that has not is already too late. That is one consistent reading — the
  window is the closed interval and it has fully elapsed — and it leaves a
  one-instant race in which an event written microseconds late is judged against a
  window that had just closed. Both halves are pinned separately, because the
  temptation when reading one of them alone is to make it match the other.

  ## The fixture

  Invented, and deliberately not in the registry — every trace below is a shape
  nobody would write on purpose, and in `test/support/` they would each become a line
  on every `mix eh_os_contract.check` run in this repository. Evaluation takes its contract as an
  argument, so nothing here needs the registry at all.
  """

  use EhOsContract.DataCase, async: false

  defmodule Edges do
    @moduledoc """
    # INVENTED. NOT A DOMAIN.

    A rig for assertion windows. The names say nothing about anybody's business,
    because nothing here is a claim about one — these are the corners of an interval.
    """

    use EhOsContract.Contract

    event :opened, label: "Opened", payload: %{case_id: :id}, process: :edge
    event :closed, label: "Closed", payload: %{case_id: :id}, process: :edge

    event :inspected,
      label: "Inspected",
      payload: %{case_id: :id},
      depends_on: :inspector,
      process: :edge

    event :chased,
      label: "Chased",
      payload: %{case_id: :id},
      depends_on: :chaser,
      process: :edge

    external :inspector, label: "Inspector"
    external :chaser, label: "Chaser"

    trace :closes_within_a_day do
      from :opened
      eventually :closed, within: {1, :day}
    end

    # A window of length zero. It compiles, which is one of the things under test.
    trace :closes_instantly do
      from :opened
      eventually :closed, within: {0, :day}
    end

    # The consequent reaches outside; the fallback does not exist. For the outage
    # boundaries.
    trace :inspected_within_a_day do
      from :opened
      eventually :inspected, within: {1, :day}
    end

    # The dependency is on the **fallback** only. The wanted route depends on nothing.
    trace :closed_or_chased do
      from :opened
      eventually :closed, within: {1, :day}
      or_else :chased
    end

    # Three self-referential shapes. Two of them cannot fail.
    trace :from_is_also_eventually do
      from :opened
      eventually :opened, within: {1, :day}
    end

    trace :from_is_also_or_else do
      from :opened
      eventually :closed, within: {1, :day}
      or_else :opened
    end

    trace :eventually_is_also_or_else do
      from :opened
      eventually :closed, within: {1, :day}
      or_else :closed
    end

    process :edge, label: "Edge", instance: [:case_id]
  end

  @opened ~U[2026-07-01 09:00:00.000000Z]
  # `within: {1, :day}` is 86 400 seconds, so every window below closes here.
  @deadline ~U[2026-07-02 09:00:00.000000Z]
  @one_microsecond_early ~U[2026-07-02 08:59:59.999999Z]
  @one_microsecond_late ~U[2026-07-02 09:00:00.000001Z]
  @long_after ~U[2026-07-10 09:00:00.000000Z]

  defp insert(type, at, case_id \\ "c-1") do
    Repo.insert!(%EhOsContract.Event{
      type: to_string(type),
      contract: inspect(Edges),
      contract_version: Edges.version(),
      process: "edge",
      instance_id: "edge|#{case_id}",
      correlation_id: Ecto.UUID.generate(),
      payload: %{"case_id" => case_id},
      occurred_at: at
    })
  end

  defp verdict(trace, now \\ @long_after) do
    assert [verdict] = EhOsContract.Trace.evaluate(Edges, trace, now: now)
    verdict
  end

  describe "the instant the window closes" do
    test "a hit exactly at the deadline is satisfied" do
      # The boundary a client argues about. If this flipped, every run that answered
      # on the last second of an agreed window would be reported as a breach — and the
      # first such report in front of the person who agreed the window is the last
      # report anybody reads.
      insert(:opened, @opened)
      insert(:closed, @deadline)

      assert %{verdict: :satisfied, via: :eventually, resolved_at: @deadline} =
               verdict(:closes_within_a_day)
    end

    test "a hit one microsecond later is violated" do
      # The control on the test above. Without it, "satisfied at the deadline" would
      # also pass against an evaluator that had stopped looking at the deadline at all.
      insert(:opened, @opened)
      insert(:closed, @one_microsecond_late)

      assert verdict(:closes_within_a_day).verdict == :violated
    end

    test "`now` exactly at the deadline, with no hit, is violated rather than pending" do
      # The other half of the asymmetry in the moduledoc. At this instant an arrival
      # would have counted and an absence does not get another moment. Pinned
      # separately from the test above precisely because reading either one alone
      # invites making it agree with the other.
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
      # Two facts written inside one transaction share a timestamp far more often than
      # anybody expects, and a strict `>` here would report those runs as breaches of
      # a promise they kept instantaneously.
      insert(:opened, @opened)
      insert(:closed, @opened)

      assert %{verdict: :satisfied, resolved_at: @opened} = verdict(:closes_within_a_day)
    end

    test "one microsecond before `from` is violated, although the fact exists" do
      # Deliberate and worth knowing: the window opens at `from`, so an answer that
      # predates its question does not count. It reads as harsh until the alternative
      # is stated — counting it would let last month's closing satisfy this month's
      # promise, which is the run-mixing that run identity exists to prevent.
      insert(:opened, @opened)
      insert(:closed, ~U[2026-07-01 08:59:59.999999Z])

      assert verdict(:closes_within_a_day).verdict == :violated
    end
  end

  describe "the shape of the data underneath" do
    test "two `from` events at identical timestamps still produce exactly one verdict" do
      # A duplicate emission — a retry, an import run twice — must not double a run's
      # weight in the summary, and must not move the deadline. One verdict per run is
      # the unit every number in the report is counted in.
      insert(:opened, @opened)
      insert(:opened, @opened)

      assert [one] = EhOsContract.Trace.evaluate(Edges, :closes_within_a_day, now: @long_after)
      assert one.from_at == @opened
      assert one.deadline_at == @deadline
    end

    test "a `from` dated in the future leaves the run pending rather than judged" do
      # Clock skew and backdated imports both produce this. The run is not ignored and
      # not violated: its window has not opened yet from the evaluator's point of view,
      # so it waits. Worth pinning because the alternative — treating an impossible
      # date as a violation — would turn one bad clock into a page of findings.
      insert(:opened, ~U[2027-01-01 00:00:00.000000Z])

      assert verdict(:closes_within_a_day).verdict == :pending
    end
  end

  describe "a window of length zero" do
    test "`within: {0, :day}` compiles, deliberately" do
      # Zero reads as "in the same instant" — a real, if rare, promise — and
      # `EhOsContract.Duration.t` is published as `non_neg_integer()` to say so. Negative is
      # the one this gate refuses; see the test below.
      assert Enum.find(Edges.traces(), &(&1.name == :closes_instantly)).within == {0, :day}
    end

    test "the deadline is the opening moment, so only a simultaneous hit satisfies" do
      insert(:opened, @opened)
      insert(:closed, @opened)

      assert %{verdict: :satisfied, deadline_at: @opened} = verdict(:closes_instantly)
    end

    test "anything later is violated, and a run with nothing is violated immediately" do
      # "Immediately" is the part worth seeing: evaluated at the very instant the run
      # opened, it is already a breach. An assertion like this can only ever be kept by
      # events written in the same transaction, which is a claim about the code rather
      # than about the process.
      insert(:opened, @opened, "c-2")
      insert(:closed, @one_microsecond_late, "c-2")

      assert [verdict] =
               EhOsContract.Trace.evaluate(Edges, :closes_instantly,
                 now: @opened,
                 instance: "edge|c-2"
               )

      assert verdict.verdict == :violated
    end

    test "a `within` of a negative count should not compile" do
      # Zero has a reading — "in the same instant" — that negative does not: the
      # deadline would land *before* the moment that opened the window, so every run
      # is violated the instant it starts, and the report says the process is
      # comprehensively broken rather than that the contract is.
      assert_raise CompileError, fn ->
        Code.compile_string("""
        defmodule Reject.NegativeWindow do
          use EhOsContract.Contract

          event :a, label: "A", payload: %{case_id: :id}, process: :p
          event :b, label: "B", payload: %{case_id: :id}, process: :p

          trace :instant do
            from :a
            eventually :b, within: {-1, :day}
          end

          process :p, label: "P", instance: [:case_id]
        end
        """)
      end
    end
  end

  describe "an outage at the edge of the window" do
    setup do
      insert(:opened, @opened)
      :ok
    end

    test "an outage observed exactly when the window opens suspends the run" do
      # `EhOsContract.Dependency` records observations, not intervals — nobody tells it when a
      # service came back — so "the outage ended as the window opened" reaches the
      # evaluator as a single moment equal to `from_at`, and both ends of the interval
      # are inclusive. Generous by one instant, and generous is the direction that
      # removes findings, which is why it is written down rather than assumed.
      EhOsContract.Dependency.unavailable!(Edges, :inspector, "test", @opened)

      assert verdict(:inspected_within_a_day).verdict == :suspended
    end

    test "an outage observed exactly at the deadline also suspends" do
      EhOsContract.Dependency.unavailable!(Edges, :inspector, "test", @deadline)

      assert verdict(:inspected_within_a_day).verdict == :suspended
    end

    test "one microsecond outside either end does not" do
      # The control, and the only thing that makes the two tests above mean anything:
      # an evaluator that suspended on any outage ever recorded would pass both.
      EhOsContract.Dependency.unavailable!(
        Edges,
        :inspector,
        "test",
        ~U[2026-07-01 08:59:59.999999Z]
      )

      EhOsContract.Dependency.unavailable!(Edges, :inspector, "test", @one_microsecond_late)

      assert verdict(:inspected_within_a_day).verdict == :violated
    end
  end

  describe "a dependency on the fallback only" do
    test "an outage of it suspends the run, although the wanted route depended on nothing" do
      # Decided rather than assumed, 21 August 2026: `awaited_outages/2` takes the
      # dependencies of both awaited events on purpose. The narrower reading — suspend
      # only when every still-possible route was blocked, so a wanted route with no
      # dependency at all could never excuse the run — was considered and rejected. The
      # contract says "X or Y", and here Y was impossible; that stands as a reason to
      # withhold judgement on the run even though X depended on nothing, because the
      # promise was the disjunction, not X alone. A `:known_defect` test asserting the
      # narrower reading stood here until this date; removed rather than left red for a
      # future nobody now intends.
      insert(:opened, @opened)

      EhOsContract.Dependency.unavailable!(
        Edges,
        :chaser,
        "test",
        ~U[2026-07-01 15:00:00.000000Z]
      )

      assert verdict(:closed_or_chased).verdict == :suspended
    end
  end

  describe "an assertion that names one event twice" do
    test "`from` is also `eventually` — satisfied the instant it opens, always" do
      # A contract that cannot fail, and it compiles. The verdict is satisfied at the
      # same moment the window opens, so the assertion's line in the report is a
      # constant with a percentage sign after it.
      insert(:opened, @opened)

      assert %{verdict: :satisfied, via: :eventually, resolved_at: @opened} =
               verdict(:from_is_also_eventually)
    end

    test "`from` is also `or_else` — the same, one route further down" do
      # Worse to read than the case above, because the report says "satisfied through
      # or_else", which is real business information everywhere else: the month was
      # blocked deliberately. Here it means nothing happened at all.
      insert(:opened, @opened)

      assert %{verdict: :satisfied, via: :or_else} = verdict(:from_is_also_or_else)
    end

    test "`eventually` is also `or_else` — not degenerate, but `via` can never say `or_else`" do
      # This one can still be violated, so it is not a contract that cannot fail. What
      # it loses is the distinction the verdict exists to carry: `summary/1` breaks
      # satisfaction down by route because "opened" and "deliberately blocked" are
      # different answers, and here one of the two counters is permanently zero.
      insert(:opened, @opened)
      insert(:closed, ~U[2026-07-01 12:00:00.000000Z])

      assert %{verdict: :satisfied, via: :eventually} = verdict(:eventually_is_also_or_else)

      assert EhOsContract.Trace.evaluate(Edges, :eventually_is_also_or_else, now: @long_after)
             |> EhOsContract.Trace.summary()
             |> Map.fetch!(:satisfied_via_or_else) == 0
    end

    test "and it can still be violated, which the other two cannot" do
      # The control that separates "both routes are the same event" from "the assertion
      # is unfalsifiable". Only the first two of the three are the latter.
      insert(:opened, @opened, "c-3")

      assert [verdict] =
               EhOsContract.Trace.evaluate(Edges, :eventually_is_also_or_else,
                 now: @long_after,
                 instance: "edge|c-3"
               )

      assert verdict.verdict == :violated
    end
  end
end
