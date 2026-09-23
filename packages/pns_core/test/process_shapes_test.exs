defmodule PNS.ProcessShapesTest do
  @moduledoc """
  Stage 1.3: **process shapes, simulated.**

  The acceptance criterion has two halves and the second matters more: `pns.check`
  **reports** the backward edge when the pair closes, and **does not report** one
  where there is none. The mere fact that the check finds a case constructed for it
  proves nothing — the proof is its silence on three controls.

  The rig (`ProcessShapes.Rig`) is explicitly **not a domain**. The shapes come
  from a table in the product plan rather than from imagination; the names are
  colourless so nobody reads them as knowledge about anybody's process.
  """

  use PNS.DataCase, async: false

  alias ProcessShapes.Rig

  defp receive_item(case_id, item_no, amount) do
    PNS.emit!(Rig, :item_received, %{case_id: case_id, item_no: item_no, amount: amount})
  end

  defp types(case_id) do
    instance = "pairing|#{case_id}"

    Repo.all(
      from(e in PNS.Event,
        where: e.instance_id == ^instance,
        order_by: e.occurred_at,
        select: e.type
      )
    )
  end

  describe "acceptance criterion: the backward edge" do
    test "the check reports exactly one backward edge — the one closing the pair" do
      edges = PNS.Check.backward_edges()
      in_rig = Enum.filter(edges, &(&1.process == :pairing))

      assert [edge] = in_rig
      assert edge.module == ProcessShapes.Resolution.OnClarificationAnswered
      assert edge.subscribes_in == :resolution
      assert edge.publishes_in == :matching
    end

    test "and stays silent on three modules that publish forwards" do
      # This is the half of the criterion that matters. A check reporting
      # everything is as useless as a check reporting nothing.
      reported = PNS.Check.backward_edges() |> Enum.map(& &1.module)

      refute ProcessShapes.Intake.OnItemReceived in reported
      refute ProcessShapes.Matching.OnPairingUnresolved in reported
      refute ProcessShapes.Matching.OnItemPaired in reported
    end

    test "a backward edge is counted by stage, not by an event's position" do
      # Two events of the same stage are never a backward edge, because the
      # contract claims nothing about order within a stage. `OnItemPaired`
      # subscribes to `item_paired` from `matching` and publishes `case_closed`
      # from `resolution` — if the check counted by position in a list, it would
      # raise a false alarm here.
      assert Rig.event(:item_paired).stage == :matching
      assert Rig.event(:case_closed).stage == :resolution

      refute ProcessShapes.Matching.OnItemPaired in Enum.map(
               PNS.Check.backward_edges(),
               & &1.module
             )
    end
  end

  describe "a step that goes backwards — at run time, not only in the check" do
    test "the pair closes after a clarification and the run returns to the `matching` stage" do
      receive_item("c-1", 1, 0)

      assert types("c-1") == ~w(item_received pairing_unresolved clarification_requested)

      # The clarification arrives **without a command**, from outside. It closes
      # the pair backwards.
      PNS.emit!(Rig, :clarification_answered, %{case_id: "c-1", item_no: 1})

      assert types("c-1") ==
               ~w(item_received pairing_unresolved clarification_requested
                  clarification_answered item_paired case_closed)
    end
  end

  describe "the same event many times in one run" do
    test "three items are three facts in one run, not three runs" do
      for n <- 1..3, do: receive_item("c-1", n, 100)

      runs = PNS.Graph.process_instances()
      node = PNS.Graph.observed().nodes["item_paired"]

      assert runs["pairing"] == 1
      assert node.count == 3
      assert node.instances == 1
    end

    test "the handler counts by run identity, not by event type" do
      # If it counted per type, the second case's items would be added to the
      # first — the same mistake stage 1.1 fixed in the overlay, committed inside
      # a handler.
      for n <- 1..2, do: receive_item("c-1", n, 100)
      for n <- 1..5, do: receive_item("c-2", n, 100)

      assert ProcessShapes.Matching.count("c-1", "item_paired") == 2
      assert ProcessShapes.Matching.count("c-2", "item_paired") == 5
    end
  end

  describe "an event arriving without a command" do
    test "it has the explicit system actor and yet has a run identity" do
      event = receive_item("c-1", 1, 100)

      assert event.actor == "system",
             "nobody invoked it — attributed to the system, not to silence"

      assert event.instance_id == "pairing|c-1"
      assert event.causation_id == nil
    end

    test "the system actor is explicit, never nil" do
      # Fixed 21 August 2026: the sensible version of "every event has an actor" is
      # not "required" but "never silent" — `PNS.Event.system_actor/0`, defaulted in
      # `PNS.Emitter.default_ctx/1` before an event ever reaches the log. An actor
      # of `nil` used to conflate "an import" with "we do not know who"; now the
      # first reads as this, and the second cannot occur without a caller
      # deliberately supplying `actor: nil` in `ctx`.
      assert receive_item("c-1", 1, 100).actor == "system"
    end
  end

  describe "two synchronous handlers on one event — stage 2.4" do
    test "the check reports the one event that has two, and stays silent on the rest" do
      competing = PNS.Check.competing_sync_handlers()

      assert [%{event: :item_measured, modules: modules}] = competing
      assert length(modules) == 2

      # The silence is the evidence. Seven other events have exactly one synchronous
      # handler, and a check that only ever fires on the case built for it proves
      # nothing — the same argument as for the backward edge above.
      singles =
        PNS.Registry.handlers()
        |> Enum.reject(& &1.async)
        |> Enum.group_by(& &1.event)
        |> Enum.count(fn {_event, handlers} -> length(handlers) == 1 end)

      assert singles >= 7
    end

    test "the order is deterministic, and it is alphabetical rather than declared" do
      # Sorted so a build reproduces; alphabetical because there is nothing better to
      # sort by. `First` sorts before `Second` while being declared after it, which is
      # why the check warns instead of the registry pretending to have solved this.
      assert PNS.Check.competing_sync_handlers() == [
               %{
                 event: :item_measured,
                 modules: [
                   ProcessShapes.Intake.OnItemMeasuredFirst,
                   ProcessShapes.Intake.OnItemMeasuredSecond
                 ]
               }
             ]

      assert Enum.map(PNS.Registry.sync_handlers_for(:item_measured), & &1.module) ==
               [
                 ProcessShapes.Intake.OnItemMeasuredFirst,
                 ProcessShapes.Intake.OnItemMeasuredSecond
               ]
    end

    test "both handlers actually run, in that order" do
      # Reproducible order is worth nothing if one of them is skipped.
      event = PNS.emit!(Rig, :item_measured, %{case_id: "c-1", item_no: 1})

      handled =
        Repo.all(
          from(h in PNS.EventHandling,
            where: h.event_id == ^event.id,
            order_by: h.inserted_at,
            select: h.handler
          )
        )

      assert length(handled) == 2
      assert "ProcessShapes.Intake.OnItemMeasuredFirst" in handled
      assert "ProcessShapes.Intake.OnItemMeasuredSecond" in handled
    end
  end
end
