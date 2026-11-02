defmodule EhOsContract.ReadYourWritesTest do
  @moduledoc """
  `min_position:` on a query (v2 §11, plan E7c-2): a query over a read model
  projected after the transaction waits until that read model has taken the
  position the dispatch returned, and refuses rather than answer from before it.
  """

  use EhOsContract.DataCase, async: false

  @moduletag :capture_log

  alias DispatchRig.Ledger
  alias DispatchRig.Ledger.Commands.{Deposit, OpenAccount}
  alias DispatchRig.Ledger.Queries.{BalanceOf, LinesOf}
  alias EhOsContract.{Actor, Testing}

  @clerk Actor.credential("u-1", ["dispatch_rig.open_account", "dispatch_rig.deposit"])
  @auditor Actor.credential("u-2", ["dispatch_rig.lines_of", "dispatch_rig.balance_of"])

  defp dispatch(command), do: EhOsContract.dispatch(Ledger, command, actor: @clerk)

  defp lines(opts),
    do: EhOsContract.query(Ledger, %LinesOf{account_id: "a-1"}, [actor: @auditor] ++ opts)

  # The row of a subscription that stopped at the event after `position`.
  defp failing!(key, position) do
    {1, _} =
      Repo.update_all(from(s in EhOsContract.SubscriptionRecord, where: s.name == ^key),
        set: [status: "failing", position: position, failed_position: position + 1]
      )
  end

  setup do
    Testing.drain()
    {:ok, _} = dispatch(%OpenAccount{account_id: "a-1", branch_id: "b-7"})
    {:ok, receipt} = dispatch(%Deposit{account_id: "a-1", amount: 10})
    {:ok, position: receipt.position}
  end

  test "without it, a query answers from where the read model is", %{position: _} do
    assert {:ok, []} = lines([])
  end

  test "with it, the query waits until the read model has the write", %{position: position} do
    drained =
      Task.async(fn ->
        Process.sleep(100) && Testing.drain(only: "dispatch_rig.ledger:read_model:ledger_lines")
      end)

    assert {:ok, [%{account_id: "a-1", amount: 10}]} = lines(min_position: position)
    Task.await(drained)
  end

  test "and refuses when the read model does not get there in time", %{position: position} do
    assert {:error, :not_caught_up} = lines(min_position: position, wait: 50)
  end

  test "a read model projected in the transaction that failed while it was rebuilt refuses", %{
    position: position
  } do
    failing!("dispatch_rig.ledger:read_model:balances", position)

    assert {:error, :not_caught_up} =
             EhOsContract.query(Ledger, %BalanceOf{account_id: "a-1"},
               actor: @auditor,
               min_position: position,
               wait: 0
             )
  end

  test "control: a failing read model projected after the transaction answers up to where it stopped",
       %{position: position} do
    failing!("dispatch_rig.ledger:read_model:ledger_lines", position)
    assert {:ok, []} = lines(min_position: position, wait: 0)
  end

  test "a read model projected in the transaction already has it", %{position: position} do
    assert {:ok, %{balance: 10}} =
             EhOsContract.query(Ledger, %BalanceOf{account_id: "a-1"},
               actor: @auditor,
               min_position: position,
               wait: 0
             )
  end
end
