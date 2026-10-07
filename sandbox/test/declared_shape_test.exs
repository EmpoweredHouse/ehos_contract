defmodule EhOsContract.DeclaredShapeTest do
  @moduledoc """
  The declared shape of the clinical visit: what `Rehmed.Processes.ClinicalVisit`
  says its run is, read from its model.

  Its assertions are **about the modelling** of the run rather than about a reader of
  it: that the run crosses three contexts, that it carries only what the report
  depends on, that the promise counts from the patient leaving. Repointed at an
  invented fixture they would still pass and would no longer be checking anything —
  they are the review a real process has to survive, and they belong where the real
  process is.

  Re-derived on 28 September 2026 (v2 plan, E9a) when the v1 `ClinicalVisit` it was
  drawn from gave way to three contexts' contracts, and again by plan DD, P2f (#222),
  when the run left `Rehmed.Contracts.StatutoryReporting` for a process module. Until
  then it read the picture `EhOsContract.Graph.declared_to_mermaid/2` drew of the
  contract's process; a process module has no picture until #220, so it reads the
  model. What only the picture showed — lanes, arrows, a dependency's line — goes
  untested for the clinic until process modules are drawn (#220); the library's
  `graph_test` keeps the renderer's own cases.
  """

  use ExUnit.Case, async: true

  alias EhOsContract.Model
  alias Rehmed.Contracts.{ClinicalDocumentation, Scheduling, StatutoryReporting}

  @process Rehmed.Processes.ClinicalVisit

  defp model, do: Model.fetch(@process)

  defp events, do: Model.process_events(@process)

  describe "the declared shape of the clinical visit" do
    test "its stages, in the order the run goes through them" do
      assert Enum.map(model().stages, & &1.name) == [:departure, :closing, :reporting]
    end

    test "the run crosses three contexts, each stage holding its own context's fact" do
      # v1 declared all of it in one contract. Here the patient leaving is
      # scheduling's (`E-51`) and the clinical close documentation's (`E-52`), and
      # the module includes both (distillation, finding 1).
      by_stage = Enum.group_by(events(), & &1.stage, &{&1.contract, &1.name})

      assert by_stage.departure == [{Scheduling, :visit_completed}]
      assert by_stage.closing == [{ClinicalDocumentation, :visit_closed_clinically}]

      assert by_stage.reporting == [
               {StatutoryReporting, :p1_report_queued},
               {StatutoryReporting, :p1_report_sent},
               {StatutoryReporting, :p1_report_failed},
               {StatutoryReporting, :p1_reporting_not_required}
             ]
    end

    test "the run carries only what the report depends on" do
      # The documentation has its own events — the codes are one, since v2 — but
      # they are that context's, and the run is the report's. The notes and the
      # treatment were never events: nothing outside the document depends on them.
      names = Enum.map(events(), & &1.name)

      refute :diagnosis_coded in names
      refute :history_taken in names
      refute :treatment_performed in names
      refute :patient_arrived in names
    end

    test "the promise counts from the patient leaving, and is kept the other way by a waiver" do
      assert [promise] = model().promises

      # From `visit_completed`, the end of the service, as the regulation counts,
      # not from the clinical close, which can lag by days.
      assert %{
               from: :visit_completed,
               eventually: :p1_report_sent,
               or_else: :p1_reporting_not_required,
               within: %{amount: 2, unit: :day}
             } = promise

      # v1 had a second, one-day promise to report or be chased. The day is now the
      # documentation's process manager, which creates a task; a promise kept by the
      # task being created would count a late visit as kept.
    end

    test "the registry is what the report's answer depends on" do
      depends =
        for e <- events(),
            Map.get(e.declaration, :depends_on),
            do: {e.name, e.declaration.depends_on}

      assert {:p1_report_sent, :p1} in depends
      assert {:p1_report_failed, :p1} in depends
    end

    test "how a run can end: the report sent, or waived, and not a rejection" do
      assert Enum.sort(model().ends_on) == [:p1_report_sent, :p1_reporting_not_required]
      refute :p1_report_failed in model().ends_on
    end
  end
end
