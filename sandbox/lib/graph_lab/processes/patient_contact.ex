defmodule GraphLab.Processes.PatientContact do
  @moduledoc """
  **Part of the test set for drawing the graph; not client material** (`GraphLab`).

  The contact with a patient around one visit: the booking, and every message about it
  queued and delivered. **It has no end**: a run stays open for as long as a message may
  still follow, which is the shape of the graph this module is here for.
  """

  use EhOsContract.Process,
    id: "graph-lab.patient_contact",
    domain: GraphLab.Domain,
    label: "Kontakt z pacjentem wokół wizyty",
    accountable: :reception

  correlate :visit_id

  stage :booking, "Umówienie", include: [{GraphLab.Contracts.Scheduling, :visit_booked}]

  stage :messages, "Wiadomości",
    include: [{GraphLab.Contracts.PatientMessaging, [:message_queued, :message_delivered]}]

  # Kept by any message delivered about the visit, the reminder or another: the promise is
  # that the patient hears from the clinic, whatever the message.
  promise :patient_informed_within_a_day do
    from :visit_booked
    eventually :message_delivered
    within {1, :day}
    source "dodane do testów grafu"
  end

  @booked %{
    visit_id: "visit-anna",
    patient_id: "patient-anna",
    service_id: "service-physiotherapy",
    specialist_id: "specialist-ewa",
    scheduled_at: "2026-09-10T09:00:00Z",
    p1_reported: true
  }

  scenario "przypomnienie doręczone godzinę po umówieniu — termin dotrzymany",
    verdict: :satisfied,
    via: :eventually do
    given :visit_booked, @booked, at: "2026-09-07T09:00:00+02:00"

    given :message_delivered,
          %{visit_id: "visit-anna", kind: :reminder, gateway_message_id: "sms-1"},
          at: "2026-09-07T10:00:00+02:00"

    promise :patient_informed_within_a_day, at: "2026-09-08T10:00:00+02:00"
  end

  scenario "bramka SMS nie działała, przypomnienie niedoręczone — termin zawieszony",
    verdict: :suspended do
    given :visit_booked, @booked, at: "2026-09-07T09:00:00+02:00"
    outage :sms_gateway, at: "2026-09-07T12:00:00+02:00"
    promise :patient_informed_within_a_day, at: "2026-09-08T10:00:00+02:00"
  end
end
