defmodule PNS.ReportTest do
  @moduledoc """
  Stage 1.7: **the conformance report for a period.**

  The acceptance criterion has two parts and the second is the hard one:

  1. readable without explaining what the columns mean,
  2. **it does not contain a `deadline` marked `unverified`.**

  The second is measurable and is the first block below. The first is soft by
  nature, but it can be pinned from the opposite side: the report contains not a
  single technical event name, because every one is replaced by a label from the
  contract.

  **Moved into the engine 6 August**, reversing the stage 1.7 call that kept
  rendering in the client tree because an accountant was the reader (see
  `PLAN.md`). The scaffolding sentences asserted on below are the engine's own and
  are English; the contract's own labels (`from_label`, `to_label`, a process's
  `label`) print in whatever language the contract declares them, and are passed
  through untranslated. Asserted here against the invented contract, whose labels
  are English — so a sentence that reads as one language throughout is now a
  statement about the renderer rather than a coincidence of two.
  """

  use PNS.DataCase, async: false
  use Oban.Testing, repo: PNS.TestRepo

  alias ProcessShapes.Promised, as: Contract

  defmodule UnverifiedTraceFixture do
    @moduledoc """
    INVENTED. Two assertions on one process, one confirmed and one not — so the
    control (a second, real assertion) proves the filter acts on `unverified`
    rather than on every assertion regardless.
    """

    use PNS.Contract

    event :thing_started, label: "Thing started", payload: %{case_id: :id}, process: :thing
    event :thing_finished, label: "Thing finished", payload: %{case_id: :id}, process: :thing
    event :thing_logged, label: "Thing logged", payload: %{case_id: :id}, process: :thing

    trace :guessed_deadline do
      from :thing_started
      eventually :thing_finished, within: {1, :day}
    end

    trace :confirmed_rule do
      from :thing_started
      eventually :thing_logged, within: {1, :day}
    end

    process :thing, label: "Thing", instance: [:case_id], unverified: [:guessed_deadline]
  end

  # The request edge: one command, two facts. Approving reaches the ordinary
  # ending inside the transaction; refusing leaves the ending in the queue.
  defp request(id, decision) do
    PNS.emit_all(Contract, [
      PNS.event(:request_received, %{request_id: id}),
      PNS.event(decision, %{request_id: id})
    ])
  end

  defp data(opts \\ []), do: PNS.Conformance.report(Contract, opts)
  defp text(opts \\ []), do: opts |> data() |> PNS.Report.render()

  describe "acceptance criterion: no unconfirmed declarations" do
    test "a deadline marked `unverified` does not reach the report's data" do
      # `deadline: {2, :day}` sits in the contract with `unverified: [:deadline]`,
      # standing in for the number that is plausible and that nobody supplied.
      assert :deadline in Contract.process(:handling).unverified

      [process] = data().processes
      keys = Enum.map(process.declarations, & &1.key)

      refute :deadline in keys,
             "an unconfirmed declaration in an evidence report reads as measured — " <>
               "and a false metric is worse than a missing one, because it is the metric the product sells"

      # The cadence is confirmed, so it stays. Without a second declaration on the
      # process this test would pass against a filter that simply drops everything.
      assert :cadence in keys
    end

    test "the deadline does not reach the rendered text either" do
      refute text() =~ "Deadline"
    end

    test "if the deadline were confirmed, it would appear" do
      # Proof that the filter acts on `unverified` rather than simply being unable
      # to print a deadline. Without this the first test would also pass with a
      # broken filter.
      process = Contract.process(:handling)
      confirmed = %{process | unverified: []}

      refute Enum.any?(PNS.Conformance.verified_declarations(process), &(&1.key == :deadline))
      assert Enum.any?(PNS.Conformance.verified_declarations(confirmed), &(&1.key == :deadline))
    end
  end

  describe "unverified reaches a trace by name, fixed 21 August 2026" do
    test "an unverified trace's assertion does not reach the report" do
      [process] = PNS.Conformance.report(UnverifiedTraceFixture).processes
      names = Enum.map(process.assertions, & &1.trace)

      refute :guessed_deadline in names,
             "an assertion nobody confirmed reads as measured next to ones that were"

      # Without a second, confirmed assertion on the same process this would also
      # pass against a filter that drops every assertion regardless of `unverified`.
      assert :confirmed_rule in names
    end

    test "the unverified assertion is still evaluated — the mechanism has something to observe" do
      # `unverified` hides it from the report the client reads; it does not turn
      # off `PNS.Trace` itself, which is what a developer reads with `mix pns.trace`.
      PNS.emit!(UnverifiedTraceFixture, :thing_started, %{case_id: "c-1"})

      assert [verdict] = PNS.Trace.evaluate(UnverifiedTraceFixture, :guessed_deadline)
      assert verdict.verdict == :pending
    end
  end

  describe "acceptance criterion: readable without explanation" do
    setup do
      request("r-1", :request_approved)
      request("r-2", :request_refused)
      Oban.drain_queue(queue: :events)
      :ok
    end

    test "the steps are named with business labels, not with event names" do
      t = text()

      # The assertion is a sentence composed of labels, because `trace` has no
      # `label`. The labels themselves are the contract's own words, printed inside
      # the engine's scaffolding and never rewritten by it.
      assert t =~ "after \"Request received\""
      assert t =~ "\"Request completed\" follows"

      refute t =~ "request_received"
      refute t =~ "request_completed"
    end

    test "satisfaction through the fallback path is named conformance, not an exception" do
      # A refusal is a correct ending. A report that called it a problem would be
      # switched off after the first period.
      assert text() =~ "Met in all 2 runs"
      assert text() =~ "conforms to the rule"
    end

    test "the screen's four questions are in one artifact" do
      t = text()

      assert t =~ "CONTRACT"
      assert t =~ "Version"
      assert t =~ "PROCESS"
      assert t =~ "Rule: after"
      assert t =~ "DRIFT"
    end

    test "the absence of divergence is a sentence, not an empty section" do
      assert text() =~ "None: nothing happened outside the agreement"
    end
  end

  describe "the report is for a period" do
    test "the window cuts off runs from outside the period" do
      request("r-1", :request_approved)
      request("r-2", :request_approved)

      everything = data()
      recent = data(since: ~U[2026-08-05 00:00:00.000000Z])

      [p_everything] = everything.processes
      [p_recent] = recent.processes

      assert p_everything.runs == 2
      assert p_recent.runs == 2

      # A window in the future cannot contain anything — proof that the bound
      # works rather than being ignored.
      empty = data(since: ~U[2027-01-01 00:00:00.000000Z])
      [p_empty] = empty.processes

      assert p_empty.runs == 0
    end

    test "a period with no runs says \"there is nothing to judge\", not \"all is well\"" do
      request("r-1", :request_approved)

      t = text(since: ~U[2027-01-01 00:00:00.000000Z])

      assert t =~ "not a single run in this period"
      refute t =~ "All agreed steps were carried out"
    end

    test "the header names the period the report is about" do
      t = text(since: ~U[2026-07-01 00:00:00.000000Z], until: ~U[2026-07-31 23:59:59.000000Z])
      assert t =~ "2026-07-01 – 2026-07-31"
    end
  end

  describe "a rule that was changed does not retroactively judge older runs" do
    # Two runs, one on each side of the moment the assertion's window last moved.
    # Backdated by payload rather than by instance key, so the test does not depend
    # on how `PNS.Instance` encodes one.
    defp run_at(id, at) do
      request(id, :request_approved)
      Oban.drain_queue(queue: :events)

      Repo.update_all(
        from(e in PNS.Event, where: fragment("?->>'request_id' = ?", e.payload, ^id)),
        set: [occurred_at: at]
      )
    end

    defp rule_changed_on(at) do
      for {digest, seen} <- [{"aaaaaaaaaaaa", ~U[2026-08-01 00:00:00.000000Z]}, {"bbbbbbbbbbbb", at}] do
        Repo.insert!(%PNS.Deployment{
          contract: inspect(Contract),
          contract_version: Contract.version(),
          wiring_version: "wiring-#{digest}",
          events: [],
          edges: [],
          declaration_digests: %{"trace:completed_or_refusal_notified" => digest},
          first_seen_at: seen
        })
      end
    end

    defp assertion do
      [process] = data().processes
      [assertion] = process.assertions
      assertion
    end

    test "runs from before the change are counted apart, not folded in" do
      run_at("r-old", ~U[2026-08-02 09:00:00.000000Z])
      run_at("r-new", ~U[2026-08-09 09:00:00.000000Z])
      rule_changed_on(~U[2026-08-05 09:00:00.000000Z])

      a = assertion()

      assert a.under_earlier_declaration == 1
      assert a.declaration_changed_at == ~U[2026-08-05 09:00:00.000000Z]

      # The counts now describe only what the current rule can speak about, and the
      # four verdicts still account for every one of them. Without that invariant a
      # partition bug would show up as a number nobody can add.
      assert a.instances == 1
      assert a.satisfied + a.violated + a.pending + a.suspended == a.instances
    end

    test "with no change, the numbers and the text are what they were" do
      # The 99% path. An assertion that never moved must render byte for byte as
      # before, or this mechanism has a cost on every report rather than on the
      # reports it is for.
      run_at("r-1", ~U[2026-08-02 09:00:00.000000Z])

      a = assertion()

      assert a.under_earlier_declaration == 0
      assert a.declaration_changed_at == nil
      assert a.instances == 1
      refute text() =~ "judged under a different promise"
    end

    test "the report says how many fell outside and on what date" do
      run_at("r-old", ~U[2026-08-02 09:00:00.000000Z])
      run_at("r-new", ~U[2026-08-09 09:00:00.000000Z])
      rule_changed_on(~U[2026-08-05 09:00:00.000000Z])

      t = text()

      assert t =~ "1 run began before this rule was last changed (2026-08-05)"
      assert t =~ "judged under a different promise"
    end

    test "every run predating the change is not the same as nothing to judge" do
      run_at("r-old", ~U[2026-08-02 09:00:00.000000Z])
      rule_changed_on(~U[2026-08-05 09:00:00.000000Z])

      a = assertion()
      assert a.instances == 0
      assert a.under_earlier_declaration == 1

      t = text()
      assert t =~ "No run in this period was judged under the rule as it now stands."
      refute t =~ "There was no run in this period on which this could be judged."
    end
  end

  describe "drift is attributed to the right contract" do
    test "drift enters the report of the contract whose event caused it" do
      request("r-1", :request_approved)

      Repo.insert!(%PNS.Event{
        type: "event_outside_the_agreement",
        contract: inspect(Contract),
        contract_version: Contract.version(),
        correlation_id: Ecto.UUID.generate(),
        causation_id: List.first(events_of(:request_completed)).id,
        payload: %{},
        occurred_at: DateTime.utc_now()
      })

      assert [divergence] = data().drift
      assert divergence.to == "event_outside_the_agreement"
      assert divergence.from_label == "Request completed"

      # Another contract's report has no business seeing this.
      assert PNS.Conformance.report(UniversalityGate.TreatmentEpisode).drift == []
    end
  end

  describe "a failing step reads as a failure, not as a step nobody took" do
    setup do
      request("r-1", :request_approved)
      Oban.drain_queue(queue: :events)
      :ok
    end

    test "the sentence says it is being attempted and not succeeding" do
      # Rendering is pure, so the failing branch is exercised with the shape it is
      # contracted to accept rather than by breaking a handler. Nothing in this
      # contract fails, and making something fail to reach a renderer branch would
      # be changing the fixture to suit a test.
      report = data()
      [process | rest] = report.processes

      # A different edge from the one the untraversed section legitimately holds,
      # because the assertion below is about an edge appearing in one section and
      # not two — which cannot be checked with an edge that belongs in both.
      failing = %{
        from: :request_received,
        to: :request_logged,
        from_label: "Request received",
        to_label: "Request logged",
        async: false,
        in_flight: 0,
        failing: 2
      }

      text =
        %{report | processes: [%{process | failing: [failing]} | rest]}
        |> PNS.Report.render()

      assert text =~ "Agreed steps that are attempted and fail:"
      assert text =~ "Request received → Request logged"
      assert text =~ "failed in 2 runs"

      # **One edge, one section.** The untraversed section is legitimately present
      # here too — only the approved branch ran, so the refusal path really was
      # never taken — which is exactly why the assertion has to be about this edge
      # rather than about the section existing. An earlier version of this test
      # asserted the section was absent and was simply wrong about the domain.
      occurrences =
        text
        |> String.split("Request received → Request logged")
        |> length()
        |> Kernel.-(1)

      assert occurrences == 1,
             "the same edge in two sections says two different things about one finding"
    end

    test "one failing run is singular, because a report is read aloud" do
      report = data()
      [process | rest] = report.processes

      failing = %{
        from: :request_received,
        to: :request_logged,
        from_label: "Request received",
        to_label: "Request logged",
        async: false,
        in_flight: 0,
        failing: 1
      }

      text =
        %{report | processes: [%{process | failing: [failing]} | rest]}
        |> PNS.Report.render()

      assert text =~ "failed in 1 run"
    end
  end

  describe "a suspended run reads as somebody else's outage" do
    setup do
      request("r-1", :request_approved)
      Oban.drain_queue(queue: :events)
      :ok
    end

    test "it is named as a suspension and kept out of the breaches" do
      # Rendering is pure, so the branch is exercised with the shape it is contracted to
      # accept. This contract declares no external dependency, so it cannot produce a
      # suspension at all — the verdict itself is exercised end to end on the shapes
      # rig, which declares one.
      report = data()
      [process | rest] = report.processes
      [assertion | others] = process.assertions

      suspended = %{assertion | instances: 3, satisfied: 1, violated: 0, suspended: 2}

      text =
        %{report | processes: [%{process | assertions: [suspended | others]} | rest]}
        |> PNS.Report.render()

      assert text =~ "Suspended: 2 runs"
      assert text =~ "external dependency was unavailable"

      # The sentence has to say whose problem it is not. Without that clause a reader sees
      # a number next to an assertion and reads it as a fault.
      assert text =~ "not a breach on the client's side"

      # And it must not be reported as a breach.
      refute text =~ "BREACHED"
    end

    test "no suspensions means no sentence at all" do
      # The control. A report that mentions suspensions when there are none teaches a
      # reader to skip the line.
      refute text() =~ "Suspended"
    end
  end
end
