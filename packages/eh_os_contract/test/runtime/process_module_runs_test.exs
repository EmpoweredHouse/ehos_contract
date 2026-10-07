defmodule EhOsContract.ProcessModuleRunsTest do
  @moduledoc """
  Plan DD, P2c (#210): **dispatch files an event into the runs of every process module
  that includes it**, under the module's `id:` and keyed by its `correlate`, beside the
  event's home run. On the invented `DispatchRig.AccountReview`, which includes the
  ledger's withdrawals and balance confirmations.
  """

  use EhOsContract.DataCase, async: false

  alias DispatchRig.Ledger
  alias DispatchRig.Ledger.Commands.{Deposit, OpenAccount, Withdraw}
  alias DispatchRig.Ledger.Events.BalanceConfirmed
  alias EhOsContract.{Actor, Event, EventRun, Implementations}

  @clerk Actor.credential("u-1", ~w(dispatch_rig.open_account dispatch_rig.deposit
    dispatch_rig.withdraw))
  @auditor Actor.credential("u-2", ["dispatch_rig.balance_confirmed"])

  defp dispatch(command), do: {:ok, _} = EhOsContract.dispatch(Ledger, command, actor: @clerk)

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

  test "an included event belongs to its home run and to the module's, under the module's id" do
    dispatch(%Withdraw{account_id: "a-1", amount: 50})

    assert runs("dispatch_rig.ledger.withdrawn") == [
             {"dispatch_rig.account_review", "dispatch_rig.account_review|a-1"},
             {"ledger", "ledger|a-1"}
           ]
  end

  test "a recorded event the module includes is filed into its run too" do
    {:ok, _} =
      EhOsContract.record(Ledger, %BalanceConfirmed{account_id: "a-1"}, actor: @auditor)

    assert runs("dispatch_rig.ledger.balance_confirmed") == [
             {"dispatch_rig.account_review", "dispatch_rig.account_review|a-1"},
             {"ledger", "ledger|a-1"}
           ]
  end

  test "control: an event no module includes keeps the runs it had" do
    assert runs("dispatch_rig.ledger.deposited") == [{"ledger", "ledger|a-1"}]

    # The branch's run, a contract's process including the opening, is unchanged.
    assert runs("dispatch_rig.ledger.account_opened") == [
             {"branch", "branch|b-7"},
             {"ledger", "ledger|a-1"}
           ]
  end
end
