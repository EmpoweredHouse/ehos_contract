defmodule BoundaryRig.CourseReview do
  @moduledoc """
  **Invented.** `BoundaryRig.Enrolment`'s process manager `:course_review`, whose
  timer only marks the month; it issues nothing, so it has no callback to define.
  """

  use BoundaryRig.Enrolment, process_manager: :course_review
end
