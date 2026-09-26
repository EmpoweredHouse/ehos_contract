defmodule DispatchRig.FlagLargeDeposit do
  @moduledoc "**Invented.** Flags an account on a deposit of 1000 or more."

  use DispatchRig.Ledger, policy: :flag_large_deposit

  @impl true
  def deposited(%Deposited{account_id: id, amount: amount}) when amount >= 1000,
    do: issue(%FlagAccount{account_id: id})

  def deposited(_small), do: {:ok, []}
end
