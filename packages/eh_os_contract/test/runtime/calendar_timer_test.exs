defmodule EhOsContract.CalendarTimerTest do
  @moduledoc """
  A timer that waits by the calendar (plan EM3, the user's choice of 27 September
  2026), on the invented `BoundaryRig`: a course defined on 31 January is reviewed
  on the last day of February, a month later as a person counts it, not thirty days
  later.
  """

  use EhOsContract.DataCase, async: false

  alias BoundaryRig.Courses.Commands.DefineCourse
  alias EhOsContract.{Actor, Clock, ProcessManagerRecord, Testing}

  @review "boundary_rig.enrolment:process_manager:course_review"

  defp define_at(at, course) do
    Clock.at(at, fn ->
      {:ok, _} =
        EhOsContract.dispatch(BoundaryRig.Courses, %DefineCourse{course_id: course, capacity: 2},
          actor: Actor.credential("u-registrar", ["boundary_rig.define_course"])
        )

      Testing.drain()
    end)
  end

  defp review_at(course),
    do:
      Repo.get_by!(ProcessManagerRecord, name: @review, correlation: course).timers["review"][
        "at"
      ]

  test "a month after 31 January is the last day of February" do
    define_at(~U[2026-01-31 09:00:00Z], "course-january")
    assert review_at("course-january") == "2026-02-28T09:00:00.000000Z"
  end

  test "a month after the 15th is the 15th" do
    define_at(~U[2026-03-15 09:00:00Z], "course-march")
    assert review_at("course-march") == "2026-04-15T09:00:00.000000Z"
  end
end
