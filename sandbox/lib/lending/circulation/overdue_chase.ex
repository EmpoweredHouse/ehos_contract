defmodule Lending.Circulation.OverdueChase do
  @moduledoc """
  **Invented.** Chases a copy that is late: the first reminder at the loan's due date,
  each next one a week after the last, until the copy comes back. The next date is
  counted from the reminder's own date, so a notice sent an hour late does not move
  the ones after it, unless the notice went out after that date: a loan due months ago
  is reminded once, and then weekly from then on, not once for every week it missed.
  """

  use Lending.Contracts.Circulation, process_manager: :overdue_chase

  @week 7 * 24 * 3600

  @impl true
  def reminder(%State{loan_id: id}), do: issue(%SendOverdueNotice{loan_id: id})

  @impl true
  def evolve(state, %CopyLent{due_at: due}), do: %{state | remind_at: due}

  def evolve(%State{remind_at: at} = state, %OverdueNoticeSent{__meta__: meta}),
    do: %{state | remind_at: DateTime.add(latest(at, meta.occurred_at), @week)}

  def evolve(state, %CopyReturned{}), do: state

  defp latest(a, b), do: if(DateTime.compare(a, b) == :lt, do: b, else: a)
end
