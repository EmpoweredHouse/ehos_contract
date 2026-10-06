defmodule BoundaryRig.Seat do
  @moduledoc """
  **Invented.** The decider of `BoundaryRig.Enrolment`'s seat.

  A test can make the next subscription append another student's subscription
  behind the decision's back, `Process.put(:boundary_rig_race, "student-x")`, so that
  the append meets a boundary that moved: the conflict dispatch retries.
  """

  use BoundaryRig.Enrolment, dcb: :seat

  alias BoundaryRig.Calendar.Events.EnrolmentClosed
  alias BoundaryRig.Courses.Events.CourseDefined
  alias BoundaryRig.Enrolment.DomainServices.Seating

  @impl true
  def subscribe(%Subscribe{course_id: course, student_id: student}, %State{} = state) do
    if other = Process.delete(:boundary_rig_race), do: race(course, other)

    cond do
      state.closed -> reject(:enrolment_is_open)
      state.capacity == nil -> reject(:a_seat_is_free)
      Seating.free_seats(state.capacity, state.taken) == 0 -> reject(:a_seat_is_free)
      true -> emit(%StudentSubscribed{course_id: course, student_id: student})
    end
  end

  @impl true
  def evolve(state, %CourseDefined{capacity: capacity}), do: %{state | capacity: capacity}
  def evolve(state, %StudentSubscribed{}), do: %{state | taken: state.taken + 1}
  def evolve(state, %SeatReleased{}), do: %{state | taken: state.taken - 1}
  def evolve(state, %EnrolmentClosed{}), do: %{state | closed: true}

  # Another student's subscription to the same course, appended after the head the
  # decision read.
  defp race(course, student) do
    repo = Application.fetch_env!(:eh_os_contract, :repo)

    {:ok, _} =
      EhOsContract.Store.append(
        repo,
        [
          %{
            type: "boundary_rig.enrolment.student_subscribed",
            contract: inspect(BoundaryRig.Enrolment),
            contract_version: "race",
            tags: ["course_id:#{course}", "student_id:#{student}"],
            correlation_id: Ecto.UUID.generate(),
            actor: "system:race",
            occurred_at: EhOsContract.Clock.now(),
            payload: %{"course_id" => course, "student_id" => student}
          }
        ],
        :none
      )
  end
end
