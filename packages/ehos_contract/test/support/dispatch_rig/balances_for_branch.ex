defmodule DispatchRig.BalancesForBranch do
  @moduledoc """
  **Invented.** The balances of one branch. A test can make it forget its `where`,
  `Process.put(:dispatch_rig_leak, true)`, to watch dispatch stop the rows of
  branches the credential does not grant. It tells the calling process it ran,
  `:dispatch_rig_asked`, so a test can see that a refusal came first.
  """

  use DispatchRig.Ledger, query: :balances_for_branch

  import Ecto.Query

  @impl true
  def balances_for_branch(%BalancesForBranch{branch_id: branch}, _ctx) do
    send(self(), :dispatch_rig_asked)
    query = from(b in "dispatch_rig_balances", select: {b.account_id, b.branch_id, b.balance})

    query =
      if Process.get(:dispatch_rig_leak),
        do: query,
        else: where(query, [b], b.branch_id == ^branch)

    for {account, branch, balance} <- Application.fetch_env!(:ehos_contract, :repo).all(query),
        do: %Row{account_id: account, branch_id: branch, balance: balance}
  end
end
