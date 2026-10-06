defmodule EhOsContract.ContractIdRowsTest do
  @moduledoc """
  Plan DD, ID4 (#178): what the engine stores names a contract by its `id:`, never by
  the module that holds it, so moving the module keeps its history. An id is looked up
  whole: `dispatch_rig` is no prefix of `dispatch_rig.ledger` to the lookup.
  """

  use EhOsContract.DataCase, async: false

  alias DispatchRig.Ledger
  alias DispatchRig.Ledger.Commands.{Deposit, OpenAccount, Withdraw}
  alias EhOsContract.{Actor, CommandRecord, Deployment, Event, Implementations}

  @clerk Actor.credential("u-1", [
           "dispatch_rig.open_account",
           "dispatch_rig.deposit",
           "dispatch_rig.withdraw"
         ])

  defp dispatch(command), do: EhOsContract.dispatch(Ledger, command, actor: @clerk)

  test "events, commands and deployments name the contract by its id" do
    {:ok, _} = dispatch(%OpenAccount{account_id: "a-1", branch_id: "b-7"})
    {:ok, _} = dispatch(%Deposit{account_id: "a-1", amount: 100})
    {:error, _} = dispatch(%Withdraw{account_id: "a-1", amount: 500})

    assert Repo.all(from(e in Event, select: e.contract, distinct: true)) == [
             "dispatch_rig.ledger"
           ]

    assert Repo.all(from(c in CommandRecord, select: c.contract, distinct: true)) == [
             "dispatch_rig.ledger"
           ]

    :ok = Deployment.record!()
    assert [%{contract: "dispatch_rig.ledger"} | _] = Deployment.all(Ledger)
  end

  test "an id is found whole, never by a prefix, and never by the module's name" do
    assert %{module: Ledger} = Implementations.contract("dispatch_rig.ledger")

    for other <- ["dispatch_rig", "dispatch_rig.ledger.deposited", "DispatchRig.Ledger"] do
      assert Implementations.contract(other) == nil, "#{other} found a contract"
    end
  end
end
