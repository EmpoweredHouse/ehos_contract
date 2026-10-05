defmodule EhOsContract.SchemaVersionTest do
  @moduledoc """
  Plan W1: a row of the log says which version of its event's fields it was written
  with, and a reader running code that declares an older version refuses it rather
  than misread it. On the invented `LifecycleRig.Visits`, whose `:note_added` is at
  version 2.
  """

  use EhOsContract.DataCase, async: false

  alias EhOsContract.{Actor, Consumer, Event}
  alias LifecycleRig.Visits
  alias LifecycleRig.Visits.Commands.{AddNote, BookVisit}
  alias LifecycleRig.Visits.Events.NoteAdded

  @visit "visit-1"

  defp reception,
    do: Actor.credential("u-reception", ~w(lifecycle_rig.book_visit lifecycle_rig.add_note))

  defp issue(module),
    do: EhOsContract.dispatch(Visits, struct(module, visit_id: @visit), actor: reception())

  defp log,
    do: Repo.all(from(e in Event, where: e.stream_id == ^"visit:#{@visit}", order_by: e.position))

  test "each row carries the schema version its event declares" do
    assert {:ok, _} = issue(BookVisit)
    assert {:ok, _} = issue(AddNote)

    assert [{"visit.booked", 1}, {"visit.note_added", 2}] =
             Enum.map(log(), &{&1.type, &1.schema_version})
  end

  test "a row written with a newer version than the code declares is refused; control: its own" do
    assert {:ok, _} = issue(BookVisit)
    assert {:ok, _} = issue(AddNote)
    [_booked, note] = log()

    assert %NoteAdded{visit_id: @visit} = Consumer.decode!(note)

    message =
      assert_raise ArgumentError, fn -> Consumer.decode!(%{note | schema_version: 3}) end

    assert message.message ==
             "LifecycleRig.Visits holds \"visit.note_added\" at position #{note.position} " <>
               "written with schema version 3, newer than the 2 this code declares: the code " <>
               "reading it is older than the code that wrote it"
  end
end
