defmodule BoundaryRig.WaitlistEntry do
  @moduledoc "**Invented.** The decider of `BoundaryRig.Waitlist`'s entry."

  use BoundaryRig.Waitlist, aggregate: :entry

  @impl true
  def join_waitlist(%JoinWaitlist{entry_id: id, course_id: course, student_id: student}, _state),
    do: emit(%WaitlistJoined{entry_id: id, course_id: course, student_id: student})

  @impl true
  def leave_waitlist(%LeaveWaitlist{entry_id: id}, %State{left: false}),
    do: emit(%WaitlistLeft{entry_id: id})

  def leave_waitlist(_command, _state), do: reject(:still_waiting)

  @impl true
  def evolve(state, %WaitlistLeft{}), do: %{state | left: true}
  def evolve(state, _joined), do: state
end
