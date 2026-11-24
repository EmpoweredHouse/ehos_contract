defmodule DispatchRig.BalanceOf do
  @moduledoc """
  **Invented.** One account's balance, or nil. A test can make it answer a list,
  `Process.put(:dispatch_rig_as_list, true)`, which a query returning one must not.
  """

  use DispatchRig.Ledger, query: :balance_of

  import Ecto.Query

  @impl true
  def balance_of(%BalanceOf{account_id: id}, _ctx) do
    rows =
      for {account, branch, balance} <-
            Application.fetch_env!(:ehos_contract, :repo).all(
              from(b in "dispatch_rig_balances",
                where: b.account_id == ^id,
                select: {b.account_id, b.branch_id, b.balance}
              )
            ),
          do: %Row{account_id: account, branch_id: branch, balance: balance}

    if Process.get(:dispatch_rig_as_list), do: rows, else: List.first(rows)
  end
end
