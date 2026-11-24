defmodule DispatchRig.Movements do
  @moduledoc """
  **Invented.** One row per deposit. It raises on a deposit of exactly 13, which
  exists only so that a test can watch a failing projection roll the append back.
  """

  use DispatchRig.Ledger, read_model: :movements

  @impl true
  def deposited(%Deposited{amount: 13}), do: raise("the movements projection fails on 13")

  def deposited(%Deposited{account_id: id, amount: amount}) do
    Application.fetch_env!(:ehos_contract, :repo)
    |> then(& &1.insert_all("dispatch_rig_movements", [%{account_id: id, amount: amount}]))

    :ok
  end
end
