defmodule GraphLab.Processes.ClinicalVisit do
  @moduledoc """
  **Part of the test set for drawing the graph; not client material** (`GraphLab`).

  The clinical visit as one run: from the patient leaving the room, through the clinical
  close, to the report to the medical events register. The promise counts the statutory
  two days from the patient leaving, and a waived report keeps it for a service that is
  not reported. A rejection by the register does not end the run: the report is still
  owed.
  """

  # The old watchdog "notified the manager at the moment the deadline had already
  # passed", and overdue work surfaces to the manager as a
  # count (`P-25`): the manager is who a breach is addressed to.
  use EhOsContract.Process,
    id: "graph-lab.clinical_visit",
    domain: GraphLab.Domain,
    label: "Wizyta: wykonanie, dokumentacja i zgłoszenie zdarzenia medycznego",
    accountable: :manager

  correlate :visit_id

  stage :departure, include: [{GraphLab.Contracts.Scheduling, :visit_completed}]
  stage :closing, include: [{GraphLab.Contracts.ClinicalDocumentation, :visit_closed_clinically}]

  stage :reporting,
    include: [
      {GraphLab.Contracts.StatutoryReporting,
       [:p1_report_queued, :p1_report_sent, :p1_report_failed, :p1_reporting_not_required]}
    ]

  ends_on [:p1_report_sent, :p1_reporting_not_required]

  promise :medical_event_reported_within_statutory_window do
    from :visit_completed
    eventually :p1_report_sent
    within {2, :day}
    or_else :p1_reporting_not_required
    source "Dz.U. 2025 poz. 866"
  end

  scenario "raport do P1 wysłany następnego dnia — termin dotrzymany",
    verdict: :satisfied,
    via: :eventually do
    given :visit_completed, %{visit_id: "visit-anna"}, at: "2026-09-07T09:00:00+02:00"
    given :p1_report_sent, %{visit_id: "visit-anna"}, at: "2026-09-08T10:00:00+02:00"
    promise :medical_event_reported_within_statutory_window, at: "2026-09-10T09:00:00+02:00"
  end

  scenario "usługa niezgłaszana do P1 — termin dotrzymany bez raportu",
    verdict: :satisfied,
    via: :or_else do
    given :visit_completed, %{visit_id: "visit-anna"}, at: "2026-09-07T09:00:00+02:00"
    given :p1_reporting_not_required, %{visit_id: "visit-anna"}, at: "2026-09-07T15:00:00+02:00"
    promise :medical_event_reported_within_statutory_window, at: "2026-09-10T09:00:00+02:00"
  end

  scenario "raport wysłany po dwóch dniach — termin przekroczony", verdict: :violated do
    given :visit_completed, %{visit_id: "visit-anna"}, at: "2026-09-07T09:00:00+02:00"
    given :p1_report_sent, %{visit_id: "visit-anna"}, at: "2026-09-09T11:00:00+02:00"
    promise :medical_event_reported_within_statutory_window, at: "2026-09-10T09:00:00+02:00"
  end

  scenario "rejestr P1 nie działał, raport niewysłany — termin zawieszony", verdict: :suspended do
    given :visit_completed, %{visit_id: "visit-anna"}, at: "2026-09-07T09:00:00+02:00"
    outage :p1, at: "2026-09-08T10:00:00+02:00"
    promise :medical_event_reported_within_statutory_window, at: "2026-09-10T09:00:00+02:00"
  end

  scenario "rejestr P1 padł dopiero po terminie — termin przekroczony", verdict: :violated do
    given :visit_completed, %{visit_id: "visit-anna"}, at: "2026-09-07T09:00:00+02:00"
    outage :p1, at: "2026-09-09T12:00:00+02:00"
    promise :medical_event_reported_within_statutory_window, at: "2026-09-10T09:00:00+02:00"
  end

  scenario "dzień po wizycie, raportu jeszcze nie ma — termin biegnie", verdict: :pending do
    given :visit_completed, %{visit_id: "visit-anna"}, at: "2026-09-07T09:00:00+02:00"
    promise :medical_event_reported_within_statutory_window, at: "2026-09-08T09:00:00+02:00"
  end
end
