defmodule EhOsContract.Web.Live.ContractStatusTest do
  @moduledoc """
  Two kinds of proof, deliberately not one: a real, DB-backed run through
  `mount/3` shows the wiring to `EhOsContract.Registry`/`EhOsContract.Conformance` is not
  hollow; the `render/1` cases below it show every section of the four
  questions renders correctly, without needing real time to pass to force a
  `:violated` verdict — `EhOsContract.Trace.evaluate/3`'s `now:` override exists
  exactly so that distinction can be tested, but only inside the engine's own
  suite, not through this screen. `EhOsContract.Registry.load!/0` runs once at boot
  (test_helper.exs), the same way a real host would call it once at startup.
  """

  use EhOsContract.Web.TestHost.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias EhOsContract.Web.Live.ContractStatus
  alias EhOsContract.Web.TestHost.Fixtures.CaseHandling
  alias EhOsContract.Web.TestHost.Access

  @endpoint EhOsContract.Web.TestHost.Endpoint

  @officer EhOsContract.Actor.credential("u-1", [
             "web_test_host.open_case",
             "web_test_host.decide_case"
           ])

  # A case opened and approved, through dispatch, as a host's code would.
  defp approve(id) do
    alias EhOsContract.Web.TestHost.Fixtures.CaseHandling.Commands.{DecideCase, OpenCase}

    {:ok, _} = EhOsContract.dispatch(CaseHandling, %OpenCase{case_id: id}, actor: @officer)

    {:ok, _} =
      EhOsContract.dispatch(CaseHandling, %DecideCase{case_id: id, approve: true},
        actor: @officer
      )
  end

  test "mounting through the real router renders a real conformance report" do
    approve("case-a")

    conn =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_admin"])
      |> get("/dashboard/contract")

    html = html_response(conn, 200)

    assert html =~ "web_test_host.case_handling"
    # What one run is, beside the count (the working plan's point 4): the process's correlate.
    assert html =~ "Runs in this period: 1, one per case_id."
    # A v2 step: the rejection reaching its policy, and the policy's command.
    assert html =~ "Case rejected → Close a case as rejected (via: Close a rejected case)"
    assert html =~ "Met in all 1 runs."
    # A v2 contract's scenarios, in the report's words: this one declares none.
    assert html =~ EhOsContract.Report.Sentence.scenarios_observed(%{declared: 0})

    # Plan LC4b: the case's lifecycle — closed, so the rejection is never taken.
    assert html =~ "Lifecycle: Case"
    assert html =~ "Aggregates with an event in this period: 1."
    assert html =~ "Open → Rejected (on: Case rejected)"
  end

  test "every sentence on the screen is one EhOsContract.Report.Sentence produced" do
    # **The anti-drift test, and the reason this file exists in this shape.** The
    # screen used to carry its own copy of these sentences; by the time anybody
    # compared the two, it was silently missing six answers the text report had
    # grown — including a run suspended by somebody else's outage, which read on
    # screen exactly like an ordinary one.
    #
    # This does not check wording. It checks that the wording is not this screen's
    # to choose: the expected strings are computed from the same data the screen
    # renders, so a local copy that says anything else fails here the day it appears.
    approve("case-a")

    report = EhOsContract.Conformance.report(CaseHandling, [])

    html =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_admin"])
      |> get("/dashboard/contract")
      |> html_response(200)

    # Plan DD, P1a (#183): the steps are the contract's, apart from its processes.
    assert html =~ escape(EhOsContract.Report.Sentence.activity(report.activity))

    for edge <- report.paths.untraversed,
        do: assert(html =~ escape(EhOsContract.Report.Sentence.step(edge)))

    for edge <- report.paths.in_flight,
        do: assert(html =~ escape(EhOsContract.Report.Sentence.step_in_flight(edge)))

    for edge <- report.paths.failing,
        do: assert(html =~ escape(EhOsContract.Report.Sentence.step_failing(edge)))

    for process <- report.processes do
      if line = EhOsContract.Report.Sentence.accountable(process.accountable),
        do: assert(html =~ escape(line))

      for declaration <- process.declarations,
          do: assert(html =~ escape(EhOsContract.Report.Sentence.declaration(declaration)))

      for line <- EhOsContract.Report.Sentence.duration(process.duration),
          do: assert(html =~ escape(line))

      for assertion <- process.promises do
        assert html =~ escape(EhOsContract.Report.Sentence.rule(assertion))
        assert html =~ escape(EhOsContract.Report.Sentence.outcome(assertion))
      end
    end

    # Plan LC4b: the lifecycle's section, in the same sentences.
    assert report.lifecycles != []

    for lifecycle <- report.lifecycles do
      if lifecycle.aggregates == 0,
        do: assert(html =~ escape(EhOsContract.Report.Sentence.no_aggregates()))

      if lifecycle.aggregates > 0 and lifecycle.untraversed == [] and lifecycle.pending == [],
        do: assert(html =~ escape(EhOsContract.Report.Sentence.all_transitions_taken()))

      for transition <- lifecycle.untraversed ++ lifecycle.pending,
          do: assert(html =~ escape(EhOsContract.Report.Sentence.transition(transition)))

      for move <- lifecycle.undeclared,
          do: assert(html =~ escape(EhOsContract.Report.Sentence.transition_undeclared(move)))
    end
  end

  test "and the clauses a real log rarely produces are not this screen's to omit" do
    # The test above walks a real report, and a real report exercises one branch of
    # `outcome/1`. **Checked by neutralising it: putting a local two-branch copy back
    # in the screen left that test green**, because the branch it covers is the one
    # both versions agree on.
    #
    # So this one hands the screen an assertion with every qualifying clause set at
    # once — a breach, a fallback, an outage, and a rule that has since changed — and
    # asserts the screen prints exactly what the shared function says. A local copy
    # cannot pass this without becoming the shared function.
    assertion = %{
      from_label: "Case opened",
      eventually_label: "Case closed",
      or_else_label: "Case closed as rejected",
      within: {1, :hour},
      instances: 9,
      satisfied: 5,
      satisfied_via_eventually: 3,
      satisfied_via_or_else: 2,
      violated: 3,
      pending: 1,
      suspended: 1,
      promise: :closed_in_time,
      under_earlier_declaration: 4,
      declaration_changed_at: ~U[2026-08-05 09:00:00.000000Z]
    }

    assigns = %{
      eh_os_contract_web_access: :all,
      eh_os_contract_web_base_path: "/dashboard",
      reports: [report(processes: [process(promises: [assertion])])]
    }

    html = render_component(&ContractStatus.render/1, assigns)

    assert html =~ escape(EhOsContract.Report.Sentence.verdict(assertion))

    for qualification <- EhOsContract.Report.Sentence.qualifications(assertion),
        do: assert(html =~ escape(qualification))

    # Named individually, so a failure says which clause went missing.
    assert html =~ "reached the fallback ending"
    assert html =~ "an external dependency was unavailable"
    assert html =~ "judged under a different promise"

    # **Only the verdict is coloured.** A clause saying an outage is not a breach on
    # the client's side, printed in the breach colour, says the opposite of what it
    # means — so the class stops at the verdict's own element.
    [_before, after_verdict] = String.split(html, "outcome-breached", parts: 2)
    assert after_verdict =~ "BREACHED in 3 of 9 runs."
    refute after_verdict |> String.split("</p>", parts: 2) |> hd() =~ "not a breach"
  end

  # HEEx escapes interpolated values, so a sentence carrying a quotation mark — every
  # `rule` sentence does — is not in the HTML verbatim.
  defp escape(sentence),
    do: sentence |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  test "no event recorded in the contract: the steps say so instead of listing paths" do
    assigns = %{
      eh_os_contract_web_access: :all,
      eh_os_contract_web_base_path: "/dashboard",
      reports: [
        report(
          activity: %{events: 0, commands: 0},
          # One declared step: a contract with none says so instead.
          paths: %{steps: [%{}], untraversed: [], in_flight: [], failing: []},
          processes: [process(runs: 0)]
        )
      ]
    }

    html = render_component(&ContractStatus.render/1, assigns)

    assert html =~ "this contract recorded no event in this period"
    refute html =~ "Declared paths never exercised"
  end

  # Plan DD, P1a (#183): a contract that recorded no event still shows what fails.
  test "no event recorded, and a step failing: the failure is shown, not \"no event\"" do
    step = %{
      from: %{kind: :event, name: :case_opened, label: "Case opened"},
      via: %{kind: :policy, name: :assign, label: "Assign a case"},
      to: %{kind: :command, name: :assign_case, label: "Assign a case"},
      mode: :async,
      taken: 0,
      in_flight: %{effects: 0, timers: 0, lag: 0},
      failing: %{commands: 0, subscription: %{stopped_at: 7, failure: "RuntimeError"}, effects: 0}
    }

    assigns = %{
      eh_os_contract_web_access: :all,
      eh_os_contract_web_base_path: "/dashboard",
      reports: [
        report(
          activity: %{events: 0, commands: 0},
          paths: %{steps: [step], untraversed: [], in_flight: [], failing: [step]}
        )
      ]
    }

    html = render_component(&ContractStatus.render/1, assigns)

    assert html =~ "Agreed steps that are attempted and fail"
    refute html =~ "recorded no event"
    refute html =~ "Declared paths never exercised"
  end

  test "a breached assertion says BREACHED, not just a number" do
    assertion = %{
      from_label: "Case opened",
      eventually_label: "Case closed",
      or_else_label: "Case closed as rejected",
      within: {1, :hour},
      instances: 2,
      satisfied: 1,
      violated: 1,
      pending: 0,
      suspended: 0,
      satisfied_via_eventually: 1,
      satisfied_via_or_else: 0,
      under_earlier_declaration: 0,
      declaration_changed_at: nil
    }

    assigns = %{
      eh_os_contract_web_access: :read_only,
      eh_os_contract_web_base_path: "/dashboard",
      reports: [report(processes: [process(promises: [assertion])])]
    }

    html = render_component(&ContractStatus.render/1, assigns)

    assert html =~ "BREACHED in 1 of 2 runs."

    assert html =~
             "Rule: after &quot;Case opened&quot; within hour, &quot;Case closed&quot; follows, or else &quot;Case closed as rejected&quot;."

    assert html =~ "Access: read only"
  end

  test "a pending assertion reports how many are still open" do
    assertion = %{
      from_label: "Case opened",
      eventually_label: "Case closed",
      or_else_label: nil,
      within: nil,
      instances: 3,
      satisfied: 1,
      violated: 0,
      pending: 2,
      suspended: 0,
      satisfied_via_eventually: 1,
      satisfied_via_or_else: 0,
      under_earlier_declaration: 0,
      declaration_changed_at: nil
    }

    assigns = %{
      eh_os_contract_web_access: :all,
      eh_os_contract_web_base_path: "/dashboard",
      reports: [report(processes: [process(promises: [assertion])])]
    }

    html = render_component(&ContractStatus.render/1, assigns)

    assert html =~ "Met in 1 of 3, 2 still in progress."
    assert html =~ "Rule: after &quot;Case opened&quot;, &quot;Case closed&quot; follows."
  end

  @drift %{
    from: %{kind: :command, name: :a, label: "A"},
    to: %{kind: :event, name: :b, label: "B"},
    count: 4
  }

  test "drift renders the undeclared edge, and its absence renders as none" do
    with_drift =
      render_component(&ContractStatus.render/1, %{
        eh_os_contract_web_access: :all,
        eh_os_contract_web_base_path: "/dashboard",
        reports: [
          report(drift: [@drift])
        ]
      })

    without_drift =
      render_component(&ContractStatus.render/1, %{
        eh_os_contract_web_access: :all,
        eh_os_contract_web_base_path: "/dashboard",
        reports: [report()]
      })

    assert with_drift =~ EhOsContract.Report.Sentence.drift(@drift)

    assert without_drift =~ "None: nothing happened outside the agreement."
  end

  test "an unconfirmed deployment says nothing has happened under it yet" do
    html =
      render_component(&ContractStatus.render/1, %{
        eh_os_contract_web_access: :all,
        eh_os_contract_web_base_path: "/dashboard",
        reports: [report(deployment: deployment(since: nil))]
      })

    assert html =~ "nothing has happened under this version yet"
  end

  defp report(overrides \\ []) do
    Map.merge(
      %{
        contract: "web_test_host.case_handling",
        module: CaseHandling,
        period: %{since: nil, until: nil},
        deployment: deployment(),
        wiring: %{version: "def456", since: nil},
        activity: %{events: 1, commands: 1},
        paths: %{steps: [], untraversed: [], in_flight: [], failing: []},
        processes: [],
        drift: []
      },
      Map.new(overrides)
    )
  end

  defp deployment(overrides \\ []) do
    Map.merge(
      %{
        contract: CaseHandling,
        deployed: %{contract_version: "abc123", wiring_version: "def456", since: nil},
        in_log: [],
        changed: nil,
        from_earlier_versions: 0
      },
      Map.new(overrides)
    )
  end

  defp process(overrides) do
    Map.merge(
      %{
        process: :handling,
        label: "Case handling",
        accountable: nil,
        runs: 1,
        declarations: [],
        duration: nil,
        promises: []
      },
      Map.new(overrides)
    )
  end
end
