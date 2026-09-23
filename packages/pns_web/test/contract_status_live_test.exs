defmodule PNS.Web.Live.ContractStatusTest do
  @moduledoc """
  Two kinds of proof, deliberately not one: a real, DB-backed run through
  `mount/3` shows the wiring to `PNS.Registry`/`PNS.Conformance` is not
  hollow; the `render/1` cases below it show every section of the four
  questions renders correctly, without needing real time to pass to force a
  `:violated` verdict — `PNS.Trace.evaluate/3`'s `now:` override exists
  exactly so that distinction can be tested, but only inside the engine's own
  suite, not through this screen. `PNS.Registry.load!/0` runs once at boot
  (test_helper.exs), the same way a real host would call it once at startup.
  """

  use PNS.Web.TestHost.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PNS.Web.Live.ContractStatus
  alias PNS.Web.TestHost.Fixtures.CaseHandling
  alias PNS.Web.TestHost.Access

  @endpoint PNS.Web.TestHost.Endpoint

  test "mounting through the real router renders a real conformance report" do
    PNS.emit_all(CaseHandling, [PNS.event(:case_opened, %{case_id: "case-a"})])
    PNS.emit_all(CaseHandling, [PNS.event(:case_approved, %{case_id: "case-a"})])

    conn =
      build_conn()
      |> Access.put_actor("admin", ["pns_admin"])
      |> get("/pns/contract")

    html = html_response(conn, 200)

    assert html =~ inspect(CaseHandling)
    assert html =~ "Runs in this period: 1."
    assert html =~ "Case rejected → Case closed as rejected"
    assert html =~ "Met in all 1 runs."
  end

  test "every sentence on the screen is one PNS.Report.Sentence produced" do
    # **The anti-drift test, and the reason this file exists in this shape.** The
    # screen used to carry its own copy of these sentences; by the time anybody
    # compared the two, it was silently missing six answers the text report had
    # grown — including a run suspended by somebody else's outage, which read on
    # screen exactly like an ordinary one.
    #
    # This does not check wording. It checks that the wording is not this screen's
    # to choose: the expected strings are computed from the same data the screen
    # renders, so a local copy that says anything else fails here the day it appears.
    PNS.emit_all(CaseHandling, [PNS.event(:case_opened, %{case_id: "case-a"})])
    PNS.emit_all(CaseHandling, [PNS.event(:case_approved, %{case_id: "case-a"})])

    report = PNS.Conformance.report(CaseHandling, [])

    html =
      build_conn()
      |> Access.put_actor("admin", ["pns_admin"])
      |> get("/pns/contract")
      |> html_response(200)

    for process <- report.processes do
      if line = PNS.Report.Sentence.accountable(process.accountable),
        do: assert(html =~ escape(line))

      for declaration <- process.declarations,
          do: assert(html =~ escape(PNS.Report.Sentence.declaration(declaration)))

      for line <- PNS.Report.Sentence.duration(process.duration),
          do: assert(html =~ escape(line))

      for edge <- process.untraversed,
          do: assert(html =~ escape(PNS.Report.Sentence.step(edge)))

      for edge <- process.in_flight,
          do: assert(html =~ escape(PNS.Report.Sentence.step_in_flight(edge)))

      for edge <- process.failing,
          do: assert(html =~ escape(PNS.Report.Sentence.step_failing(edge)))

      for assertion <- process.assertions do
        assert html =~ escape(PNS.Report.Sentence.rule(assertion))
        assert html =~ escape(PNS.Report.Sentence.outcome(assertion))
      end
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
      trace: :closed_in_time,
      under_earlier_declaration: 4,
      declaration_changed_at: ~U[2026-08-05 09:00:00.000000Z]
    }

    assigns = %{
      pns_web_access: :all,
      pns_web_base_path: "/pns",
      reports: [report(processes: [process(assertions: [assertion])])]
    }

    html = render_component(&ContractStatus.render/1, assigns)

    assert html =~ escape(PNS.Report.Sentence.verdict(assertion))

    for qualification <- PNS.Report.Sentence.qualifications(assertion),
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

  test "no runs at all: the process says so instead of listing paths" do
    assigns = %{
      pns_web_access: :all,
      pns_web_base_path: "/pns",
      reports: [report(processes: [process(runs: 0)])]
    }

    html = render_component(&ContractStatus.render/1, assigns)

    assert html =~ "there was not a single run in this period"
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
      pns_web_access: :read_only,
      pns_web_base_path: "/pns",
      reports: [report(processes: [process(assertions: [assertion])])]
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
      pns_web_access: :all,
      pns_web_base_path: "/pns",
      reports: [report(processes: [process(assertions: [assertion])])]
    }

    html = render_component(&ContractStatus.render/1, assigns)

    assert html =~ "Met in 1 of 3, 2 still in progress."
    assert html =~ "Rule: after &quot;Case opened&quot;, &quot;Case closed&quot; follows."
  end

  test "drift renders the undeclared edge, and its absence renders as none" do
    with_drift =
      render_component(&ContractStatus.render/1, %{
        pns_web_access: :all,
        pns_web_base_path: "/pns",
        reports: [
          report(drift: [%{from: "a", to: "b", from_label: "A", to_label: "B", count: 4}])
        ]
      })

    without_drift =
      render_component(&ContractStatus.render/1, %{
        pns_web_access: :all,
        pns_web_base_path: "/pns",
        reports: [report()]
      })

    assert with_drift =~ "A → B (4x)"
    assert without_drift =~ "None: nothing happened outside the agreement."
  end

  test "an unconfirmed deployment says nothing has happened under it yet" do
    html =
      render_component(&ContractStatus.render/1, %{
        pns_web_access: :all,
        pns_web_base_path: "/pns",
        reports: [report(deployment: deployment(since: nil))]
      })

    assert html =~ "nothing has happened under this version yet"
  end

  defp report(overrides \\ []) do
    Map.merge(
      %{
        contract: CaseHandling,
        period: %{since: nil, until: nil},
        deployment: deployment(),
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
        untraversed: [],
        in_flight: [],
        failing: [],
        assertions: []
      },
      Map.new(overrides)
    )
  end
end
