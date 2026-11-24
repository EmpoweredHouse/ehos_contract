defmodule BoundaryRig.EnrolmentRun do
  @moduledoc """
  # THIS PROCESS IS INVENTED. IT IS NOT CLIENT MATERIAL.

  A course's enrolment as one run: the seats `BoundaryRig.Enrolment` gives and
  releases, keyed by the course. Until plan DD, P2g (#228) it was `:enrolment` inside
  the contract.
  """

  use EhosContract.Process,
    id: "boundary_rig.enrolment_run",
    domain: BoundaryRig.Domain,
    label: "Enrolment"

  correlate :course_id

  stage :seating, include: [{BoundaryRig.Enrolment, [:student_subscribed, :seat_released]}]
end
