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

  describe "the declared shape of a v2 process" do
    test "its stages are lanes, its promise an arrow with its window, its endings marked" do
      shape = Graph.declared_to_mermaid(ProcessShapes.Promised, :handling)

      assert shape =~ "flowchart TB"
      assert shape =~ ~s(subgraph stage_intake["intake · no order claimed inside"])
      assert shape =~ ~s(        request_received["Request received"])
      assert shape =~ "stage_intake --> stage_decision"
      assert shape =~ "request_received ==>|within 2 days| request_completed"
      assert shape =~ "request_received -.->|or else| refusal_notified"
      assert shape =~ "class request_completed,refusal_notified terminal"
    end

    test "an included event is in its run's picture, and an external comes from the domain" do
      assert Graph.declared_to_mermaid(DispatchRig.Branch, :branch) =~
               ~s(    account_opened["Account opened"])

      shape =
        Graph.declared_to_mermaid(UniversalityGate.TreatmentEpisode, :treatment_episode)

      assert shape =~
               ~s|payer_registry[("Payer registry: confirmation of eligibility for treatment")]|

      assert shape =~ "payer_eligibility_checked -.- payer_registry"
    end
  end

  @tag :tmp_dir
  test "mix eh_os_contract.graph --process draws a v2 process's shape, and with --overlay its graph",
       %{tmp_dir: dir} do
    path = Path.join(dir, "handling.mmd")
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    Mix.Tasks.EhOsContract.Graph.run(["--process", "ledger", "--mermaid", "--output", path])
    assert File.read!(path) =~ ~s(    account_opened["Account opened"])
    refute File.read!(path) =~ "command_open_account"

    Mix.Tasks.EhOsContract.Graph.run([
      "--process",
      "ledger",
      "--mermaid",
      "--overlay",
      "--output",
      path
    ])

    assert File.read!(path) =~ "command_open_account -->|0 taken| event_account_opened"
  end
end
