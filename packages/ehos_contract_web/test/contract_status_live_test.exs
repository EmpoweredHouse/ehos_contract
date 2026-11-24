defmodule EhosContract.Web.Live.ContractStatusTest do
  @moduledoc """
  Two kinds of proof, deliberately not one: a real, DB-backed run through
  `mount/3` shows the wiring to `EhosContract.Registry`/`EhosContract.Conformance` is not
  hollow; the `render/1` cases below it show the sections a real log rarely
  produces render correctly. A contract declares no process (plan DD, P2h, #221): its
  runs and promises are a process module's, which has a section of its own (plan DD,
  P2e (#220)). `EhosContract.Registry.load!/0`
  runs once at boot (test_helper.exs), the same way a real host would call it once
  at startup.
  """

  use EhosContract.Web.TestHost.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias EhosContract.Report.Sentence
  alias EhosContract.Web.Live.ContractStatus
  alias EhosContract.Web.TestHost.Fixtures.{CaseHandling, CaseRun}
  alias EhosContract.Web.TestHost.Access

  @endpoint EhosContract.Web.TestHost.Endpoint

  @officer EhosContract.Actor.credential("u-1", [
             "web_test_host.open_case",
             "web_test_host.decide_case"
           ])

  # A case opened and approved, through dispatch, as a host's code would.
  defp approve(id) do
    alias EhosContract.Web.TestHost.Fixtures.CaseHandling.Commands.{DecideCase, OpenCase}

    {:ok, _} = EhosContract.dispatch(CaseHandling, %OpenCase{case_id: id}, actor: @officer)

    {:ok, _} =
      EhosContract.dispatch(CaseHandling, %DecideCase{case_id: id, approve: true},
        actor: @officer
      )
  end

  test "mounting through the real router renders a real conformance report" do
    approve("case-a")

    conn =
      build_conn()
      |> Access.put_actor("admin", ["ehos_contract_admin"])
      |> get("/dashboard/contract")

    html = html_response(conn, 200)

    assert html =~ "web_test_host.case_handling"
    # A contract declares no process (plan DD, P2h, #221): runs are a process module's,
    # whose section the static render leaves for the connection.
    refute html =~ "Runs in this period"
    # A v2 step: the rejection reaching its policy, and the policy's command.
    assert html =~ "Case rejected → Close a case as rejected (via: Close a rejected case)"
    # A v2 contract's scenarios, in the report's words: this one declares none.
    assert html =~ EhosContract.Report.Sentence.scenarios_observed(%{declared: 0})

    # Plan LC4b: the case's lifecycle — closed, so the rejection is never taken.
    assert html =~ "Lifecycle: Case"
    assert html =~ "Aggregates with an event in this period: 1."
    assert html =~ "Open → Rejected (on: Case rejected)"
  end

  test "every sentence on the screen is one EhosContract.Report.Sentence produced" do
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

    report = EhosContract.Conformance.report(CaseHandling, [])

    html =
      build_conn()
      |> Access.put_actor("admin", ["ehos_contract_admin"])
      |> get("/dashboard/contract")
      |> html_response(200)

    # Plan DD, P1a (#183): the steps are the contract's, apart from its processes.
    assert html =~ escape(EhosContract.Report.Sentence.activity(report.activity))

    for edge <- report.paths.untraversed,
        do: assert(html =~ escape(EhosContract.Report.Sentence.step(edge)))

    for edge <- report.paths.in_flight,
        do: assert(html =~ escape(EhosContract.Report.Sentence.step_in_flight(edge)))

    for edge <- report.paths.failing,
        do: assert(html =~ escape(EhosContract.Report.Sentence.step_failing(edge)))

    # Plan LC4b: the lifecycle's section, in the same sentences.
    assert report.lifecycles != []

    for lifecycle <- report.lifecycles do
      if lifecycle.aggregates == 0,
        do: assert(html =~ escape(EhosContract.Report.Sentence.no_aggregates()))

      if lifecycle.aggregates > 0 and lifecycle.untraversed == [] and lifecycle.pending == [],
        do: assert(html =~ escape(EhosContract.Report.Sentence.all_transitions_taken()))

      for transition <- lifecycle.untraversed ++ lifecycle.pending,
          do: assert(html =~ escape(EhosContract.Report.Sentence.transition(transition)))

      for move <- lifecycle.undeclared,
          do: assert(html =~ escape(EhosContract.Report.Sentence.transition_undeclared(move)))
    end
  end

  # Plan DD, P2e (#220): a process module's report, beside the contracts.
  test "a process module has its section: its version, runs and promises' verdicts" do
    approve("case-a")

    {:ok, _view, html} =
      build_conn()
      |> Access.put_actor("admin", ["ehos_contract_admin"])
      |> live("/dashboard/contract")

    report = EhosContract.Conformance.report(CaseRun, [])
    [process] = report.processes

    assert html =~ "<h2>web_test_host.case_run</h2>"
    assert html =~ "Version #{report.deployment.deployed.version}"
    assert html =~ "<h3>A case, from opening to closing</h3>"
    assert html =~ "Runs in this period: 1, one per case_id."

    [promise] = process.promises
    assert html =~ escape(Sentence.rule(promise))
    assert html =~ ~s(<p class="outcome-ok">#{Sentence.verdict(promise)}</p>)
  end

  # Plan DD, P2e (#220), review: every process module's report read the whole history
  # twice per visit, for the static render and again once connected.
  test "a process module's report waits for the connection; the contracts' do not" do
    approve("case-a")
    conn = Access.put_actor(build_conn(), "admin", ["ehos_contract_admin"])
    static = conn |> get("/dashboard/contract") |> html_response(200)

    assert static =~ "reports are read once the page connects."
    refute static =~ "<h2>web_test_host.case_run</h2>"
    assert static =~ "web_test_host.case_handling"

    {:ok, _view, connected} = live(conn, "/dashboard/contract")
    assert connected =~ "<h2>web_test_host.case_run</h2>"
    refute connected =~ "read once the page connects"
  end

  test "a process module's duration, stages out of order and a broken promise" do
    approve("case-a")
    report = EhosContract.Conformance.report(CaseRun, [])
    [process] = report.processes
    [promise] = process.promises

    process = %{
      process
      | accountable: "Case officer",
        declarations: [%{key: :deadline, value: {7, :day}}],
        duration: %{runs: 3, within: 1, exceeded: 1, overdue: 1, deadline: {7, :day}},
        out_of_order: %{
          runs: 2,
          pairs: [
            %{
              earlier: :opening,
              later: :closing,
              runs: 2,
              earlier_label: "Opening",
              later_label: "Closing"
            }
          ]
        },
        promises: [%{promise | instances: 3, satisfied: 1, violated: 1, pending: 1, suspended: 1}]
    }

    html =
      render_component(&ContractStatus.render/1, %{
        ehos_contract_web_access: :all,
        ehos_contract_web_base_path: "/dashboard",
        reports: [],
        processes: [put_in(%{report | processes: [process]}.deployment.deployed.since, nil)]
      })

    assert html =~ "not recorded as deployed"
    assert html =~ Sentence.accountable("Case officer")
    assert html =~ Sentence.declaration(%{key: :deadline, value: {7, :day}})
    for line <- Sentence.duration(process.duration), do: assert(html =~ line)

    {heading, [pair]} = Sentence.out_of_order(process.out_of_order)
    assert html =~ "<h4>#{heading}</h4>"
    assert html =~ "<li>#{pair}</li>"

    [broken] = process.promises
    assert html =~ ~s(<p class="outcome-breached">#{Sentence.verdict(broken)}</p>)

    # The qualifications beside the verdict, a suspension's among them, are not
    # coloured as a breach.
    assert [_ | _] = qualifications = Sentence.qualifications(broken)
    assert html =~ ~s(class="outcome-qualification")
    for q <- qualifications, do: assert(html =~ escape(q))
  end

  # Plan DD, P2e (#220), review: the screen left out what changed since the
  # previous version, which the text report prints.
  test "a process module's deployment says what changed since the previous version" do
    report = EhosContract.Conformance.report(CaseRun, [])

    changed = %{
      events_added: ["case_closed"],
      events_removed: [],
      agreement_changed: true,
      declarations: %{added: [], removed: [], changed: ["promise:closed_within_a_week"]},
      words: []
    }

    render = fn changed ->
      render_component(&ContractStatus.render/1, %{
        ehos_contract_web_access: :all,
        ehos_contract_web_base_path: "/dashboard",
        reports: [],
        processes: [put_in(report.deployment.changed, changed)]
      })
    end

    html = render.(changed)
    assert html =~ "Since the previous version: events added 1, removed 0."
    assert html =~ "Declarations changed: 1 (promise:closed_within_a_week)."

    # The text report says the same.
    text = EhosContract.Report.render(put_in(report.deployment.changed, changed))

    for line <-
          Sentence.process_deployment(put_in(report.deployment.changed, changed).deployment),
        do: assert(text =~ line and html =~ line)

    assert render.(%{changed | declarations: :not_recorded}) =~
             "was not recorded, so it cannot be compared."

    # Plan DD, V5 (#322): a deploy that changed only the words is no new agreement.
    assert render.(%{changed | agreement_changed: false, words: ["stage:closing"]}) =~
             "Only the words changed since the previous deployment, not the agreement: " <>
               "1 (stage:closing)."
  end

  # HEEx escapes interpolated values, so a sentence carrying a quotation mark is not in
  # the HTML verbatim.
  defp escape(sentence),
    do: sentence |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  test "no event recorded in the contract: the steps say so instead of listing paths" do
    assigns = %{
      ehos_contract_web_access: :all,
      ehos_contract_web_base_path: "/dashboard",
      processes: [],
      reports: [
        report(
          activity: %{events: 0, commands: 0},
          # One declared step: a contract with none says so instead.
          paths: %{steps: [%{}], untraversed: [], in_flight: [], failing: []}
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
      ehos_contract_web_access: :all,
      ehos_contract_web_base_path: "/dashboard",
      processes: [],
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

  @drift %{
    from: %{kind: :command, name: :a, label: "A"},
    to: %{kind: :event, name: :b, label: "B"},
    count: 4
  }

  test "drift renders the undeclared edge, and its absence renders as none" do
    with_drift =
      render_component(&ContractStatus.render/1, %{
        ehos_contract_web_access: :all,
        ehos_contract_web_base_path: "/dashboard",
        processes: [],
        reports: [
          report(drift: [@drift])
        ]
      })

    without_drift =
      render_component(&ContractStatus.render/1, %{
        ehos_contract_web_access: :all,
        ehos_contract_web_base_path: "/dashboard",
        processes: [],
        reports: [report()]
      })

    assert with_drift =~ EhosContract.Report.Sentence.drift(@drift)

    assert without_drift =~ "None: nothing happened outside the agreement."
  end

  test "an unconfirmed deployment says nothing has happened under it yet" do
    html =
      render_component(&ContractStatus.render/1, %{
        ehos_contract_web_access: :all,
        ehos_contract_web_base_path: "/dashboard",
        processes: [],
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
end
