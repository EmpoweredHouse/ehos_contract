defmodule GraphLab.Contracts.PatientMessaging do
  @moduledoc """
  **Added to the test set to test the graph on; not client material** (`GraphLab`).

  The text messages a patient gets about a visit: a reminder when it is booked, a notice
  when it is cancelled, a survey when the patient has left.

  It is here for three shapes of the graph: an event consumed under another name —
  scheduling's `visit_completed` is `patient_left` here, the words of this context — one
  policy taking three events, and an effect whose external system records its answer as
  a system actor.
  """

  use EhOsContract.Contract,
    domain: GraphLab.Domain,
    context: :patient_messaging,
    id: "graph-lab.patient_messaging"

  consumes GraphLab.Contracts.Scheduling, [:visit_booked, :visit_cancelled, :visit_completed],
    as: [visit_completed: :patient_left]

  aggregate :visit_messages, "Wiadomości o wizycie" do
    identity visit_id: {:id, :visit}

    state do
      field :queued, {:list, :message_kind}, default: []
    end

    invariant :one_message_of_a_kind, "Pacjent dostaje każdą wiadomość o wizycie raz",
      source: "dodane do testów grafu"

    # Issued by the policy only, so no actor may.
    command :queue_message, "Zakolejkuj wiadomość do pacjenta",
      emits: :message_queued,
      rejects: :one_message_of_a_kind,
      source: "dodane do testów grafu" do
      field :kind, :message_kind
    end

    event :message_queued, "Zakolejkowano wiadomość do pacjenta",
      source: "dodane do testów grafu" do
      field :kind, :message_kind
    end

    event :message_delivered, "Bramka SMS doręczyła wiadomość",
      recorded_by: :sms_integration,
      depends_on: :sms_gateway,
      source: "dodane do testów grafu" do
      field :kind, :message_kind
    end
  end

  policy :message_the_patient, "Wizyta umówiona, odwołana albo odbyta — wiadomość do pacjenta",
    handles: [:visit_booked, :visit_cancelled, :patient_left],
    issues: :queue_message,
    delivery: :at_least_once,
    idempotency: [key: :event_id, owner: :infrastructure],
    source: "dodane do testów grafu"

  effect :send_sms, "Wyślij SMS do pacjenta",
    handles: :message_queued,
    calls: {:sms_gateway, :send_sms},
    idempotency: [key: :event_id, owner: :downstream]

  @booked %{
    visit_id: "visit-anna",
    patient_id: "patient-anna",
    service_id: "service-physiotherapy",
    specialist_id: "specialist-ewa",
    scheduled_at: "2026-10-05T09:00:00Z",
    p1_reported: true
  }

  scenario "wizyta umówiona — przypomnienie dla pacjenta" do
    target :message_the_patient
    on :visit_booked, @booked
    issues :queue_message, %{visit_id: "visit-anna", kind: :reminder}
  end

  scenario "wizyta odwołana — wiadomość o odwołaniu" do
    target :message_the_patient
    on :visit_cancelled, %{visit_id: "visit-anna"}
    issues :queue_message, %{visit_id: "visit-anna", kind: :cancellation}
  end

  scenario "pacjent wyszedł z gabinetu — ankieta po wizycie" do
    target :message_the_patient
    on :patient_left, %{visit_id: "visit-anna"}
    issues :queue_message, %{visit_id: "visit-anna", kind: :survey}
  end

  scenario "przypomnienie trafia do kolejki" do
    command :queue_message, %{kind: :reminder}
    expect :message_queued, %{kind: :reminder}
  end

  scenario "przypomnienie już wysłane — drugie odrzucone" do
    given :message_queued, %{kind: :reminder}
    command :queue_message, %{kind: :reminder}
    rejected :one_message_of_a_kind
  end
end
