defmodule EhOsContract.DeclaredShapeTest do
  @moduledoc """
  `EhOsContract.Graph.declared_to_mermaid/2`: the picture a process draws of itself.

  Drawn from `Rehmed.Contracts.StatutoryReporting`'s `:clinical_visit`, and several
  of its assertions are **about that contract's modelling** rather than about the
  renderer: that the run crosses three contexts, that it carries only what the
  report depends on, that the promise counts from the patient leaving. Repointed at
  an invented fixture those assertions would still pass and would no longer be
  checking anything — they are the review a real contract has to survive, and they
  belong where the real contract is.

  Re-derived on 28 September 2026 (v2 plan, E9a) when the v1 `ClinicalVisit` it was
  drawn from gave way to three contexts' contracts. What changed in the modelling,
  and why, is beside each test.
  """

  use ExUnit.Case, async: true

  describe "the declared shape of the clinical visit" do
    @contract Rehmed.Contracts.StatutoryReporting

    defp shape, do: EhOsContract.Graph.declared_to_mermaid(@contract, :clinical_visit)

    test "stages are lanes, chained in the order the contract declares" do
      mermaid = shape()

      assert mermaid =~ "stage_departure --> stage_closing"
      assert mermaid =~ "stage_closing --> stage_reporting"

      # The only ordering claim a contract makes is between stages, so it is the
      # only arrow drawn between lanes — and never the other way round.
      refute mermaid =~ "stage_closing --> stage_departure"
      refute mermaid =~ "stage_reporting --> stage_closing"

      # Chained pairwise rather than fully connected.
      refute mermaid =~ "stage_departure --> stage_reporting"
    end

    test "the run crosses three contexts, each lane holding its own context's fact" do
      # v1 declared all of it in one contract. Here the patient leaving is
      # scheduling's (`E-51`) and the clinical close documentation's (`E-52`), and
      # this contract includes both (distillation, finding 1).
      mermaid = shape()

      assert mermaid =~ ~s(subgraph stage_departure["departure"])
      assert mermaid =~ ~s(visit_completed["Pacjent wyszedł z gabinetu"])
      assert mermaid =~ ~s(subgraph stage_closing["closing"])
      assert mermaid =~ ~s(visit_closed_clinically["Zamknięto wizytę przez specjalistę"])
    end

    test "a lane holding several events says it claims no order between them" do
      assert shape() =~ ~s(subgraph stage_reporting["reporting · no order claimed inside"])
      refute shape() =~ "departure · no order"
    end

    test "the run carries only what the report depends on" do
      # The documentation has its own events — the codes are one, since v2 — but
      # they are that context's, and the run is the report's. The notes and the
      # treatment were never events: nothing outside the document depends on them.
      mermaid = shape()

      refute mermaid =~ "diagnosis_coded"
      refute mermaid =~ "history_taken"
      refute mermaid =~ "treatment_performed"
      refute mermaid =~ "patient_arrived"
    end

    test "the promise is an arrow carrying its window, from the patient leaving" do
      mermaid = shape()

      # From `visit_completed`, the end of the service, as the regulation counts,
      # not from the clinical close, which can lag by days.
      assert mermaid =~ "visit_completed ==>|within 2 days| p1_report_sent"
      assert mermaid =~ "visit_completed -.->|or else| p1_reporting_not_required"
      refute mermaid =~ "visit_closed_clinically ==>"

      # v1 had a second, one-day promise to report or be chased. The day is now the
      # documentation's process manager, which creates a task; a promise kept by the
      # task being created would count a late visit as kept.
      refute mermaid =~ "within 24 hours"
    end

    test "a dependency hangs off the fact that declares it, on a line with no arrowhead" do
      mermaid = shape()

      assert mermaid =~ ~s|p1[("Rejestr zdarzeń medycznych P1")]|
      assert mermaid =~ "p1_report_sent -.- p1"
      assert mermaid =~ "p1_report_failed -.- p1"
      # An arrowhead would read as causation, and somebody would build on it.
      refute mermaid =~ "p1_report_sent -.-> p1"
    end

    test "how a process can end is visible without reading anything" do
      mermaid = shape()

      assert mermaid =~ "class p1_report_sent,p1_reporting_not_required terminal"
      assert mermaid =~ "classDef terminal"
    end

    test "a process nobody declared is an error, and the message says what exists" do
      assert_raise ArgumentError, ~r/declares no process :nonesuch/, fn ->
        EhOsContract.Graph.declared_to_mermaid(@contract, :nonesuch)
      end
    end
  end
end
