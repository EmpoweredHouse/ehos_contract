defmodule Lending.Circulation.Loan do
  @moduledoc """
  **Invented.** Decides a loan: lent once and only on a card that is not suspended,
  chased while the copy is out, back once, and charged the late fee the desk's tariff
  supplies when there is one. A fee owed is paid or waived, once.
  """

  use Lending.Contracts.Circulation, aggregate: :loan

  @impl true
  def lend_copy(_command, %State{lent: true}, _read), do: reject(:lent_once)

  def lend_copy(_command, _state, %{card: %{suspended: true}}),
    do: reject(:suspended_card_borrows_nothing)

  def lend_copy(%LendCopy{} = command, _state, _read) do
    emit(%CopyLent{
      loan_id: command.loan_id,
      copy_id: command.copy_id,
      member_id: command.member_id,
      card_id: command.card_id,
      due_at: command.due_at
    })
  end

  @impl true
  def return_copy(_command, %State{lent: false}), do: reject(:only_a_copy_out_comes_back)
  def return_copy(_command, %State{returned: true}), do: reject(:only_a_copy_out_comes_back)

  def return_copy(%ReturnCopy{loan_id: id, late_fee: 0}, _state),
    do: emit(%CopyReturned{loan_id: id})

  def return_copy(%ReturnCopy{loan_id: id, late_fee: fee}, _state),
    do: emit([%CopyReturned{loan_id: id}, %LateFeeCharged{loan_id: id, fee: fee}])

  @impl true
  def send_overdue_notice(%SendOverdueNotice{loan_id: id}, %State{lent: true, returned: false}),
    do: emit(%OverdueNoticeSent{loan_id: id})

  def send_overdue_notice(_command, _state), do: reject(:only_a_copy_out_is_chased)

  @impl true
  def pay_late_fee(%PayLateFee{loan_id: id}, %State{fee_owed: true}),
    do: emit(%LateFeePaid{loan_id: id})

  def pay_late_fee(_command, _state), do: reject(:only_an_owed_fee_is_settled)

  @impl true
  def waive_late_fee(%WaiveLateFee{loan_id: id}, %State{fee_owed: true}),
    do: emit(%LateFeeWaived{loan_id: id})

  def waive_late_fee(_command, _state), do: reject(:only_an_owed_fee_is_settled)

  @impl true
  def evolve(state, %CopyLent{}), do: %{state | lent: true}
  def evolve(state, %CopyReturned{}), do: %{state | returned: true}
  def evolve(state, %LateFeeCharged{}), do: %{state | fee_owed: true}
  def evolve(state, %LateFeePaid{}), do: %{state | fee_owed: false}
  def evolve(state, %LateFeeWaived{}), do: %{state | fee_owed: false}
  def evolve(state, %OverdueNoticeSent{}), do: state

  @doc """
  What each invariant means of a state the decisions reached, for the properties
  `EhosContract.PropertyCase` writes: a copy is back only after it was lent, and a fee
  is owed only on a copy back.
  """
  @spec holds?(atom(), State.t()) :: boolean()
  def holds?(:only_a_copy_out_comes_back, state), do: not state.returned or state.lent
  def holds?(:only_an_owed_fee_is_settled, state), do: not state.fee_owed or state.returned

  # Each of these refuses a request on what the state already says, and leaves no state
  # of its own to check: its scenario and the decision's property show it.
  def holds?(:lent_once, _state), do: true
  def holds?(:suspended_card_borrows_nothing, _state), do: true
  def holds?(:only_a_copy_out_is_chased, _state), do: true
end
