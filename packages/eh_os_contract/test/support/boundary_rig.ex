defmodule BoundaryRig do
  @moduledoc """
  **An engine fixture, and invented.** Enrolment in courses with a limited number of
  seats, written to exercise a dynamic consistency boundary at run time (v2 §10.1,
  plan EM1), and nothing more: no workshop stands behind it, and no name in it comes
  from one. It is the textbook case for a boundary: whether a student gets a seat
  depends on facts of three units, none of which is the seat — the course's
  capacity, every other student's subscription to it, and the calendar closing
  enrolment for everyone.
  """

  use Boundary,
    deps: [EhOsContract],
    exports: [Calendar, Courses, Domain, Enrolment]
end
