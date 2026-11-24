defmodule EhosContract.ProcessModuleRunsTest do
  @moduledoc """
  Plan DD, P2c (#210): **dispatch files an event into the runs of every process module
  that includes it**, under the module's `id:` and keyed by its `correlate`, beside the
  event's other runs. On the invented `DispatchRig.AccountReview`, which includes the
  ledger's withdrawals and balance confirmations, beside `DispatchRig.LedgerRun` and
  `DispatchRig.BranchRun`, the ledger's other runs since plan DD, P2g (#228).
  """

  use EhosContract.DataCase, async: false

  alias DispatchRig.Ledger
  alias DispatchRig.Ledger.Commands.{Deposit, OpenAccount, Withdraw}
  alias DispatchRig.Ledger.Events.BalanceConfirmed
  alias EhosContract.{Actor, Event, EventRun, Implementations}

  @clerk Actor.credential("u-1", ~w(dispatch_rig.open_account dispatch_rig.deposit
    dispatch_rig.withdraw))
  @auditor Actor.credential("u-2", ["dispatch_rig.balance_confirmed"])

  defp dispatch(command), do: {:ok, _} = EhosContract.dispatch(Ledger, command, actor: @clerk)

  defp runs(type) do
    Repo.all(
      from(r in EventRun,
        join: e in Event,
        on: e.position == r.position,
        where: e.type == ^type,
        order_by: [e.position, r.process],
        select: {r.process, r.instance_id}
      )
    )
  end

  setup do
    dispatch(%OpenAccount{account_id: "a-1", branch_id: "b-7"})
    dispatch(%Deposit{account_id: "a-1", amount: 100})
    :ok
  end

  test "the index names the module, by its id, for each event it includes" do
    review = %{name: "dispatch_rig.account_review", correlate: [:account_id]}

    assert review in Implementations.included(Ledger, "dispatch_rig.ledger.withdrawn")
    assert review in Implementations.included(Ledger, "dispatch_rig.ledger.balance_confirmed")
    refute review in Implementations.included(Ledger, "dispatch_rig.ledger.deposited")
  end

  test "a process module of another domain gets no runs for this domain's events" do
    review = DispatchRig.AccountReview.__ehos_contract_model__()
    run = %{name: "dispatch_rig.account_review", correlate: [:account_id]}

    assert Implementations.runs_of([review])["dispatch_rig.ledger.withdrawn"] == [run]
    assert Implementations.runs_of([%{review | domain: Elsewhere.Domain}]) == %{}
  end

  test "an included event belongs to the run of every module that includes it, under its id" do
    dispatch(%Withdraw{account_id: "a-1", amount: 50})

    assert runs("dispatch_rig.ledger.withdrawn") == [
             {"dispatch_rig.account_review", "dispatch_rig.account_review|a-1"},
             {"dispatch_rig.ledger_run", "dispatch_rig.ledger_run|a-1"}
           ]
  end

  test "a recorded event the module includes is filed into its run too" do
    {:ok, _} =
      EhosContract.record(Ledger, %BalanceConfirmed{account_id: "a-1"}, actor: @auditor)

    assert runs("dispatch_rig.ledger.balance_confirmed") == [
             {"dispatch_rig.account_review", "dispatch_rig.account_review|a-1"},
             {"dispatch_rig.ledger_run", "dispatch_rig.ledger_run|a-1"}
           ]
  end

  test "control: an event the review does not include is in no review's run" do
    assert runs("dispatch_rig.ledger.deposited") == [
             {"dispatch_rig.ledger_run", "dispatch_rig.ledger_run|a-1"}
           ]

    # The branch's run, another module including the opening, is its own.
    assert runs("dispatch_rig.ledger.account_opened") == [
             {"dispatch_rig.branch_run", "dispatch_rig.branch_run|b-7"},
             {"dispatch_rig.ledger_run", "dispatch_rig.ledger_run|a-1"}
           ]
  end
end
