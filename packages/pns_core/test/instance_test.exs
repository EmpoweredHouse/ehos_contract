defmodule PNS.InstanceTest do
  @moduledoc """
  The acceptance criterion of stage 1.1: **an assertion counted over two parallel
  runs does not confuse their events.**

  This file is written to show the difference rather than only to check a new
  counter. Wherever it makes sense, the per-run result stands next to the per-event-type
  one — that is, next to what the engine counted before this stage. Without that
  comparison "the counter says 1" is a number with no meaning.

  Two parallel runs used to be two companies opening the same accounting month,
  one of which failed its registry check. Since 2026-08-21 they are two cases in
  the rig, one of which has an item worth pairing and one of which does not. The
  divergence is the same shape — both runs start with the same event and only one
  of them reaches the end — and it no longer needs a client tree to produce it.
  """

  use PNS.DataCase, async: false

  alias ProcessShapes.Bare
  alias ProcessShapes.Rig

  defp receive_item(case_id, item_no, amount) do
    PNS.emit!(Rig, :item_received, %{case_id: case_id, item_no: item_no, amount: amount})
  end

  describe "run identity in the log" do
    test "the run key comes from `instance:` and is written on the event" do
      receive_item("c-1", 1, 100)

      event = List.first(events_of(:item_received))

      assert event.process == "pairing"
      assert event.instance_id == "pairing|c-1"
    end

    test "every event of one command lands in one run" do
      receive_item("c-1", 1, 100)

      instances = Repo.all(from(e in PNS.Event, select: e.instance_id)) |> Enum.uniq()

      assert instances == ["pairing|c-1"]
    end

    test "two runs of the same process are two runs, not one" do
      # `correlation_id` would answer the same way here, because these are two
      # separate arrivals. But one arrival opening two runs would also give two,
      # and one run touched by two arrivals would give one. These are different
      # questions.
      for case_id <- ["c-1", "c-2"], do: receive_item(case_id, 1, 100)

      instances =
        Repo.all(from(e in PNS.Event, select: e.instance_id)) |> Enum.uniq() |> Enum.sort()

      assert instances == ["pairing|c-1", "pairing|c-2"]
    end

    test "a run keyed by two fields varies in either of them" do
      # The shape an accounting month had and the rig does not: one run is one
      # tenant's one batch, so changing the tenant and changing the batch both
      # produce a different run. A key built from the first field only would read
      # these three as two.
      for {tenant, batch} <- [{"t-1", "b-1"}, {"t-1", "b-2"}, {"t-2", "b-1"}] do
        PNS.emit!(Bare, :batch_opened, %{tenant_id: tenant, batch_id: batch})
      end

      instances =
        Repo.all(from(e in PNS.Event, where: e.process == "batching", select: e.instance_id))
        |> Enum.uniq()
        |> Enum.sort()

      assert instances == ["batching|t-1|b-1", "batching|t-1|b-2", "batching|t-2|b-1"]
    end

    test "an event missing an instance field does not enter the log" do
      # Still refused, and since stage 2.2b **by a different check**. Payload validation
      # runs before the run key is computed and rejects any declared field that is
      # missing, so it reaches this case first. The consequence for the log is the one
      # that matters and is unchanged: the event does not land with an empty key segment
      # and merge with another run.
      assert_raise ArgumentError, ~r/`tenant_id` is declared and missing/, fn ->
        PNS.emit(Bare, :batch_opened, %{batch_id: "b-1"})
      end

      assert events_of(:batch_opened) == []
    end

    test "the run key still guards a direct caller, where nothing validated first" do
      # `PNS.Instance.key/3` is public, so it can be reached without going through the
      # emitter — and there its own check is the only thing standing between a missing
      # field and a key with a hole in it. Unreachable from `emit` is not the same as
      # dead, and the difference is worth a test rather than a comment.
      assert_raise ArgumentError, ~r/does not carry instance field :tenant_id/, fn ->
        PNS.Instance.key(Bare, :batch_opened, %{batch_id: "b-1"})
      end
    end
  end

  describe "two parallel runs" do
    setup do
      # c-1 has an item worth pairing, c-2 does not. Both runs start with the same
      # event, so per event type they are indistinguishable.
      receive_item("c-1", 1, 100)
      receive_item("c-2", 1, 0)

      :ok
    end

    test "\"after X, eventually Y\" is true for one run rather than for both" do
      # This is the whole reason stage 1.1 comes before assertion evaluation. Both
      # runs received an item; only one of them paired it and closed.
      c1 = PNS.Graph.observed(instance: "pairing|c-1").nodes
      c2 = PNS.Graph.observed(instance: "pairing|c-2").nodes

      assert Map.has_key?(c1, "item_received")
      assert Map.has_key?(c2, "item_received")

      assert Map.has_key?(c1, "case_closed")
      refute Map.has_key?(c2, "case_closed")

      # And this is the same statement counted per event type, that is, the way the
      # engine counted before this stage: "`case_closed` happened after
      # `item_received`" is **true globally** and would credit run c-2, which never
      # closed.
      globally = PNS.Graph.observed().nodes
      assert globally["item_received"].count == 2
      assert globally["case_closed"].count == 1
    end

    test "an edge counter has two dimensions: occurrences and runs" do
      overlay = PNS.Graph.overlay()
      edge = Enum.find(overlay, &(&1.to == :case_closed))

      # The edge is `confirmed`, because somebody traversed it. And that is exactly
      # the hidden silence: **one of two** runs traversed it.
      assert edge.state == :confirmed
      assert edge.count == 1
      assert edge.instances == 1
      assert edge.of_instances == 2
    end

    test "an event repeated within one run raises occurrences, not runs" do
      # Occurrences go up, runs do not. The version without that distinction read
      # one run repeating an operation as coverage of the whole population.
      #
      # `item_measured` rather than an event that cascades: its two handlers publish
      # nothing, so repeating it adds an occurrence and disturbs no edge.
      for item_no <- 1..2 do
        PNS.emit!(Rig, :item_measured, %{case_id: "c-1", item_no: item_no})
      end

      node = PNS.Graph.observed().nodes["item_measured"]

      assert node.count == 2
      assert node.instances == 1

      assert PNS.Graph.observed().nodes["item_received"].instances == 2
    end

    test "the number of runs of a process is a count, not a list of cases" do
      # Deliberately. "Which case has nothing open" is a question for the client
      # application; PNS answers the question about the path.
      assert PNS.Graph.process_instances() == %{"pairing" => 2}
    end
  end
end
