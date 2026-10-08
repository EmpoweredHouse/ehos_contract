defmodule EhOsContract.DeclaredShapeTest do
  @moduledoc """
  The declared shape of a process: the picture the dashboard draws of it, the
  renderer's `EhOsContract.GraphRenderer.View.declared/1` over the contract's
  `graph.v1` document.

  Drawn from `Rehmed.Contracts.StatutoryReporting`'s `:clinical_visit`, and several
  of its assertions are **about that contract's modelling** rather than about the
  renderer: that the run crosses three contexts, that it carries only what the
  report depends on, that the promise counts from the patient leaving. Repointed at
  an invented fixture those assertions would still pass and would no longer be
  checking anything — they are the review a real contract has to survive, and they
  belong where the real contract is.

  Re-derived on 28 September 2026 (v2 plan, E9a) when the v1 `ClinicalVisit` it was
  drawn from gave way to three contexts' contracts. What changed in the modelling,
  and why, is beside each test. Read from the renderer's view since plan E13b, which
  took the engine's own picture away.
  """

  use ExUnit.Case, async: true

  alias EhOsContract.Graph.Document
  alias EhOsContract.GraphRenderer.View

  describe "the declared shape of the clinical visit" do
    @contract Rehmed.Contracts.StatutoryReporting

    defp shape, do: View.declared(Document.contract(@contract))

    # Every arrow by the names of its ends: `{type, from, to, words, line, head}`.
    defp arrows(shape) do
      names = Map.new(shape.nodes ++ shape.groups, &{&1.id, &1.facts["name"]})
      for r <- shape.relations, do: {r.type, names[r.from], names[r.to], r.words, r.line, r.head}
    end

    defp card(shape, name), do: Enum.find(shape.nodes, &(&1.facts["name"] == name))
    defp group(shape, name), do: Enum.find(shape.groups, &(&1.facts["name"] == name))

    test "stages are lanes, chained in the order the contract declares" do
      # The only ordering claim a contract makes is between stages, so it is the only
      # arrow drawn between lanes — chained pairwise, never the other way round and
      # never fully connected.
      chain = for {"precedes", from, to, _, _, _} <- arrows(shape()), do: {from, to}
      assert chain == [{"departure", "closing"}, {"closing", "reporting"}]
    end

    test "the run crosses three contexts, each lane holding its own context's fact" do
      # v1 declared all of it in one contract. Here the patient leaving is
      # scheduling's (`E-51`) and the clinical close documentation's (`E-52`), and
      # this contract includes both (distillation, finding 1).
      shape = shape()

      assert %{label: "Pacjent wyszedł z gabinetu", group: departure} =
               card(shape, "visit_completed")

      assert departure == group(shape, "departure").id

      assert %{label: "Zamknięto wizytę przez specjalistę", group: closing} =
               card(shape, "visit_closed_clinically")

      assert closing == group(shape, "closing").id
    end

    test "a lane holding several events says it claims no order between them" do
      assert group(shape(), "reporting").title == "reporting · no order claimed inside"
      assert group(shape(), "departure").title == "departure"
    end

    test "the run carries only what the report depends on" do
      # The documentation has its own events — the codes are one, since v2 — but
      # they are that context's, and the run is the report's. The notes and the
      # treatment were never events: nothing outside the document depends on them.
      names = Enum.map(shape().nodes, & &1.facts["name"])

      for name <- ~w(diagnosis_coded history_taken treatment_performed patient_arrived),
          do: refute(name in names, name)
    end

    test "the promise is an arrow carrying its window, from the patient leaving" do
      arrows = arrows(shape())

      # From `visit_completed`, the end of the service, as the regulation counts,
      # not from the clinical close, which can lag by days.
      assert {"promise", "visit_completed", "p1_report_sent", "within 2 days", "thick", true} in arrows

      assert {"or_else", "visit_completed", "p1_reporting_not_required", "or else", "dotted",
              true} in arrows

      refute Enum.any?(arrows, &match?({"promise", "visit_closed_clinically", _, _, _, _}, &1))

      # v1 had a second, one-day promise to report or be chased. The day is now the
      # documentation's process manager, which creates a task; a promise kept by the
      # task being created would count a late visit as kept.
      refute Enum.any?(arrows, &match?({_, _, _, "within 24 hours", _, _}, &1))
    end

    test "a dependency hangs off the fact that declares it, on a line with no arrowhead" do
      shape = shape()

      assert %{kind: "external", label: "Rejestr zdarzeń medycznych P1"} = card(shape, "p1")

      # An arrowhead would read as causation, and somebody would build on it.
      for event <- ~w(p1_report_sent p1_report_failed),
          do: assert({"depends_on", event, "p1", nil, "dotted", false} in arrows(shape))
    end

    test "how a process can end is visible without reading anything" do
      ends = for %{variant: "terminal"} = n <- shape().nodes, do: n.facts["name"]
      assert Enum.sort(ends) == ["p1_report_sent", "p1_reporting_not_required"]
    end
  end
end
