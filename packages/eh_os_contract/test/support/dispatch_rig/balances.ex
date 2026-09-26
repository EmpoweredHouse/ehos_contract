defmodule DispatchRig.Balances do
  @moduledoc """
  **Invented.** The balances read model, one row per account, written in its own
  table, with the position of the last event it projected: the one field of an
  event's `__meta__` a projection most often needs.
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
  def deposited(%Deposited{account_id: id, amount: amount, __meta__: meta}),
    do: move(id, amount, meta.position)

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
