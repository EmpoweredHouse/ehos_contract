defmodule EhOsContract.StageOrderTest do
  @moduledoc """
  Plan DD, O1 (#260): **the runs that reached a later stage before an earlier one**, on
  the invented `DispatchRig.AccountReview`, whose stages are a withdrawal and then the
  auditor's confirmation of the balance. The rules are the ones agreed with EHOS in
  EmpoweredHouse/eh-os#297: by position in the log, only stages a run reached, the period
  not cutting a run, a stage entered by its first event.
  """

  use EhOsContract.DataCase, async: false

  alias DispatchRig.{AccountReview, Ledger}
  alias DispatchRig.Ledger.Commands.{Deposit, OpenAccount, Withdraw}
  alias DispatchRig.Ledger.Events.BalanceConfirmed
  alias EhOsContract.{Actor, Conformance, Report, StageOrder}

  @clerk Actor.credential("u-1", ~w(dispatch_rig.open_account dispatch_rig.deposit
    dispatch_rig.withdraw))
  @auditor Actor.credential("u-2", ["dispatch_rig.balance_confirmed"])

  defp dispatch(command), do: {:ok, _} = EhOsContract.dispatch(Ledger, command, actor: @clerk)

  defp withdraw(account) do
    dispatch(%OpenAccount{account_id: account, branch_id: "b-7"})
    dispatch(%Deposit{account_id: account, amount: 100})
    dispatch(%Withdraw{account_id: account, amount: 50})
  end

  defp confirm(account) do
    {:ok, _} =
      EhOsContract.record(Ledger, %BalanceConfirmed{account_id: account}, actor: @auditor)
  end

  # A moment strictly between what came before and what comes after.
  defp mark do
    Process.sleep(2)
    at = DateTime.utc_now()
    Process.sleep(2)
    at
  end

  @pair %{earlier: :withdrawal, later: :confirmation}

  test "a run confirmed before its withdrawal counts; one in order, or one that skipped a stage, does not" do
    withdraw("in-order")
    confirm("in-order")
    withdraw("in-order-too")
    confirm("in-order-too")

    confirm("out-of-order")
    withdraw("out-of-order")

    confirm("never-withdrawn")
    withdraw("never-confirmed")

    assert StageOrder.evaluate(AccountReview) == %{runs: 1, pairs: [Map.put(@pair, :runs, 1)]}
  end

  test "a stage is entered by its first event, so one entered again later still counts" do
    confirm("a-1")
    withdraw("a-1")
    confirm("a-1")

    assert %{runs: 1} = StageOrder.evaluate(AccountReview)
  end

  test "the period takes a run by its first event and judges it whole" do
    confirm("began-inside")
    until = mark()
    withdraw("began-inside")
    confirm("began-after")
    withdraw("began-after")

    # Its withdrawal came after `until`, and the run still counts on it.
    assert %{runs: 1} = StageOrder.evaluate(AccountReview, until: until)

    # And a run that began after `until` is not in the period at all.
    assert %{runs: 0, pairs: []} =
             StageOrder.evaluate(AccountReview, since: DateTime.add(until, 1, :day))
  end

  test "is in the report, on the wire and in the text, without naming a run" do
    confirm("a-1")
    withdraw("a-1")

    [process] = Conformance.report(AccountReview).processes

    assert process.out_of_order == %{
             runs: 1,
             pairs: [
               Map.merge(@pair, %{
                 runs: 1,
                 earlier_label: "withdrawal",
                 later_label: "confirmation"
               })
             ]
           }

    [wire] = Conformance.as_data(AccountReview)["report"]["processes"]

    assert wire["out_of_order"] == %{
             "runs" => 1,
             "pairs" => [
               %{
                 "earlier" => "withdrawal",
                 "later" => "confirmation",
                 "runs" => 1,
                 "earlier_label" => "withdrawal",
                 "later_label" => "confirmation"
               }
             ]
           }

    refute Jason.encode!(wire) =~ "a-1"

    text = Report.render(Conformance.report(AccountReview))
    assert text =~ "  Stages out of order in 1 run:\n    · confirmation before withdrawal: 1 run"
  end

  test "a report with every run in order says nothing about the order" do
    withdraw("a-1")
    confirm("a-1")

    assert %{runs: 0, pairs: []} = StageOrder.evaluate(AccountReview)
    refute Report.render(Conformance.report(AccountReview)) =~ "out of order"
  end
end
