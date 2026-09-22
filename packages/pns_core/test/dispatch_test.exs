defmodule PNS.DispatchTest do
  @moduledoc """
  Dispatch split along the transaction boundary (ADR §9-10, notes §4).

  This is a claim prose cannot settle: either the failure semantics are as
  recorded, or they are not.

  Written against a client tree until 2026-08-21, where "the handler's own writes
  landed in the same transaction" was checked by counting rows in the client's
  tables. The invented fixtures own no tables, so the same claim is checked on the
  rows the engine itself writes inside that transaction — the events and their
  handling records. That is not a weaker statement about the boundary: it is the
  same boundary, observed through the only rows a library can promise.
  """

  use PNS.DataCase, async: false
  use Oban.Testing, repo: PNS.TestRepo

  alias ProcessShapes.Promised
  alias ProcessShapes.Rig

  test "emit writes the event, runs the sync handler and queues the async one — one transaction" do
    {:ok, _} = PNS.emit(Rig, :item_received, %{case_id: "c-1", item_no: 1, amount: 100})

    # The synchronous handler added its own rows in the same transaction, and its
    # publication pulled in a further synchronous handler.
    assert [_] = events_of(:item_received)
    assert [_] = events_of(:item_paired)
    assert [closed] = events_of(:case_closed)

    assert closed.payload["paired"] == 1

    # One handling row per handler that ran, all of them committed by the same
    # transaction that committed the events.
    handlers =
      Repo.all(from(h in PNS.EventHandling, select: h.handler)) |> Enum.sort()

    assert handlers == [
             "ProcessShapes.Intake.OnItemReceived",
             "ProcessShapes.Matching.OnItemPaired"
           ]
  end

  test "the causation chain and the correlation run through every event" do
    {:ok, root} = PNS.emit(Rig, :item_received, %{case_id: "c-1", item_no: 1, amount: 100})

    [paired] = events_of(:item_paired)
    [closed] = events_of(:case_closed)

    assert paired.correlation_id == root.correlation_id
    assert closed.correlation_id == root.correlation_id
    assert paired.causation_id == root.id
    # The cause of the case closing is the item being paired, not the item
    # arriving. Without this the observed graph would be flat.
    assert closed.causation_id == paired.id
  end

  test "a synchronous handler that raises rolls everything back — no event, no job" do
    # A declared event whose handler is built to raise, and does so on a positive
    # item number. The control is the same handler not raising, which
    # `handler_failure_test` uses — without it this could pass against a mechanism
    # that rolled back every emission.
    assert_raise RuntimeError, ~r/review desk is unreachable/, fn ->
      PNS.emit(Rig, :item_flagged, %{case_id: "c-1", item_no: 1})
    end

    assert events_of(:item_flagged) == []
    assert events_of(:pairing_unresolved) == []
    assert Repo.aggregate(PNS.EventHandling, :count) == 0
    assert all_enqueued() == []
  end

  test "the asynchronous handler gets a job inserted in the same transaction" do
    {:ok, event} = PNS.emit(Promised, :request_refused, %{request_id: "r-1"})

    assert [job] = all_enqueued(worker: PNS.Job)
    assert job.args["handler"] == "ProcessShapes.Promised.OnRequestRefused"
    # Correlation serialised into the arguments — without it the chain breaks at
    # the BEAM process boundary (notes §3).
    assert job.args["correlation_id"] == event.correlation_id
    assert job.args["causation_id"] == event.id

    # The synchronous handlers did not fire: this is not their event.
    assert Repo.aggregate(PNS.EventHandling, :count) == 0
  end

  test "the retain policy applies to the job arguments too, not only to the log" do
    note = "the inspector's own words about this item"

    {:ok, event} = PNS.emit(Rig, :item_reported, %{case_id: "c-1", item_no: 1, note: note})

    assert [job] = all_enqueued(worker: PNS.Job)

    assert String.starts_with?(event.payload["note"], "sha256:")
    # This is the thing that only came out in code: if the handler received the
    # full value, it would leak through `oban_jobs` — a table `retain` does not
    # cover. A policy the queue walks around looks satisfied.
    assert String.starts_with?(job.args["payload"]["note"], "sha256:")
    refute job.args["payload"]["note"] == note
  end

  describe "the system actor — fixed 21 August 2026" do
    test "no ctx.actor supplied — the event and the queued job both get the explicit system actor, not nil" do
      {:ok, event} = PNS.emit(Rig, :item_reported, %{case_id: "c-1", item_no: 1, note: "n"})

      assert event.actor == "system"
      assert [job] = all_enqueued(worker: PNS.Job)
      assert job.args["actor"] == "system"
    end

    test "an explicit ctx.actor is never overridden by the default" do
      {:ok, event} =
        PNS.emit(Rig, :item_reported, %{case_id: "c-1", item_no: 1, note: "n"}, %{actor: "alice"})

      assert event.actor == "alice"
      assert [job] = all_enqueued(worker: PNS.Job)
      assert job.args["actor"] == "alice"
    end

    test "emit_all defaults the actor the same way emit does" do
      # A different entry point, and the same default_ctx/1 helper behind it —
      # pinned separately so a future change to one path cannot silently stop
      # covering the other.
      {:ok, [event]} =
        PNS.emit_all(Promised, [
          %PNS.Emission{name: :request_received, payload: %{request_id: "r-2"}}
        ])

      assert event.actor == "system"
    end
  end

  test "an asynchronous handler run twice does nothing the second time" do
    {:ok, _} = PNS.emit(Promised, :request_refused, %{request_id: "r-1"})

    [job] = all_enqueued(worker: PNS.Job)

    assert :ok = perform_job(PNS.Job, job.args)
    # The effect of this handler **is** its publication, so counting the published
    # event is counting the effect rather than standing in for it.
    assert [_] = events_of(:refusal_notified)

    assert :ok = perform_job(PNS.Job, job.args)
    assert [_] = events_of(:refusal_notified)
  end

  test "publishing an event outside the contract is rejected at run time" do
    assert_raise ArgumentError, ~r/does not declare event/, fn ->
      PNS.emit(Rig, :no_such_event, %{})
    end
  end
end
