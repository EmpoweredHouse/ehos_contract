defmodule PNS.GraphTest do
  @moduledoc """
  Whether a graph can be built from the contract, and whether overlaying it on the
  log makes sense.

  This is the question "does this have a chance" put as a test rather than as an
  opinion. There is no dashboard and deliberately will not be one at this step —
  first check whether the difference is signal.

  The half of this file that rendered a **declared** contract moved to the root
  application on 2026-08-21 as `declared_shape_test.exs`. Its assertions are about
  a real contract's modelling — that a note is not an event, that two windows nest
  on one target — and against an invented fixture they would still pass while
  checking nothing.
  """

  use PNS.DataCase, async: false

  alias ProcessShapes.Rig

  defp receive_item(case_id, item_no \\ 1, amount \\ 100) do
    PNS.emit!(Rig, :item_received, %{case_id: case_id, item_no: item_no, amount: amount})
  end

  test "the static graph comes from the registry, that is, from the binary" do
    graph = PNS.Graph.static()

    # The registry scans the **whole binary**, and there are three contracts in it:
    # the rig, the bare process and the universality gate fixture. Counting nodes
    # without narrowing to a contract was the hidden assumption "there is only one".
    ours = Enum.filter(graph.nodes, &(&1.contract == Rig))
    assert length(ours) == length(Rig.events())

    edges = MapSet.new(graph.edges, &{&1.from, &1.to})
    assert MapSet.member?(edges, {:item_received, :item_paired})
    assert MapSet.member?(edges, {:pairing_unresolved, :clarification_requested})
    assert MapSet.member?(edges, {:item_paired, :case_closed})

    # Narrowed the same way the node count above is, and for the same reason. This
    # line used to compare a **global** list of asynchronous edges against one
    # contract's expectation, so it broke the moment a fixture in another contract
    # declared an asynchronous handler — the hidden "there is only one" again, two
    # lines below a comment about it.
    ours = Enum.map(Rig.events(), & &1.name)
    async = for e <- graph.edges, e.async, e.from in ours, do: e.from

    assert async == [:item_reopened]
  end

  test "before any run everything is dead and nothing is drift" do
    overlay = PNS.Graph.overlay()

    assert Enum.all?(overlay, &(&1.state == :dead))
    assert Enum.all?(overlay, &(&1.count == 0))
  end

  test "after a run the edges become confirmed and the untaken ones stay dead" do
    receive_item("c-1")

    overlay = PNS.Graph.overlay()
    by_edge = Map.new(overlay, &{{&1.from, &1.to}, &1})

    assert by_edge[{:item_received, :item_paired}].state == :confirmed
    assert by_edge[{:item_paired, :case_closed}].state == :confirmed

    # The unresolved path was not traversed — and that is exactly the information
    # this view exists for.
    assert by_edge[{:pairing_unresolved, :clarification_requested}].state == :dead
  end

  test "volume is a dimension separate from state" do
    for case_id <- ["c-1", "c-2", "c-3"], do: receive_item(case_id)

    overlay = PNS.Graph.overlay()
    edge = Enum.find(overlay, &(&1.to == :case_closed))

    assert edge.state == :confirmed
    assert edge.count == 3
  end

  test "the events nothing has reached are declared and never observed" do
    receive_item("c-1")

    dead = PNS.Graph.declared_never_observed() |> Enum.map(& &1.event)

    assert :item_submitted in dead
    assert :item_inspected in dead
    assert :item_flagged in dead

    refute :item_paired in dead
    refute :case_closed in dead
  end

  test "cadence is what the window is computed from — and it is declared" do
    # `:batching` is the one invented process with a cadence, which is what makes
    # it the one that can answer this. The rig has none, and a process with no
    # cadence is a separate finding recorded against the universality gate.
    [entry] = PNS.Graph.declared_never_observed() |> Enum.filter(&(&1.event == :batch_closed))

    assert entry.process == :batching
    assert entry.cadence == {1, :week}
  end

  test "an event under a different contract version is history, not drift" do
    receive_item("c-1")

    # Simulating a deploy that removed an event: a row in the log under a contract
    # version that is no longer in the binary.
    Repo.insert!(%PNS.Event{
      type: "event_from_last_month",
      contract: inspect(Rig),
      contract_version: "version_that_is_gone",
      correlation_id: Ecto.UUID.generate(),
      causation_id: List.first(events_of(:case_closed)).id,
      payload: %{},
      occurred_at: DateTime.utc_now()
    })

    overlay = PNS.Graph.overlay()
    entry = Enum.find(overlay, &(&1.to == "event_from_last_month"))

    assert entry.state == :historical,
           "without `contract_version` every deploy that removes an event produces false drift"
  end

  test "a job waiting in the queue is :in_flight, not :dead" do
    # `item_appealed` is handled synchronously and publishes `item_reopened`, whose
    # handler is asynchronous. So the job exists and has not run — exactly the
    # moment at which a dashboard without the third state would claim the path
    # never works.
    PNS.emit!(Rig, :item_appealed, %{case_id: "c-1", item_no: 1})

    edge = PNS.Graph.overlay() |> Enum.find(&(&1.from == :item_reopened))

    assert edge.to == :item_appealed
    assert edge.state == :in_flight
    assert edge.count == 0
    assert edge.in_flight == 1
  end

  test "events from one command are siblings, not a chain" do
    # Two intentions returned by one decision and emitted together: a shared
    # correlation, no cause, neither of them the reason for the other.
    PNS.emit_all(Rig, [
      PNS.event(:item_submitted, %{case_id: "c-1", item_no: 1}),
      PNS.event(:item_measured, %{case_id: "c-1", item_no: 1})
    ])

    receive_item("c-2")

    siblings = PNS.Graph.command_siblings()

    assert siblings[{"item_measured", "item_submitted"}] == 1 or
             siblings[{"item_submitted", "item_measured"}] == 1

    # And this is real causation, which must not end up among the siblings.
    refute Map.has_key?(siblings, {"item_received", "item_paired"})
  end

  test "mermaid comes out of the overlay, not out of a separate file" do
    receive_item("c-1")

    PNS.emit_all(Rig, [
      PNS.event(:item_submitted, %{case_id: "c-1", item_no: 1}),
      PNS.event(:item_measured, %{case_id: "c-1", item_no: 1})
    ])

    mermaid = PNS.Graph.overlay() |> PNS.Graph.to_mermaid()

    assert mermaid =~ "flowchart LR"
    assert mermaid =~ "item_received"
    assert mermaid =~ "classDef confirmed"
    assert mermaid =~ "case_closed[\""
    assert mermaid =~ "-.->|" and mermaid =~ "async"
    assert mermaid =~ "same command"
  end
end
