defmodule Lending.Circulation.OverdueChase do
  @moduledoc """
  **Invented.** Chases a copy that is late: the first reminder at the loan's due date,
  each next one a week after the last, until the copy comes back. The next date is
  counted from the stored one, not from when the notice went out, so a reminder sent
  late does not move the ones after it.
  """

  use Lending.Contracts.Circulation, process_manager: :overdue_chase

  @week 7 * 24 * 3600

  @impl true
  def reminder(%State{loan_id: id}), do: issue(%SendOverdueNotice{loan_id: id})

  @impl true
  def evolve(state, %CopyLent{due_at: due}), do: %{state | remind_at: due}

  def evolve(%State{remind_at: at} = state, %OverdueNoticeSent{}),
    do: %{state | remind_at: DateTime.add(at, @week)}

  def evolve(state, %CopyReturned{}), do: state
end
