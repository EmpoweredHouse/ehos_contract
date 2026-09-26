defmodule DispatchRig.Balances do
  @moduledoc "**Invented.** The balances read model, one row per account, written in its own table."

  use DispatchRig.Ledger, read_model: :balances

  import Ecto.Query

  @impl true
  def account_opened(%AccountOpened{account_id: id, branch_id: branch}) do
    repo().insert_all("dispatch_rig_balances", [%{account_id: id, branch_id: branch, balance: 0}])
    :ok
  end

  @impl true
  def deposited(%Deposited{account_id: id, amount: amount}), do: move(id, amount)

  @impl true
  def withdrawn(%Withdrawn{account_id: id, amount: amount}), do: move(id, -amount)

  @impl true
  def interest_recorded(%InterestRecorded{account_id: id, amount: amount}), do: move(id, amount)

  defp move(id, amount) do
    repo().update_all(from(b in "dispatch_rig_balances", where: b.account_id == ^id),
      inc: [balance: amount]
    )

    :ok
  end

  defp repo, do: Application.fetch_env!(:eh_os_contract, :repo)
end
