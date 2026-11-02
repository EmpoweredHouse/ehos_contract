defmodule DispatchRig.Balances do
  @moduledoc """
  **Invented.** The balances read model, one row per account, written in its own
  table, with the position of the last event it projected: the one field of an
  event's `__meta__` a projection most often needs.

  A test can make it raise on a deposit of exactly 77,
  `Process.put(:dispatch_rig_balances_fail, true)`: dispatch would roll back on it, so
  this is how a rebuild meets an event it cannot apply.
  """

  use DispatchRig.Ledger, read_model: :balances

  import Ecto.Query

  @impl true
  def account_opened(%AccountOpened{account_id: id, branch_id: branch, __meta__: meta}) do
    repo().insert_all("dispatch_rig_balances", [
      %{account_id: id, branch_id: branch, balance: 0, last_position: meta.position}
    ])

    :ok
  end

  @impl true
  def deposited(%Deposited{account_id: id, amount: amount, __meta__: meta}) do
    if amount == 77 and Process.get(:dispatch_rig_balances_fail),
      do: raise("the balances fail on 77")

    move(id, amount, meta.position)
  end

  @impl true
  def withdrawn(%Withdrawn{account_id: id, amount: amount, __meta__: meta}),
    do: move(id, -amount, meta.position)

  @impl true
  def interest_recorded(%InterestRecorded{account_id: id, amount: amount, __meta__: meta}),
    do: move(id, amount, meta.position)

  # A flag moves no money; the row only records that it has read that far.
  @impl true
  def account_flagged(%AccountFlagged{account_id: id, __meta__: meta}),
    do: move(id, 0, meta.position)

  @impl true
  def reset do
    repo().delete_all("dispatch_rig_balances")
    :ok
  end

  defp move(id, amount, position) do
    repo().update_all(from(b in "dispatch_rig_balances", where: b.account_id == ^id),
      inc: [balance: amount],
      set: [last_position: position]
    )

    :ok
  end

  defp repo, do: Application.fetch_env!(:eh_os_contract, :repo)
end
