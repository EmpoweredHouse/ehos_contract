defmodule Rehmed.Processes.ClinicalVisit do
  @moduledoc """
  The clinical visit as one run (plan DD, P2f, #222): from the patient leaving
  (scheduling, `E-51`) through the clinical close (documentation, `E-52`) to the
  report to the medical events register (statutory reporting). It is the
  distillation's finding 1 in part: each context declares its own events, and the
  run includes them from all three. Until P2f it was `:clinical_visit` inside
  `Rehmed.Contracts.StatutoryReporting`.

  The promise counts two days from `visit_completed`, the end of the service, as the
  regulation does (Dz.U. 2025 poz. 866), not from the clinical close, which can lag
  by days; `p1_reporting_not_required` keeps it for a visit that owes the registry
  nothing (`H21`, `DEC-20`). Why each, and what is still open, is in the contract's
  moduledoc.

  The run ends when the report is sent (`E-54`) or waived. A rejection by the
  registry (`AGG-10`'s error state) does not end it: the report is still owed, and
  its retry (`S-46`) is not written yet.
  """

  # The old watchdog "notified the manager at the moment the deadline had already
  # passed" (distillation, process 3), and overdue work surfaces to the manager as a
  # count (`P-25`): the manager is who a breach is addressed to.
  use EhOsContract.Process,
    id: "rehmed.clinical_visit",
    domain: Rehmed.Domain,
    label: "Wizyta: wykonanie, dokumentacja i zgłoszenie zdarzenia medycznego",
    accountable: :manager

  correlate :visit_id

  stage :departure, include: [{Rehmed.Contracts.Scheduling, :visit_completed}]
  stage :closing, include: [{Rehmed.Contracts.ClinicalDocumentation, :visit_closed_clinically}]

  stage :reporting,
    include: [
      {Rehmed.Contracts.StatutoryReporting,
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
end
