defmodule DispatchRig.FirstDepositChase do
  @moduledoc """
  **Invented.** Gives a new account a day for its first deposit: the day passing
  flags the account, and so does interest recorded before any deposit.
  """

  use DispatchRig.Ledger, process_manager: :first_deposit_chase

  @impl true
  def first_deposit_due(%State{account_id: id}), do: issue(%FlagAccount{account_id: id})

  @impl true
  def interest_recorded(%InterestRecorded{account_id: id}, %State{deposits: 0}),
    do: issue(%FlagAccount{account_id: id})

  def interest_recorded(_interest, _state), do: {:ok, []}

  @impl true
  def evolve(state, %Deposited{}), do: %{state | deposits: state.deposits + 1}
  def evolve(state, _other), do: state
end
