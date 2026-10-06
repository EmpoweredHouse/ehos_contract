defmodule EhOsContract.DispatchDcbTest do
  @moduledoc """
  A command to a dynamic consistency boundary (v2 §10.1, plan EM1), on the invented
  `BoundaryRig`: the boundary decides over what it consults — a sibling contract's
  event, events of its own kind matched on part of its identity, and an event by
  prose — and appends only if none of that moved since it was read.

  `async: false`: dispatch takes the one append lock, and a sandboxed test holds it
  until the test ends.
  """

  use EhOsContract.DataCase, async: false

  alias BoundaryRig.Calendar.Commands.CloseEnrolment
  alias BoundaryRig.Courses.Commands.DefineCourse
  alias BoundaryRig.Enrolment
  alias BoundaryRig.Enrolment.Commands.Subscribe
  alias BoundaryRig.Enrolment.Events.{SeatReleased, StudentSubscribed}
  alias EhOsContract.{Actor, CommandRecord, Event, Receipt, Rejection}

  @capabilities ~w(define_course close_enrolment subscribe) |> Enum.map(&"boundary_rig.#{&1}")

  defp registrar, do: Actor.credential("u-registrar", @capabilities)

  defp define!(course, capacity) do
    {:ok, _} =
      EhOsContract.dispatch(
        BoundaryRig.Courses,
        %DefineCourse{course_id: course, capacity: capacity},
        actor: registrar()
      )
  end

  defp subscribe(course, student, opts \\ []) do
    EhOsContract.dispatch(
      Enrolment,
      %Subscribe{course_id: course, student_id: student},
      Keyword.merge([actor: registrar()], opts)
    )
  end

  defp subscriptions(course) do
    Repo.all(
      from(e in Event,
        where: e.type == "boundary_rig.enrolment.student_subscribed",
        where: fragment("? @> ?::text[]", e.tags, ^["course_id:#{course}"]),
        order_by: e.position
      )
    )
  end

  defp row(type), do: Repo.one!(from(c in CommandRecord, where: c.type == ^type, limit: 1))

  describe "an accepted command" do
    test "appends outside any stream, tagged, and records what it decided over" do
      define!("course-math", 2)

      assert {:ok, %Receipt{events: [%StudentSubscribed{student_id: "student-anna"}]}} =
               subscribe("course-math", "student-anna")

      assert [event] = subscriptions("course-math")
      assert event.stream_id == nil and event.stream_version == nil
      assert event.tags == ["course_id:course-math", "student_id:student-anna"]
      assert event.process == "enrolment"

      # The sibling's event is among what the decision read.
      assert row("subscribe").given_types == ["boundary_rig.courses.course_defined"]
    end

    test "a later student reads the earlier ones' subscriptions to the same course" do
      define!("course-art", 2)
      assert {:ok, _} = subscribe("course-art", "student-anna")
      assert {:ok, _} = subscribe("course-art", "student-ben")

      assert {:error, %Rejection{invariant: :a_seat_is_free}} =
               subscribe("course-art", "student-cara")

      assert length(subscriptions("course-art")) == 2

      # What the refused decision read, each type once however many of it there were.
      refused = Repo.one!(from(c in CommandRecord, where: c.outcome == "rejected"))

      assert refused.given_types == [
               "boundary_rig.courses.course_defined",
               "boundary_rig.enrolment.student_subscribed"
             ]
    end

    test "control: subscriptions to another course do not count" do
      define!("course-one", 1)
      define!("course-two", 1)
      assert {:ok, _} = subscribe("course-one", "student-anna")
      assert {:ok, _} = subscribe("course-two", "student-ben")
    end
  end

  describe "a refusal" do
    test "a course nobody defined has no seat, and nothing is appended" do
      assert {:error, %Rejection{invariant: :a_seat_is_free}} =
               subscribe("course-ghost", "student-anna")

      assert subscriptions("course-ghost") == []
      assert row("subscribe").outcome == "rejected"
    end

    test "an event consulted by prose is read whatever it names" do
      define!("course-bio", 5)

      {:ok, _} =
        EhOsContract.dispatch(
          BoundaryRig.Calendar,
          %CloseEnrolment{calendar_id: "calendar-2026"},
          actor: registrar()
        )

      assert {:error, %Rejection{invariant: :enrolment_is_open}} =
               subscribe("course-bio", "student-anna")
    end
  end

  describe "a recorded event" do
    test "is appended under the boundary's condition, and the boundary folds it" do
      define!("course-chem", 1)
      assert {:ok, _} = subscribe("course-chem", "student-anna")

      assert {:ok, %Receipt{}} =
               EhOsContract.record(
                 Enrolment,
                 %SeatReleased{course_id: "course-chem", student_id: "student-anna"},
                 actor: Actor.system(:timetable)
               )

      released =
        Repo.one!(from(e in Event, where: e.type == "boundary_rig.enrolment.seat_released"))

      assert released.stream_id == nil

      assert {:ok, _} = subscribe("course-chem", "student-ben")
    end
  end

  describe "a conflict" do
    test "a subscription appended after the read is retried over, and the retry sees it" do
      define!("course-race", 1)
      Process.put(:boundary_rig_race, "student-x")

      # The race's subscription rolled back with the attempt that met it; the retry
      # read a free seat again and took it.
      assert {:ok, %Receipt{events: [%StudentSubscribed{student_id: "student-anna"}]}} =
               subscribe("course-race", "student-anna")

      assert [%{payload: %{"student_id" => "student-anna"}}] = subscriptions("course-race")
    end

    test "inside a caller's transaction it is returned, not retried" do
      define!("course-held", 1)
      Process.put(:boundary_rig_race, "student-x")

      assert {:ok, {:error, :conflict}} =
               Repo.transaction(fn -> subscribe("course-held", "student-anna") end)
    end
  end
end
