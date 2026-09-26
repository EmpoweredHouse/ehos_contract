defmodule DispatchRig.FirstDepositChase do
  @moduledoc """
  **Invented.** Gives a new account a day for its first deposit: the day passing
  flags the account, and so does interest recorded before any deposit. A deposit
  sets a review a week after it, a timer at `review_at` of the state, which flags the
  account too.
  """

  use DispatchRig.Ledger, process_manager: :first_deposit_chase

  @impl true
  def first_deposit_due(%State{account_id: id}), do: issue(%FlagAccount{account_id: id})

  @impl true
  def interest_recorded(%InterestRecorded{account_id: id}, %State{deposits: 0}),
    do: issue(%FlagAccount{account_id: id})

  def interest_recorded(_interest, _state), do: {:ok, []}

  @impl true
  def review(%State{account_id: id}), do: issue(%FlagAccount{account_id: id})

  @impl true
  def evolve(state, %Deposited{__meta__: meta}),
    do: %{
      state
      | deposits: state.deposits + 1,
        review_at: DateTime.add(meta.occurred_at, 7, :day)
    }

  def evolve(state, _other), do: state
end
