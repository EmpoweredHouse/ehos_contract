defmodule BoundaryRig.Enrolment do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  One student's seat on one course, decided over the course's capacity, every
  subscription to that course, the seats the timetable released, and whether the
  calendar has closed enrolment. The last is consulted by prose: it names no
  course, so every one of those events is read. How many seats are free is a
  domain service's, which the decision calls.
  """

  use EhOsContract.Next.Contract, domain: BoundaryRig.Domain, context: :enrolment

  consumes BoundaryRig.Courses, :course_defined
  consumes BoundaryRig.Calendar, :enrolment_closed

  dcb :seat, "Seat on a course" do
    identity [:course_id, :student_id]

    consults :course_defined, match: :course_id
    consults :student_subscribed, match: :course_id
    consults :seat_released, match: :course_id
    consults :enrolment_closed, where: "enrolment closed for every course"

    state do
      field :capacity, :integer, optional: true
      field :taken, :integer, default: 0
      field :closed, :boolean, default: false
    end

    invariant :a_seat_is_free, "A course never has more students than seats"
    invariant :enrolment_is_open, "Nobody subscribes once enrolment is closed"

    command :subscribe, "Subscribe a student",
      by: :registrar,
      emits: :student_subscribed,
      rejects: [:a_seat_is_free, :enrolment_is_open]

    event :student_subscribed, "Student subscribed"
    event :seat_released, "Seat released", recorded_by: :timetable
  end

  # Logic no unit owns, which the seat's decision calls (plan EM2).
  domain_service :seating, "Seating" do
    function :free_seats, "Seats still free on a course" do
      argument(:capacity, :integer)
      argument(:taken, :integer)
      returns :integer
      rule :never_below_zero, "A course never has fewer than no free seats"
    end

    function :next_seat, "The number of the next free seat, if there is one" do
      argument :capacity, :integer
      argument :taken, :integer
      returns(:integer, optional: true)
    end
  end

  process :enrolment, "Enrolment" do
    correlate :course_id
  end

  scenario "a seat is free: the student is subscribed" do
    given :course_defined, %{capacity: 2}
    given :student_subscribed, %{student_id: "student-anna"}
    command :subscribe, %{student_id: "student-ben"}
    expect :student_subscribed
  end

  scenario "every seat is taken: refused" do
    given :course_defined, %{capacity: 1}
    given :student_subscribed, %{student_id: "student-anna"}
    command :subscribe, %{student_id: "student-ben"}
    rejected :a_seat_is_free
  end

  scenario "a released seat can be taken again" do
    given :course_defined, %{capacity: 1}
    given :student_subscribed, %{student_id: "student-anna"}
    given :seat_released, %{student_id: "student-anna"}
    command :subscribe, %{student_id: "student-ben"}
    expect :student_subscribed
  end

  scenario "enrolment is closed: refused, though a seat is free" do
    given :course_defined, %{capacity: 2}
    given :enrolment_closed, %{calendar_id: "calendar-2026"}
    command :subscribe, %{student_id: "student-ben"}
    rejected :enrolment_is_open
  end
end
