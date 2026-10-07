defmodule EhOsContract.GraphTest do
  @moduledoc """
  A v2 contract's graph (v2 §13, plan E7c-2): a node of every kind, in the Event
  Storming colours, and each step as its edges; with the overlay, the log on it. What
  the full graph adds around the steps (plan EG1) is `GraphContractTest`'s.
  """

  use EhOsContract.DataCase, async: false

  alias EhOsContract.Graph
  alias ProcessShapes.Seed

  test "every kind is a node of its own shape and colour" do
    diagram = Graph.contract_to_mermaid(DispatchRig.Ledger)

    assert diagram =~ ~s(command_deposit["Deposit"]:::command)
    assert diagram =~ ~s(event_deposited["Deposited"]:::event)

    assert diagram =~
             ~s(policy_flag_large_deposit{{"Flag an account on a large deposit"}}:::policy)

    assert diagram =~
             ~s(process_manager_first_deposit_chase[["Chase an account's first deposit"]]:::process_manager)

    assert diagram =~ ~s|timer_first_deposit_due(["First deposit due"]):::timer|
    assert diagram =~ ~s(effect_notify_branch>"Tell the branch an account was flagged"]:::effect)
    assert diagram =~ "classDef command fill:#a7c7e7"

    # A command from a person has no event before it, and is on the picture anyway.
    assert diagram =~ "command_open_account --> event_account_opened"
    # A recorded event has no command, and is on it too.
    assert diagram =~ ~s(event_balance_confirmed["Balance confirmed"]:::event)
  end

  test "a reaction is the event reaching its consumer and the consumer's command" do
    diagram = Graph.contract_to_mermaid(DispatchRig.Ledger)

    assert diagram =~ "event_deposited --> policy_flag_large_deposit"
    assert diagram =~ "policy_flag_large_deposit --> command_flag_account"
    assert diagram =~ "event_withdrawn -.->|async| policy_flag_large_withdrawal"
    # The manager sets its timer, which is ownership, not a delivery: no arrowhead, no "async".
    assert diagram =~ "process_manager_first_deposit_chase -. sets .- timer_first_deposit_due"
    refute diagram =~ "process_manager_first_deposit_chase -.->|async| timer_first_deposit_due"
    assert diagram =~ "timer_first_deposit_due -.->|async| command_flag_account"
  end

  test "the overlay puts how often each step was taken on it, and each event's occurrences" do
    Seed.deploy()
    Seed.request("r-1", :request_approved)
    Seed.request("r-2", :request_refused)

    diagram = Graph.contract_to_mermaid(ProcessShapes.Promised, overlay: true)

    assert diagram =~ ~s|event_request_received["Request received (2x)"]:::event|
    assert diagram =~ "command_decide_request -->|1 taken| event_request_approved"

    assert diagram =~
             "policy_notify_on_refusal -.->|async · 0 taken · 1 waiting| command_notify_refusal"

    # The event reaching its consumer is drawn once and carries no count of its own.
    assert diagram =~ "event_request_refused -.->|async| policy_notify_on_refusal"
  end

  test "the overlay counts occurrences: two deposits on one account are two" do
    # Plan DD, P1a (#183): a step is the contract's and counts how often it was taken,
    # whatever run it fell in. Until P1a a step was measured in runs, and two deposits
    # on one account read "1/1 runs"; a contract without a process had no count.
    clerk =
      EhOsContract.Actor.credential("u-1", ["dispatch_rig.open_account", "dispatch_rig.deposit"])

    for command <- [
          %DispatchRig.Ledger.Commands.OpenAccount{account_id: "a-1", branch_id: "b-7"},
          %DispatchRig.Ledger.Commands.Deposit{account_id: "a-1", amount: 5},
          %DispatchRig.Ledger.Commands.Deposit{account_id: "a-1", amount: 6}
        ] do
      {:ok, _} = EhOsContract.dispatch(DispatchRig.Ledger, command, actor: clerk)
    end

    diagram = Graph.contract_to_mermaid(DispatchRig.Ledger, overlay: true)

    assert diagram =~ ~s|event_deposited["Deposited (2x)"]:::event|
    assert diagram =~ "command_deposit -->|2 taken| event_deposited"
  end

  # Since plan DD, P2g (#228) the rigs' processes are modules, which
  # `declared_to_mermaid/2` draws by their id as it draws a contract's by its name.
  describe "the declared shape of a v2 process" do
    test "its stages are lanes, its promise an arrow with its window, its endings marked" do
      shape = Graph.declared_to_mermaid(ProcessShapes.Handling, "process_shapes.handling")

      assert shape =~ "flowchart TB"
      assert shape =~ ~s(subgraph stage_intake["intake · no order claimed inside"])
      assert shape =~ ~s(        request_received["Request received"])
      assert shape =~ "stage_intake --> stage_decision"
      assert shape =~ "request_received ==>|within 2 days| request_completed"
      assert shape =~ "request_received -.->|or else| refusal_notified"
      assert shape =~ "class request_completed,refusal_notified terminal"
    end

    test "an included event is in its run's picture, and an external comes from the domain" do
      assert Graph.declared_to_mermaid(DispatchRig.BranchRun, "dispatch_rig.branch_run") =~
               ~s(    account_opened["Account opened"])

      shape =
        Graph.declared_to_mermaid(
          UniversalityGate.TreatmentEpisodeRun,
          "universality_gate.treatment_episode_run"
        )

      assert shape =~
               ~s|payer_registry[("Payer registry: confirmation of eligibility for treatment")]|

      assert shape =~ "payer_eligibility_checked -.- payer_registry"
    end
  end

  # `--process` finds a process by the name a contract gives it, among the contracts of
  # the configured applications. No rig's contract declares one since plan DD, P2g
  # (#228), so until the contract's `process` goes (#221) the task is handed this one,
  # in an application of its own. Invented, like the ledger it includes from.
  defmodule Openings do
    @moduledoc false
    use EhOsContract.Contract,
      domain: DispatchRig.Domain,
      context: :ledger,
      id: "dispatch_rig.graph_openings"

    consumes DispatchRig.Ledger, :account_opened

    aggregate :branch_note, "Branch note" do
      identity :branch_id
      command :note_branch, "Note a branch", by: :auditor, emits: :branch_noted
      event :branch_noted, "Branch noted"
    end

    process :openings, "Openings" do
      correlate :branch_id
      include :account_opened
    end
  end

  defp with_openings_registered do
    app = :eh_os_contract_graph_openings
    spec = [description: ~c"graph task test", vsn: ~c"0", modules: [Openings], applications: []]
    :ok = :application.load({:application, app, spec})
    apps = Application.get_env(:eh_os_contract, :applications)
    Application.put_env(:eh_os_contract, :applications, List.wrap(apps) ++ [app])

    on_exit(fn ->
      Application.put_env(:eh_os_contract, :applications, apps)
      :application.unload(app)
      EhOsContract.Registry.load!()
    end)
  end

  @tag :tmp_dir
  test "mix eh_os_contract.graph --process draws a v2 process's shape, and with --overlay its graph",
       %{tmp_dir: dir} do
    with_openings_registered()
    path = Path.join(dir, "openings.mmd")
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    Mix.Tasks.EhOsContract.Graph.run(["--process", "openings", "--mermaid", "--output", path])
    assert File.read!(path) =~ ~s(    account_opened["Account opened"])
    refute File.read!(path) =~ "command_note_branch"

    Mix.Tasks.EhOsContract.Graph.run([
      "--process",
      "openings",
      "--mermaid",
      "--overlay",
      "--output",
      path
    ])

    assert File.read!(path) =~ "command_note_branch -->|0 taken| event_branch_noted"
  end
end
