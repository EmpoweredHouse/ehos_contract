defmodule EhOsContract.GeneratedIdentityTest do
  @moduledoc """
  An aggregate whose identity the library gives (plan EM3, the user's choice of 27
  September 2026), on the invented `BoundaryRig.Waitlist`: the command that creates
  an entry arrives without an identity and gets a UUIDv7, returned in the receipt;
  every other command names the entry as usual.
  """

  use EhOsContract.DataCase, async: false

  alias BoundaryRig.Waitlist
  alias BoundaryRig.Waitlist.Commands.{JoinWaitlist, LeaveWaitlist}
  alias EhOsContract.{Actor, Event, Receipt, Rejection}

  defp registrar,
    do:
      Actor.credential("u-registrar", [
        "boundary_rig.join_waitlist",
        "boundary_rig.leave_waitlist"
      ])

  # A creating command needs an idempotency key; each call gets its own unless the
  # test names one.
  defp join(opts \\ []),
    do:
      EhOsContract.dispatch(
        Waitlist,
        %JoinWaitlist{course_id: "course-math", student_id: "student-anna"},
        Keyword.merge(
          [actor: registrar(), idempotency_key: "join-#{System.unique_integer([:positive])}"],
          opts
        )
      )

  defp log,
    do: Repo.all(from(e in Event, where: like(e.type, "waitlist.%"), order_by: e.position))

  test "the creating command gets a UUIDv7, in its events and in the receipt" do
    assert {:ok, %Receipt{identity: %{entry_id: id}, events: [joined]}} = join()

    assert {:ok, <<_::binary-size(16)>>} = Ecto.UUID.dump(id)
    assert String.at(id, 14) == "7", "a UUIDv7 carries its version in the 13th hex digit"
    assert joined.entry_id == id

    assert [%{stream_id: stream, stream_version: 1, payload: %{"entry_id" => ^id}}] = log()
    assert stream == "entry:#{id}"
  end

  test "every other command names the entry it went to, and decides over its stream" do
    {:ok, %Receipt{identity: %{entry_id: id}}} = join()

    assert {:ok, %Receipt{identity: %{entry_id: ^id}}} =
             EhOsContract.dispatch(Waitlist, %LeaveWaitlist{entry_id: id}, actor: registrar())

    assert {:error, %Rejection{invariant: :still_waiting}} =
             EhOsContract.dispatch(Waitlist, %LeaveWaitlist{entry_id: id}, actor: registrar())
  end

  test "a creating command without an idempotency key is refused, and nothing is written" do
    # A retry of it would make a second entry the caller never hears of.
    assert {:error, :idempotency_key_required} = join(idempotency_key: nil)
    assert log() == []
  end

  test "a creating command that brings its own identity is refused, and nothing is written" do
    assert {:error, {:invalid, [entry_id: :generated]}} =
             EhOsContract.dispatch(
               Waitlist,
               %JoinWaitlist{entry_id: "entry-made-up", course_id: "c", student_id: "s"},
               actor: registrar(),
               idempotency_key: "join-made-up"
             )

    assert log() == []
  end

  test "control: a command that does not create still needs the identity" do
    assert {:error, {:invalid, [entry_id: :required]}} =
             EhOsContract.dispatch(Waitlist, %LeaveWaitlist{entry_id: nil}, actor: registrar())
  end

  test "a duplicate of a creating command that decided nothing names no identity" do
    # The first receipt names the identity the command was given; nothing was
    # appended under it. The retry generates another, which names nothing either.
    Process.put(:boundary_rig_join_decides_nothing, true)

    {:ok, %Receipt{identity: %{entry_id: _}, duplicate: false}} =
      join(idempotency_key: "join-none")

    {:ok, %Receipt{identity: again, duplicate: true}} = join(idempotency_key: "join-none")

    assert again == %{}
    assert log() == []
  end

  test "the same idempotency key gives the same identity, and one entry" do
    {:ok, %Receipt{identity: first, duplicate: false}} = join(idempotency_key: "join-anna")
    {:ok, %Receipt{identity: again, duplicate: true}} = join(idempotency_key: "join-anna")

    assert again == first
    assert length(log()) == 1
  end
end
