defmodule EhOsContract.DispatchDcbCommitsTest do
  @moduledoc """
  A boundary under real concurrency (plan EM1): **ten registrars subscribing ten
  students to a course of three seats at once never seat a fourth.**

  The sandbox cannot show it: its one connection serialises every dispatch, so no
  two decisions ever read the same boundary. This runs on `EhOsContract.CommitRepo`,
  with `:repo` pointed at it for the test, under a course of its own, since rows of
  the log written here stay for the rest of the run.
  """

  use ExUnit.Case, async: false

  import Ecto.Query

  alias BoundaryRig.Courses.Commands.DefineCourse
  alias BoundaryRig.Enrolment.Commands.Subscribe
  alias EhOsContract.CommitRepo, as: Repo
  alias EhOsContract.{Actor, Event, Rejection}

  setup do
    previous = Application.fetch_env!(:eh_os_contract, :repo)
    Application.put_env(:eh_os_contract, :repo, Repo)
    on_exit(fn -> Application.put_env(:eh_os_contract, :repo, previous) end)
    %{course: "course-commits-#{System.unique_integer([:positive])}"}
  end

  defp registrar,
    do: Actor.credential("u-registrar", ["boundary_rig.define_course", "boundary_rig.subscribe"])

  # Dispatch retries a conflict three times; a registrar whose three all met one
  # sends the command again, as a host would — a bounded number of times, so that a
  # conflict that never settles fails here rather than as a timeout.
  defp subscribe_until_settled(course, student, sends \\ 20)

  defp subscribe_until_settled(course, student, 0),
    do: flunk("#{student}'s subscription to #{course} kept conflicting")

  defp subscribe_until_settled(course, student, sends) do
    case EhOsContract.dispatch(
           BoundaryRig.Enrolment,
           %Subscribe{course_id: course, student_id: student},
           actor: registrar()
         ) do
      {:error, :conflict} -> subscribe_until_settled(course, student, sends - 1)
      settled -> settled
    end
  end

  test "ten concurrent subscriptions to three seats: three accepted, seven refused", %{
    course: course
  } do
    {:ok, _} =
      EhOsContract.dispatch(
        BoundaryRig.Courses,
        %DefineCourse{course_id: course, capacity: 3},
        actor: registrar()
      )

    results =
      1..10
      |> Enum.map(fn n ->
        Task.async(fn -> subscribe_until_settled(course, "student-#{n}") end)
      end)
      |> Enum.map(&Task.await(&1, 60_000))

    accepted = Enum.count(results, &match?({:ok, _}, &1))
    refused = Enum.count(results, &match?({:error, %Rejection{invariant: :a_seat_is_free}}, &1))
    assert {accepted, refused} == {3, 7}

    seated =
      Repo.aggregate(
        from(e in Event,
          where: e.type == "enrolment.student_subscribed",
          where: fragment("? @> ?::text[]", e.tags, ^["course_id:#{course}"])
        ),
        :count
      )

    assert seated == 3
  end
end
