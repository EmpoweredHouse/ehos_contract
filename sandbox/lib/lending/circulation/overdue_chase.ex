defmodule Lending.Circulation.OverdueChase do
  @moduledoc """
  **Invented.** Chases a copy that is late: the first reminder at the loan's due date,
  each next one a week after the last, until the copy comes back. The next date is
  counted from the reminder's own date, so a notice sent an hour late does not move
  the ones after it. Only a notice that went out a week or more after its date counts
  the next from itself: a loan due months ago is reminded once, and then weekly from
  then on, not once for every week it missed.
  """

  use Lending.Contracts.Circulation, process_manager: :overdue_chase

  @week 7 * 24 * 3600

  @impl true
  def reminder(%State{loan_id: id}), do: issue(%SendOverdueNotice{loan_id: id})

  @impl true
  def evolve(state, %CopyLent{due_at: due}), do: %{state | remind_at: due}

  # A week after the reminder's own date, unless that is already past when the notice
  # went out; then a week after the notice.
  def evolve(%State{remind_at: at} = state, %OverdueNoticeSent{__meta__: meta}) do
    next = DateTime.add(at, @week)

    if DateTime.compare(next, meta.occurred_at) == :gt,
      do: %{state | remind_at: next},
      else: %{state | remind_at: DateTime.add(meta.occurred_at, @week)}
  end

  def evolve(state, %CopyReturned{}), do: state
end
