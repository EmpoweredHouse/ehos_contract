defmodule DispatchRig.FlagLargeWithdrawal do
  @moduledoc "**Invented.** Flags an account on a withdrawal of 1000 or more, after the fact."

  use DispatchRig.Ledger, policy: :flag_large_withdrawal

  @impl true
  def withdrawn(%Withdrawn{account_id: id, amount: amount}) when amount >= 1000,
    do: issue(%FlagAccount{account_id: id})

  def withdrawn(_small), do: {:ok, []}
end
