defmodule EhOsContract.DispatchLifecycleTest do
  @moduledoc """
  Plan LC2 (#99): dispatch computes an aggregate's status from its stream, refuses a
  command outside its `from:` on its `or_rejects:` before the decision, and treats an
  event the graph does not allow as a defect; a recorded event that does not fit is
  appended and moves nothing. On the invented `LifecycleRig.Visits`.
  """

  use EhOsContract.DataCase, async: false

  alias EhOsContract.{Actor, CommandRecord, Event, Rejection}
  alias LifecycleRig.Visits
  alias LifecycleRig.Visits.Commands.{AddNote, AdmitPatient, BookVisit, CancelVisit, CloseVisit}
  alias LifecycleRig.Visits.Commands.ReopenVisit
  alias LifecycleRig.Visits.Events.PatientArrived

  @visit "visit-1"

  defp reception,
    do:
      Actor.credential(
        "u-reception",
        Enum.map(
          ~w(book_visit admit_patient cancel_visit close_visit add_note reopen_visit),
          &"lifecycle_rig.#{&1}"
        )
      )

  defp issue(module),
    do: EhOsContract.dispatch(Visits, struct(module, visit_id: @visit), actor: reception())

  defp log,
    do:
      Repo.all(
        from(e in Event,
          where: e.stream_id == ^"visit:#{@visit}",
          order_by: e.position,
          select: e.type
        )
      )

  test "a command outside its from: is refused on its or_rejects:, before the decision" do
    assert {:ok, _} = issue(BookVisit)
    assert {:ok, _} = issue(AdmitPatient)

    assert {:error, %Rejection{invariant: :only_a_booked_visit}} = issue(AdmitPatient)
    assert {:error, %Rejection{invariant: :only_a_booked_visit}} = issue(CancelVisit)

    assert log() == ["visit.visit_booked", "visit.patient_arrived"]

    # Recorded as the decision's own refusal would be, with what the stream held.
    assert [
             %{invariant: "only_a_booked_visit", given_types: given},
             %{invariant: "only_a_booked_visit"}
           ] =
             Repo.all(
               from(c in CommandRecord, where: c.outcome == "rejected", order_by: c.recorded_at)
             )

    assert given == ["visit.visit_booked", "visit.patient_arrived"]
  end

  test "a command in its from: reaches the decision, whose state holds the status as it stood" do
    assert {:ok, _} = issue(BookVisit)
    assert {:error, %Rejection{invariant: :only_an_open_visit}} = issue(CloseVisit)

    assert {:ok, _} = issue(AddNote)
    assert {:ok, _} = issue(AdmitPatient)
    assert {:ok, _} = issue(AddNote)
    assert {:ok, %{events: [closed]}} = issue(CloseVisit)

    # `evolve/2` counted the note taken while booked, and not the one after arrival.
    assert closed.notes_before_arrival == 1
  end

  test "an event the graph does not allow is a defect, and nothing is appended" do
    assert {:ok, _} = issue(BookVisit)
    assert {:ok, _} = issue(AdmitPatient)

    assert_raise ArgumentError,
                 ~r/command :reopen_visit decided :patient_arrived in status :in_progress, which no transition leaves with it\. Nothing was appended\./,
                 fn -> issue(ReopenVisit) end

    assert {:ok, _} = issue(CloseVisit)

    assert_raise ArgumentError,
                 ~r/command :add_note decided :note_added in status :closed, which is terminal/,
                 fn -> issue(AddNote) end

    assert log() == ["visit.visit_booked", "visit.patient_arrived", "visit.visit_closed"]
  end

  test "a command before the visit exists may only start it" do
    assert_raise ArgumentError,
                 ~r/command :reopen_visit decided :patient_arrived before the aggregate has a status/,
                 fn -> issue(ReopenVisit) end

    assert log() == []
  end

  test "a recorded event that does not fit is appended, and moves nothing" do
    assert {:ok, _} = issue(BookVisit)
    assert {:ok, _} = issue(CancelVisit)

    # The kiosk saw the patient check in, for a visit already cancelled.
    assert {:ok, _} =
             EhOsContract.record(Visits, %PatientArrived{visit_id: @visit},
               actor: Actor.system(:front_desk)
             )

    assert log() == ["visit.visit_booked", "visit.visit_cancelled", "visit.patient_arrived"]

    # Still cancelled: closing is refused as for any visit not in progress.
    assert {:error, %Rejection{invariant: :only_an_open_visit}} = issue(CloseVisit)
  end

  test "the callback's @doc says where it is issued, and what it is refused on elsewhere" do
    {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(LifecycleRig.Visits.Aggregates.Visit)
    doc = for {{:callback, :admit_patient, 2}, _, _, %{"en" => doc}, _} <- docs, do: doc

    assert [admit] = doc

    assert admit =~
             "Issued only in status `booked`: in any other the engine refuses it on " <>
               "`only_a_booked_visit` before this callback runs"
  end
end
