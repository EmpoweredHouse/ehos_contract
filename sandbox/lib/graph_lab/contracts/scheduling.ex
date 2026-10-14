defmodule GraphLab.Contracts.Scheduling do
  @moduledoc """
  **Part of the test set for drawing the graph; not client material** (`GraphLab`).

  Scheduling: a visit from its booking to one of its three ends — the patient seen, the
  visit cancelled, or the patient not coming.

  - **A lifecycle.** The visit's statuses, and the commands that end it early name the
    statuses they are issued in. A patient leaving the room whom reception never saw
    arrive is still recorded, and moves nothing: the report shows it as a move the
    lifecycle does not allow.
  - **The confirmation, from another application.** The patient confirms in the patient
    app, which publishes it, and a policy confirms the visit; reception may confirm by
    phone.
  """

  use EhOsContract.Contract,
    domain: GraphLab.Domain,
    context: :scheduling,
    id: "graph-lab.scheduling"

  # An event of another application, which arrives in an inbox.
  subscribe "patient-app.visit.confirmed.v1", as: :confirmed_in_app do
    field :visit_id, {:id, :visit}
  end

  aggregate :visit, "Wizyta" do
    identity :visit_id, generated: :uuid

    invariant :only_a_visit_not_yet_held_ends_early,
              "Odwołać wizytę albo odnotować nieobecność można tylko przed jej odbyciem",
              source: "AGG-01, stany: C-16 i C-17 tylko z Umówiona, Potwierdzona, BrakKontaktu"

    invariant :only_a_booked_visit_is_confirmed,
              "Potwierdza się tylko wizytę umówioną i jeszcze niepotwierdzoną",
              source: "dodane do testów grafu"

    # `AGG-01`'s states, in its own words.
    lifecycle do
      status :booked, "Umówiona"
      status :confirmed, "Potwierdzona"
      status :in_progress, "W gabinecie"
      status :completed, "Zrealizowana", final: true
      status :cancelled, "Odwołana", final: true
      status :no_show, "Nieobecność", final: true

      initial :booked, on: :visit_booked
      transition :booked, :patient_confirmed, :confirmed
      transition [:booked, :confirmed], :patient_arrived, :in_progress
      transition :in_progress, :visit_completed, :completed
      transition [:booked, :confirmed], :visit_cancelled, :cancelled
      transition [:booked, :confirmed], :patient_no_show, :no_show
    end

    command :book_visit, "Umów wizytę",
      by: :reception,
      emits: :visit_booked,
      creates: true,
      reads: [service: :service_id],
      source: "C-09, aktor A-02" do
      field :patient_id, :id, subject: :patient
      field :service_id, {:id, :service}
      field :specialist_id, :id
      field :scheduled_at, :timestamp
    end

    # Issued by reception on the phone, or by the policy on the patient's answer in the app.
    command :confirm_visit, "Potwierdź wizytę",
      by: :reception,
      emits: :patient_confirmed,
      from: :booked,
      or_rejects: :only_a_booked_visit_is_confirmed,
      rejects: :only_a_booked_visit_is_confirmed,
      source: "dodane do testów grafu"

    command :cancel_visit, "Odwołaj wizytę",
      by: :reception,
      emits: :visit_cancelled,
      from: [:booked, :confirmed],
      or_rejects: :only_a_visit_not_yet_held_ends_early,
      rejects: :only_a_visit_not_yet_held_ends_early,
      source: "C-16, aktor A-01 przez A-02"

    command :record_no_show, "Odnotuj nieobecność",
      by: :reception,
      emits: :patient_no_show,
      from: [:booked, :confirmed],
      or_rejects: :only_a_visit_not_yet_held_ends_early,
      rejects: :only_a_visit_not_yet_held_ends_early,
      source: "C-17, aktor A-02"

    event :visit_booked, "Pacjent umówił wizytę", source: "E-14" do
      field :patient_id, :id, subject: :patient
      field :service_id, {:id, :service}
      field :specialist_id, :id
      field :scheduled_at, :timestamp
      field :p1_reported, :boolean, label: "Raportowana do P1"
    end

    event :patient_confirmed, "Pacjent potwierdził wizytę", source: "dodane do testów grafu"

    event :patient_arrived, "Klient pojawił się na wizycie",
      recorded_by: :reception,
      source: "E-27"

    event :visit_completed, "Pacjent wyszedł z gabinetu",
      recorded_by: :specialist,
      source: "E-51"

    event :visit_cancelled, "Oznaczono wizytę jako odwołaną", source: "E-28"

    event :patient_no_show, "Pacjent nie przyszedł", source: "E-32, E-35"
  end

  policy :confirm_from_app, "Pacjent potwierdził w aplikacji — wizyta potwierdzona",
    handles: :confirmed_in_app,
    issues: :confirm_visit,
    source: "dodane do testów grafu"

  @booked %{
    patient_id: "patient-anna",
    service_id: "service-physiotherapy",
    specialist_id: "specialist-ewa",
    scheduled_at: "2026-10-05T09:00:00Z",
    p1_reported: true
  }

  scenario "recepcja umawia pacjenta — wizyta powstaje" do
    given_entity :service, %{service_id: "service-physiotherapy", p1_reported: true}

    command :book_visit, %{
      patient_id: "patient-anna",
      service_id: "service-physiotherapy",
      specialist_id: "specialist-ewa",
      scheduled_at: "2026-10-05T09:00:00Z"
    }

    expect :visit_booked, %{
      patient_id: "patient-anna",
      service_id: "service-physiotherapy",
      p1_reported: true
    }
  end

  scenario "wizyta na usługę spoza P1 pamięta, że nie będzie zgłaszana" do
    given_entity :service, %{service_id: "service-fitness", p1_reported: false}

    command :book_visit, %{
      patient_id: "patient-anna",
      service_id: "service-fitness",
      specialist_id: "specialist-ewa",
      scheduled_at: "2026-10-05T09:00:00Z"
    }

    expect :visit_booked, %{service_id: "service-fitness", p1_reported: false}
  end

  scenario "pacjent potwierdza w aplikacji — wizyta do potwierdzenia" do
    target :confirm_from_app
    on :confirmed_in_app, %{visit_id: "visit-anna"}
    issues :confirm_visit, %{visit_id: "visit-anna"}
  end

  scenario "recepcja potwierdza umówioną wizytę" do
    given :visit_booked, @booked
    command :confirm_visit
    expect :patient_confirmed
  end

  scenario "wizyta już potwierdzona — drugie potwierdzenie odrzucone" do
    given :visit_booked, @booked
    given :patient_confirmed
    command :confirm_visit
    rejected :only_a_booked_visit_is_confirmed
  end

  scenario "pacjent odwołuje wizytę przed terminem" do
    given :visit_booked, @booked
    command :cancel_visit
    expect :visit_cancelled
  end

  scenario "pacjent odwołuje potwierdzoną wizytę" do
    given :visit_booked, @booked
    given :patient_confirmed
    command :cancel_visit
    expect :visit_cancelled
  end

  scenario "pacjent nie przyszedł na umówioną wizytę" do
    given :visit_booked, @booked
    command :record_no_show
    expect :patient_no_show
  end

  scenario "pacjent nie przyszedł mimo potwierdzenia" do
    given :visit_booked, @booked
    given :patient_confirmed
    command :record_no_show
    expect :patient_no_show
  end

  scenario "pacjent już wyszedł z gabinetu — wizyty nie da się odwołać" do
    given :visit_booked, @booked
    given :patient_arrived
    given :visit_completed
    command :cancel_visit
    rejected :only_a_visit_not_yet_held_ends_early
  end

  scenario "pacjent był na wizycie — nie odnotowuje się nieobecności" do
    given :visit_booked, @booked
    given :patient_arrived
    command :record_no_show
    rejected :only_a_visit_not_yet_held_ends_early
  end
end
