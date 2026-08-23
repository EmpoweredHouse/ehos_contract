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
  alias PNS.Web.TestHost.TestToken

  @endpoint PNS.Web.TestHost.Endpoint

  test "mounting through the real router renders a real conformance report" do
    PNS.emit_all(CaseHandling, [PNS.event(:case_opened, %{case_id: "case-a"})])
    PNS.emit_all(CaseHandling, [PNS.event(:case_approved, %{case_id: "case-a"})])

    conn =
      build_conn()
      |> TestToken.put_actor("admin", ["pns_admin"])
      |> get("/pns")

    html = html_response(conn, 200)

    assert html =~ inspect(CaseHandling)
    assert html =~ "Runs in this period: 1."
    assert html =~ "Case rejected → Case closed as rejected"
    assert html =~ "Met in all 1 runs."
  end

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
      satisfied_via_or_else: 0
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
      satisfied_via_or_else: 0
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
        runs: 1,
        declarations: [],
        untraversed: [],
        in_flight: [],
        failing: [],
        assertions: []
      },
      Map.new(overrides)
    )
  end
end
