defmodule BoundaryRig.Waitlist do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  A student waiting for a seat. An entry on the list has no identity until it
  exists, so the library gives it one (plan EM3): joining creates it, leaving
  addresses it by that identity.
  """

  use EhOsContract.Contract, domain: BoundaryRig.Domain, context: :enrolment

  aggregate :entry, "Waiting-list entry" do
    identity :entry_id, generated: :uuid

    state do
      field :left, :boolean, default: false
    end

    invariant :still_waiting, "A student leaves the list once"

    command :join_waitlist, "Join the waiting list",
      by: :registrar,
      emits: :waitlist_joined,
      creates: true do
      field :course_id, :id
      field :student_id, :id
    end

    command :leave_waitlist, "Leave the waiting list",
      by: :registrar,
      emits: :waitlist_left,
      rejects: :still_waiting

    event :waitlist_joined, "Joined the waiting list" do
      field :course_id, :id
      field :student_id, :id
    end

    event :waitlist_left, "Left the waiting list", terminal: true

    # The timetable's note that the student was told where they stand.
    event :waitlist_reminded, "Reminded of their place on the list", recorded_by: :timetable
  end

  process :waitlist, "Waiting list" do
    correlate :entry_id
  end

  scenario "a student who left cannot leave again" do
    given :waitlist_joined, %{course_id: "course-math", student_id: "student-anna"}
    given :waitlist_left
    command :leave_waitlist
    rejected :still_waiting
  end
end
