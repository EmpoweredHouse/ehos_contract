defmodule EhOsContract.DeclaredShapeTest do
  @moduledoc """
  `EhOsContract.Graph.declared_to_mermaid/2`: the picture a contract draws of itself, before
  a single handler exists.

  Split out of `graph_test.exs` on 2026-08-21, when the engine's tests moved into
  the package and this block did not go with them. It is drawn from
  `Rehmed.Contracts.ClinicalVisit` and several of its assertions are **about that
  contract's modelling** rather than about the renderer: that a note is not an
  event, that entering the room is a different fact from arriving at the clinic,
  that two windows are nested on one target. Repointed at an invented fixture
  those assertions would still pass and would no longer be checking anything —
  they are exactly the review a real contract has to survive, and they belong
  where the real contract is.
  """

  use ExUnit.Case, async: true

  describe "the declared shape of one process" do
    # Drawn from `Rehmed.Contracts.ClinicalVisit` on purpose: it has **no
    # handlers**, so the handler graph of it is eleven unconnected boxes. If this
    # picture says anything at all, it says it from `stages`, `terminal` and
    # `trace` — which is the claim the function is making.
    @contract Rehmed.Contracts.ClinicalVisit

    defp shape, do: EhOsContract.Graph.declared_to_mermaid(@contract, :clinical_visit)

    test "stages are lanes, chained in the order the contract declares" do
      mermaid = shape()

      assert mermaid =~ "stage_start --> stage_departure"
      assert mermaid =~ "stage_departure --> stage_closing"
      assert mermaid =~ "stage_closing --> stage_reporting"

      # The only ordering claim a contract makes is between stages, so it is the
      # only arrow drawn between lanes — and never the other way round.
      refute mermaid =~ "stage_departure --> stage_start"
      refute mermaid =~ "stage_reporting --> stage_closing"

      # Chained pairwise rather than fully connected: the claim is that each
      # stage follows the previous one, and drawing start --> reporting as well
      # would add a second edge saying nothing new.
      refute mermaid =~ "stage_start --> stage_reporting"
    end

    test "a lane holding several events says it claims no order between them" do
      # Otherwise boxes with no arrows read as unfinished rather than as
      # deliberately unordered, and those two collect different corrections.
      assert shape() =~ ~s(subgraph stage_closing["closing \u00b7 no order claimed inside"])
    end

    test "a lane holding one event carries no such marker, because there is nothing to order" do
      mermaid = shape()

      # Two of the four lanes hold exactly one event, and that is not an accident:
      # `stages` is a total order, so saying "this one, then that one" costs a lane
      # per moment.
      assert mermaid =~ ~s(subgraph stage_start["start"])
      assert mermaid =~ ~s(subgraph stage_departure["departure"])
      refute mermaid =~ "departure \u00b7 no order"
    end

    test "a note is not an event, and neither is performing the treatment" do
      # Six of the thirteen this contract reached were edits to one document. The
      # test that removed them is not "is it stored in a field" — the codes are a
      # field — but "does anything outside this document depend on it happening".
      mermaid = shape()

      refute mermaid =~ "history_taken"
      refute mermaid =~ "previous_note_copied"
      refute mermaid =~ "reception_note_written"
      refute mermaid =~ "treatment_performed"
      refute mermaid =~ "diagnosis_coded"
    end

    test "the visit has a beginning, and it is not the same fact as arriving at the clinic" do
      # `E-40` entering the room, not `E-27` arriving at the clinic. The source
      # model keeps them apart on purpose — the waiting room is reception's
      # `R-03`, and mixing a physical-presence state with a workflow state is the
      # mistake it records the board's colour palette making.
      assert shape() =~ ~s(visit_started["Pacjent wszedł do gabinetu"])
      refute shape() =~ "pojawił się"
    end

    test "an event is drawn with the client's own words, not its atom" do
      assert shape() =~ ~s(visit_completed["Pacjent wyszedł z gabinetu"])
    end

    test "an assertion is an arrow carrying its window, and its fallback is a second arrow" do
      mermaid = shape()

      # The number on the arrow is the point: a claim with a number is the only
      # thing a process owner can correct.
      # Two windows on the same target, nested on purpose: a day to report or be
      # chased, two days as the statutory bound.
      assert mermaid =~ "visit_completed ==>|within 24 hours| p1_report_sent"
      assert mermaid =~ "visit_completed ==>|within 2 days| p1_report_sent"
      assert mermaid =~ "visit_completed -.->|or else| documentation_task_created"
      assert mermaid =~ "visit_completed -.->|or else| p1_reporting_not_required"
    end

    test "a dependency hangs off the fact that declares it, on a line with no arrowhead" do
      mermaid = shape()

      assert mermaid =~ ~s|medical_event_registry[("Krajowy rejestr|
      assert mermaid =~ "p1_report_sent -.- medical_event_registry"
      # An arrowhead would read as causation, and somebody would build on it.
      refute mermaid =~ "p1_report_sent -.-> medical_event_registry"
    end

    test "how a process can end is visible without reading anything" do
      mermaid = shape()

      assert mermaid =~ "class p1_reporting_not_required,p1_report_sent terminal"
      assert mermaid =~ "classDef terminal"
    end

    test "a process nobody declared is an error, and the message says what exists" do
      assert_raise ArgumentError, ~r/declares no process :nonesuch/, fn ->
        EhOsContract.Graph.declared_to_mermaid(@contract, :nonesuch)
      end
    end
  end
end
