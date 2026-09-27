defmodule BoundaryRig.WaitlistEntry do
  @moduledoc """
  **Invented.** The decider of `BoundaryRig.Waitlist`'s entry.

  A test can make joining decide no event,
  `Process.put(:boundary_rig_join_decides_nothing, true)`, to see what a receipt says
  about an entry that was never made.
  """

  use BoundaryRig.Waitlist, aggregate: :entry

  @impl true
  def join_waitlist(%JoinWaitlist{entry_id: id, course_id: course, student_id: student}, _state) do
    if Process.get(:boundary_rig_join_decides_nothing),
      do: {:ok, []},
      else: emit(%WaitlistJoined{entry_id: id, course_id: course, student_id: student})
  end

  @impl true
  def leave_waitlist(%LeaveWaitlist{entry_id: id}, %State{left: false}),
    do: emit(%WaitlistLeft{entry_id: id})

  def leave_waitlist(_command, _state), do: reject(:still_waiting)

  @impl true
  def evolve(state, %WaitlistLeft{}), do: %{state | left: true}
  def evolve(state, _joined), do: state
end
