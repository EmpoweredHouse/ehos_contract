defmodule Rehmed.Contracts.Scheduling do
  @moduledoc """
  Scheduling and resources (`CTX-01`): the visit as a held slot, from the booking to
  one of its three ends.

  Written from `AGG-01` in `2-Solution/20-aggregates.md` and process 1 of
  `docs/rehmed-2026-08-18-distillation.md` (v2 plan, E9). The commands are the event
  model's `C-09`, `C-16` and `C-17`, by the actors its catalogue gives them. The
  event names are the distillation's.

  ## What is decided here, and what is only recorded

  A booking, a cancellation and a no-show are reception's acts, and a visit that
  already happened can be neither cancelled nor missed: the state machine in `AGG-01`
  reaches cancelled and no-show only from states before the patient arrives.
  That is the one invariant.

  The patient arriving and the patient leaving the room are observations, not
  decisions (D6): nothing can refuse them, so they are recorded by the people who saw
  them, reception at the desk and the specialist at the door.

  ## What is left out, and why

  - **Confirmation and the calls** (`E-21`–`E-24`, `P-01`, `P-02`). `U-10`: an
    unconfirmed visit takes place, reception calls until someone answers, so no
    ordering claim rests on confirmation, and the reminder is anchored backwards from
    the visit, which a promise cannot express (distillation, finding 2).
  - **The resource rules** (`AGG-01` invariants 1, 3, 5, 10). The map calls this
    context a constraint-satisfaction problem, and that is where the rules live: in
    whether a slot is free, which the booking screen answers before a command exists.
  - **The payer's PESEL before booking** (invariant 4) belongs to external payers,
    stage E9b.
  - **The two-person visit** (`H35`) is still undecided as one visit or two.

  ## No process

  The contract holds the visit as a unit, not as a run. The run the clinic described
  crosses three contexts with the same visit, and it is statutory reporting's
  `clinical_visit`, which includes `visit_completed` from here (distillation,
  finding 1). Which of its three ends a visit reached is the aggregate's state.

  `visit_booked`, `visit_completed` and `visit_cancelled` start with the aggregate's
  name and `check` says so (`event-name-with-aggregate-prefix`): the names are the
  distillation's and the aggregate is `AGG-01`'s (plan, the decisions before E9).
  """

  use EhOsContract.Contract, domain: Rehmed.Domain, context: :scheduling, id: "rehmed.scheduling"

  aggregate :visit, "Wizyta" do
    # `C-09` creates the visit, and the library gives it its identifier: a booking
    # repeated with the same idempotency key is the same visit (plan EM2).
    identity :visit_id, generated: :uuid

    state do
      field :ended, :boolean, default: false
    end

    invariant :only_a_visit_not_yet_held_ends_early,
              "Odwołać wizytę albo odnotować nieobecność można tylko przed jej odbyciem",
              source: "AGG-01, stany: C-16 i C-17 tylko z Umówiona, Potwierdzona, BrakKontaktu"

    command :book_visit, "Umów wizytę",
      by: :reception,
      emits: :visit_booked,
      creates: true,
      source: "C-09, aktor A-02" do
      field :patient_id, :id, subject: :patient
      field :service_id, {:id, :service}
      field :specialist_id, :id
      field :scheduled_at, :timestamp
    end

    command :cancel_visit, "Odwołaj wizytę",
      by: :reception,
      emits: :visit_cancelled,
      rejects: :only_a_visit_not_yet_held_ends_early,
      source: "C-16, aktor A-01 przez A-02"

    command :record_no_show, "Odnotuj nieobecność",
      by: :reception,
      emits: :patient_no_show,
      rejects: :only_a_visit_not_yet_held_ends_early,
      source: "C-17, aktor A-02"

    # `E-14`. The service decides what else happens to the visit: whether it is
    # reported to P1 is a flag on the service (`AGG-15`).
    event :visit_booked, "Pacjent umówił wizytę", source: "E-14" do
      field :patient_id, :id, subject: :patient
      field :service_id, {:id, :service}
      field :specialist_id, :id
      field :scheduled_at, :timestamp
    end

    # The three ends of `AGG-01` and the arrival before the good one. Which may follow
    # which is the invariant's to say: a no-show after an arrival is refused by it.
    #
    # `E-27`, and `H101` makes it load-bearing since the mockup: the manual presence
    # mark opens the till.
    event :patient_arrived, "Klient pojawił się na wizycie",
      recorded_by: :reception,
      source: "E-27"

    # `E-51`, the good end, `AGG-01`'s delivered state. The statutory two days to P1 count from
    # here (Dz.U. 2025 poz. 866), which is why `StatutoryReporting` includes it.
    event :visit_completed, "Pacjent wyszedł z gabinetu",
      recorded_by: :specialist,
      source: "E-51"

    event :visit_cancelled, "Oznaczono wizytę jako odwołaną", source: "E-28"

    # `E-35` is what `C-17` records; `E-32` is the same fact as the board wrote it.
    event :patient_no_show, "Pacjent nie przyszedł", source: "E-32, E-35"
  end

  scenario "recepcja umawia pacjenta — wizyta powstaje" do
    command :book_visit, %{
      patient_id: "patient-anna",
      service_id: "service-physiotherapy",
      specialist_id: "specialist-ewa",
      scheduled_at: "2026-10-05T09:00:00Z"
    }

    expect :visit_booked, %{patient_id: "patient-anna", service_id: "service-physiotherapy"}
  end

  scenario "pacjent odwołuje wizytę przed terminem" do
    given :visit_booked, %{
      patient_id: "patient-anna",
      service_id: "service-physiotherapy",
      specialist_id: "specialist-ewa",
      scheduled_at: "2026-10-05T09:00:00Z"
    }

    command :cancel_visit
    expect :visit_cancelled
  end

  scenario "pacjent już wyszedł z gabinetu — wizyty nie da się odwołać" do
    given :visit_booked, %{
      patient_id: "patient-anna",
      service_id: "service-physiotherapy",
      specialist_id: "specialist-ewa",
      scheduled_at: "2026-10-05T09:00:00Z"
    }

    given :visit_completed
    command :cancel_visit
    rejected :only_a_visit_not_yet_held_ends_early
  end

  scenario "pacjent był na wizycie — nie odnotowuje się nieobecności" do
    given :visit_booked, %{
      patient_id: "patient-anna",
      service_id: "service-physiotherapy",
      specialist_id: "specialist-ewa",
      scheduled_at: "2026-10-05T09:00:00Z"
    }

    given :patient_arrived
    command :record_no_show
    rejected :only_a_visit_not_yet_held_ends_early
  end
end
