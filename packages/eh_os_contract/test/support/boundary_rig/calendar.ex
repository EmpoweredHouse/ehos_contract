defmodule BoundaryRig.Calendar do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  The academic calendar, which closes enrolment for every course at once: what
  `BoundaryRig.Enrolment`'s boundary consults by prose, since the fact names no
  course.
  """

  use EhOsContract.Contract,
    domain: BoundaryRig.Domain,
    context: :enrolment,
    id: "boundary_rig.calendar"

  aggregate :calendar, "Calendar" do
    identity :calendar_id

    command :close_enrolment, "Close enrolment", by: :registrar, emits: :enrolment_closed

    event :enrolment_closed, "Enrolment closed"
  end

  process :calendar, "Calendar" do
    correlate :calendar_id
  end
end
