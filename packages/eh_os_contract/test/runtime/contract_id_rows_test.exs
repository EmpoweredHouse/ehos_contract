defmodule EhOsContract.ContractIdRowsTest do
  @moduledoc """
  Plan DD, ID4 (#178): what the engine stores names a contract by its `id:`, never by
  the module that holds it, so moving the module keeps its history. An id is looked up
  whole: `dispatch_rig` is no prefix of `dispatch_rig.ledger` to the lookup.
  """

  use EhOsContract.DataCase, async: false

  alias DispatchRig.Ledger
  alias DispatchRig.Ledger.Commands.{Deposit, OpenAccount, Withdraw}
  alias EhOsContract.{Actor, CommandRecord, Deployment, Event, Implementations, Model, Registry}

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

  # X7 refuses one id twice in an application; two applications a node scans meet only here.
  test "two contracts of one id across the scanned applications are refused, naming both" do
    ledger = Model.fetch(Ledger)
    till = Model.fetch(ValueRig.Till)

    assert Registry.unique_ids!([ledger, till]) == :ok
    # One application listed twice, or reached twice, shows a contract twice: still one.
    assert Registry.unique_ids!([ledger, till, ledger]) == :ok

    error =
      assert_raise ArgumentError, fn ->
        Registry.unique_ids!([ledger, %{till | id: ledger.id}])
      end

    assert error.message =~ ~s(the id: "dispatch_rig.ledger" is declared by DispatchRig.Ledger)
    assert error.message =~ "ValueRig.Till (:eh_os_contract)"
  end

  # A sibling a scanned contract consumes is found by its id even when no scan reaches
  # its application: `consumes` names it by module (review of #181).
  test "an id finds a sibling a scanned contract consumes" do
    branch = Model.fetch(DispatchRig.Branch)

    assert %{"dispatch_rig.ledger" => %{module: Ledger}} = Implementations.by_id([branch])

    # One this node cannot load is left out, not raised on: every dispatch builds this.
    missing = %{kind: :contract, from: DispatchRig.NotInThisRelease, events: [:x]}
    with_missing = %{branch | consumes: [missing | branch.consumes]}
    assert %{"dispatch_rig.ledger" => _} = Implementations.by_id([with_missing])
  end
end
