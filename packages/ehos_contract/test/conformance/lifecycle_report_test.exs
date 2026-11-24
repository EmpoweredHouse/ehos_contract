defmodule EhosContract.LifecycleReportTest do
  @moduledoc """
  Plan LC3 (#99): the report's first two questions for an aggregate's lifecycle —
  which declared transitions no aggregate took, and which moves the lifecycle does
  not allow happened anyway. On the invented `LifecycleRig.Visits`.
  """

  use EhosContract.DataCase, async: false

  alias EhosContract.{Actor, Conformance, Report}
  alias LifecycleRig.Visits
  alias LifecycleRig.Visits.Commands.{AdmitPatient, BookVisit, CloseVisit}
  alias LifecycleRig.Visits.Events.PatientArrived

  defp reception,
    do:
      Actor.credential(
        "u-reception",
        Enum.map(~w(book_visit admit_patient close_visit), &"lifecycle_rig.#{&1}")
      )

  defp issue(module, visit),
    do:
      {:ok, _} =
        EhosContract.dispatch(Visits, struct(module, visit_id: visit), actor: reception())

  # The kiosk saw the patient check in: recorded, never refused for not fitting.
  defp arrive(visit),
    do:
      {:ok, _} =
        EhosContract.record(Visits, %PatientArrived{visit_id: visit},
          actor: Actor.system(:front_desk)
        )

  defp lifecycle(opts \\ []), do: hd(Conformance.report(Visits, opts).lifecycles)

  defp moves(transitions),
    do: Enum.map(transitions, &{&1.from && &1.from.name, &1.event.name, &1.to.name})

  test "with no aggregate in the period nothing is untraversed" do
    assert %{aggregates: 0, untraversed: [], undeclared: []} = lifecycle()
  end

  test "each declared transition with how often it was taken; one an open visit can still take is not yet" do
    issue(BookVisit, "v-1")
    issue(AdmitPatient, "v-1")
    issue(CloseVisit, "v-1")
    issue(BookVisit, "v-2")

    l = lifecycle()

    assert l.aggregates == 2

    assert Enum.map(
             l.transitions,
             &{&1.from && &1.from.name, &1.event.name, &1.to.name, &1.count}
           ) ==
             [
               {nil, :booked, :booked, 2},
               {:booked, :patient_arrived, :in_progress, 1},
               {:booked, :cancelled, :cancelled, 0},
               {:in_progress, :closed, :closed, 1}
             ]

    # v-2 is still booked, so it can still be cancelled: not yet, not never.
    assert l.untraversed == []
    assert moves(l.pending) == [{:booked, :cancelled, :cancelled}]
    assert l.undeclared == []
  end

  test "once no aggregate can take it any more, a transition never taken is never taken" do
    issue(BookVisit, "v-1")
    issue(AdmitPatient, "v-1")
    issue(CloseVisit, "v-1")

    l = lifecycle()
    assert moves(l.untraversed) == [{:booked, :cancelled, :cancelled}]
    assert l.pending == []
  end

  test "an event before the aggregate started is said so, not as a status" do
    arrive("v-9")

    assert [%{from: nil, event: %{name: :patient_arrived}, count: 1}] = lifecycle().undeclared

    assert Report.render(Conformance.report(Visits)) =~
             "    · Patient arrived before the aggregate started — no status followed  (1x)"
  end

  test "a recorded event that did not fit is counted where the aggregate stood" do
    issue(BookVisit, "v-1")
    issue(AdmitPatient, "v-1")
    issue(CloseVisit, "v-1")
    arrive("v-1")
    arrive("v-1")

    assert [%{from: %{name: :closed}, event: %{name: :patient_arrived}, count: 2}] =
             lifecycle().undeclared
  end

  test "only the period's events are counted, though earlier ones set the status" do
    issue(BookVisit, "v-1")
    # Untouched in the period: not read, and not counted.
    issue(BookVisit, "v-2")
    since = DateTime.utc_now()
    issue(AdmitPatient, "v-1")

    l = lifecycle(since: since)

    assert l.aggregates == 1
    counts = Map.new(l.transitions, &{&1.event.name, &1.count})
    assert counts.booked == 0
    assert counts.patient_arrived == 1
    assert l.undeclared == []
  end

  test "the report says it in sentences, and the labels as the contract has them" do
    issue(BookVisit, "v-1")
    issue(AdmitPatient, "v-1")
    issue(CloseVisit, "v-1")
    arrive("v-1")

    text = Report.render(Conformance.report(Visits))

    assert text =~ "LIFECYCLE: Visit\n  Aggregates with an event in this period: 1."

    assert text =~
             "  Declared transitions never taken:\n    · Booked → Cancelled (on: Visit cancelled)"

    assert text =~
             "  Happened, though the lifecycle does not allow it there:\n" <>
               "    · Patient arrived in Closed — the status stayed  (1x)"
  end

  test "on the wire, the start of an aggregate is null" do
    issue(BookVisit, "v-1")

    %{"report" => %{"lifecycles" => [wire]}} = Conformance.as_data(Visits)

    assert %{"from" => nil, "event" => %{"name" => "booked"}, "to" => %{"name" => "booked"}} =
             hd(wire["transitions"])

    assert Jason.encode!(wire)
  end
end
