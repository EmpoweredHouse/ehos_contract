defmodule DispatchRig.FlagLargeDeposit do
  @moduledoc """
  **Invented.** Flags an account on a deposit of 1000 or more.

  Or issues a deposit instead, once, after `Process.put(:dispatch_rig_flag_strays,
  true)`: a command the policy does not declare it issues, returned without `issue/1`,
  where I6 cannot see it, so that a test can watch dispatch's own guard stop it.
  """

  use DispatchRig.Ledger, policy: :flag_large_deposit

  @impl true
  def deposited(%Deposited{account_id: id, amount: amount}) when amount >= 1000 do
    if Process.delete(:dispatch_rig_flag_strays),
      do: {:ok, [stray(id)]},
      else: issue(%FlagAccount{account_id: id})
  end

  def deposited(_small), do: {:ok, []}

  # Built in a function of its own, which is what I6, reading struct literals in
  # `issue/1`, cannot follow.
  defp stray(id), do: %DispatchRig.Ledger.Commands.Deposit{account_id: id, amount: 1}
end
