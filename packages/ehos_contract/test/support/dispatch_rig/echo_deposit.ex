defmodule DispatchRig.EchoDeposit do
  @moduledoc """
  **Invented.** Repeats a deposit of 777, which deposits 777 again: a cycle, for the
  guard dispatch keeps from v1's emitter. Any other deposit issues nothing.
  """

  use DispatchRig.Ledger, policy: :echo_deposit

  @impl true
  def deposited(%Deposited{account_id: id, amount: 777}),
    do: issue(%Deposit{account_id: id, amount: 777})

  def deposited(_other), do: {:ok, []}
end
