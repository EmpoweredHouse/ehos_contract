defmodule BoundaryRig.AcademicCalendar do
  @moduledoc "**Invented.** The decider of `BoundaryRig.Calendar`'s calendar."

  use BoundaryRig.Calendar, aggregate: :calendar

  @impl true
  def close_enrolment(%CloseEnrolment{calendar_id: id}, _state),
    do: emit(%EnrolmentClosed{calendar_id: id})
end
