defmodule GraphLab.Processes.VisitSettlement do
  @moduledoc """
  **Added to the test set to test the graph on; not client material** (`GraphLab`).

  A visit from the patient leaving the room to its commercial close at reception. It
  shares `visit_completed` with `GraphLab.Processes.ClinicalVisit`, so two process lines
  cross at that event. Its promise is invented for the graph, since Rehmed's material
  names no interval for a settlement (`Rehmed.Contracts.Settlement`): a visit is settled
  within twelve hours of the patient leaving, or closed without payment when a payer
  covers it.
  """

  use EhOsContract.Process,
    id: "graph-lab.visit_settlement",
    domain: GraphLab.Domain,
    label: "Wizyta: od wyjścia pacjenta do rozliczenia",
    accountable: :reception

  correlate :visit_id

  stage :departure, include: [{GraphLab.Contracts.Scheduling, :visit_completed}]

  stage :settlement,
    include: [
      {GraphLab.Contracts.Settlement,
       [
         :payment_recorded,
         :unsettled_visit_flagged,
         :visit_closed_commercially,
         :visit_closed_without_payment
       ]}
    ]

  ends_on [:visit_closed_commercially, :visit_closed_without_payment]

  promise :settled_the_same_day do
    from :visit_completed
    eventually :visit_closed_commercially
    within {12, :hour}
    or_else :visit_closed_without_payment
    source "dodane do testów grafu"
  end

  scenario "wizyta opłacona godzinę po wyjściu pacjenta — termin dotrzymany",
    verdict: :satisfied,
    via: :eventually do
    given :visit_completed, %{visit_id: "visit-anna"}, at: "2026-09-07T09:00:00+02:00"

    given :visit_closed_commercially, %{visit_id: "visit-anna", total: 20_000},
      at: "2026-09-07T10:00:00+02:00"

    promise :settled_the_same_day, at: "2026-09-08T09:00:00+02:00"
  end

  scenario "wizyta nierozliczona następnego dnia — termin przekroczony", verdict: :violated do
    given :visit_completed, %{visit_id: "visit-anna"}, at: "2026-09-07T09:00:00+02:00"
    promise :settled_the_same_day, at: "2026-09-08T09:00:00+02:00"
  end
end
