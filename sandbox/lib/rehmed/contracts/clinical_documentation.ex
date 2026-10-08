defmodule Rehmed.Contracts.ClinicalDocumentation do
  @moduledoc """
  Clinical documentation (`CTX-03`): the codes of a visit and the specialist's
  clinical close, which is what hands a medical event to statutory reporting. It
  declares no process: the visit's run spans booking, documentation and settlement
  (distillation, finding 1), so it belongs to none of the three contracts; its place
  is the process module (plan DD, P2b). `Rehmed.Processes.ClinicalVisit` includes the clinical close
  from here.

  Written from `AGG-02` in `2-Solution/20-aggregates.md` and process 2 of
  `docs/rehmed-2026-08-18-distillation.md` (v2 plan, E9), the best-evidenced process
  of the corpus: `E-41`, `E-42` and `E-44` are observed, not stated.

  ## The payload travels with the close

  The context map makes statutory reporting a conformist of this context: "ICD-10,
  ICD-9, PESEL, practitioner number; payload assembly on clinical close". So
  `visit_closed_clinically` carries what P1 needs, and whether the service is
  reported at all. The PESEL comes from the patient record, on the command. The flag
  comes from the catalogue (`AGG-15`, "one flag, not two"): scheduling records it on
  `visit_booked` when the visit is booked, and this boundary reads that event, so the
  specialist never says it (plan DD, A2 (#249)).

  **PESEL and the codes are the patient's personal data**, and so are sealed per
  patient (v2 §14). The distillation's hardest question stays open beside it:
  medical records are kept for twenty years by statute, so whether erasing a patient
  may shred them is the clinic's lawyer's answer, not the library's.

  ## The two gates

  `DEC-19`: a service reported to P1 closes clinically only with both codes. The close
  carries the codes and the booking the flag, so this is an invariant of the visit's
  documentation. It is a proposal and contradicts the room's 2026-08-13 decision
  ("remind, don't block"), so if it becomes a reminder this invariant goes.

  `AGG-02` invariant 3, **only the specialist who delivered the visit may close it**,
  is enforced today. The specialist who recorded the patient leaving is on
  `visit_completed`, given by the host from their credential, and the close names
  them with `actor_is`: the engine refuses any other specialist before the decision.
  Until plan DD, A2 (#249) the contract could not say it (the finding of E9a): a
  decision sees the command and the state, not who issued the command.

  ## Twenty-four hours

  The client decided on 2026-08-13 that a visit is closed within 24 hours of the
  patient leaving, deliberately inside the statutory 48 (the old watchdog fired at 48
  and was "a post-mortem, not a warning"). The chase is the process manager below:
  it starts on the patient leaving, from scheduling, and a day later creates the task
  unless the close came first. The task itself is work coordination's (`CTX-07`),
  which E9 does not write; the fact that it was created is this context's.
  """

  use EhOsContract.Contract,
    domain: Rehmed.Domain,
    context: :clinical_documentation,
    id: "rehmed.clinical_documentation"

  consumes Rehmed.Contracts.Scheduling, [:visit_booked, :visit_completed]

  # A boundary, not an aggregate (plan DD, A2 (#249)): what the close depends on was
  # recorded by scheduling — the service's P1 flag at booking (`AGG-15`), and who saw
  # the patient when they left — so the documentation reads those events of its visit
  # beside its own.
  dcb :visit_documentation, "Dokumentacja wizyty" do
    identity :visit_id

    consults :visit_booked, match: :visit_id
    consults :visit_completed, match: :visit_id

    state do
      field :closed, :boolean, default: false
      field :p1_reported, :boolean, optional: true
      field :specialist_id, :id, optional: true
    end

    # `AGG-02`'s clinical close is its final state, and each close queues a report to
    # P1: a second close would send the registry the same visit twice.
    invariant :closed_clinically_once, "Wizytę zamyka się klinicznie raz",
      source: "AGG-02, stan ZamkniętaKlinicznie"

    # Enforced by the clinic today; the engine compares the specialist who recorded the
    # patient leaving with whoever closes (`actor_is`).
    invariant :closed_by_its_specialist,
              "Wizytę zamyka klinicznie tylko specjalista, który ją wykonał",
              source: "AGG-02 niezmiennik 3, egzekwowane dziś"

    # The service's flag as it stood at booking, so a rule on the visit's state, not on
    # the command: the codes come with the close, the flag with the booking.
    invariant :codes_before_clinical_close,
              "Wizyta z usługą raportowaną do P1 zamyka się klinicznie dopiero z kodami ICD-10 i ICD-9",
              source: "AGG-02 niezmiennik 2, DEC-19 (propozycja)"

    command :code_diagnosis, "Wybierz kody ICD",
      by: :specialist,
      emits: :diagnosis_coded,
      source: "C-22, aktor A-03" do
      field :patient_id, :id, subject: :patient
      field :icd10, :string, personal: :patient_id
      field :icd9, :string, personal: :patient_id
    end

    # The codes come with the close, from the screen the specialist closes on; the state
    # could not hold them: a personal field folds under a patient the first event
    # names, and before it the state has no patient (F5). Whether the service is
    # reported is the booking's, in the state.
    command :close_visit_clinically, "Zamknij wizytę klinicznie",
      by: :specialist,
      emits: :visit_closed_clinically,
      rejects: [:closed_clinically_once, :closed_by_its_specialist, :codes_before_clinical_close],
      source: "C-29, aktor A-03" do
      actor_is(:specialist_id, or_rejects: :closed_by_its_specialist)

      field :patient_id, :id, subject: :patient
      field :pesel, :string, personal: :patient_id
      field :icd10, :string, personal: :patient_id, optional: true
      field :icd9, :string, personal: :patient_id, optional: true
      field :practitioner_number, :id
    end

    # Issued by the chase only, so no actor may.
    command :create_documentation_overdue_task, "Utwórz zadanie o zaległej dokumentacji",
      emits: :documentation_overdue_task_created,
      source: "P-23; decyzja klienta 2026-08-13"

    # `E-44`, observed; about two minutes per code on a paper cheat-sheet today.
    # Corrected codes are a new fact rather than an overwrite, which is what the
    # regulation's "data obtained later" path suggests (distillation, process 2).
    event :diagnosis_coded, "Wybrano ICD10 / ICD9", source: "E-44" do
      field :patient_id, :id, subject: :patient
      field :icd10, :string, personal: :patient_id
      field :icd9, :string, personal: :patient_id
    end

    event :documentation_overdue_task_created, "Utworzono zadanie o zaległej dokumentacji",
      source: "P-23, P-25; decyzja klienta 2026-08-13"

    # `E-52`, "triggers P1 dispatch". The codes are optional because a service that
    # is not reported closes without them.
    event :visit_closed_clinically, "Zamknięto wizytę przez specjalistę", source: "E-52" do
      field :patient_id, :id, subject: :patient
      field :pesel, :string, personal: :patient_id
      field :icd10, :string, personal: :patient_id, optional: true
      field :icd9, :string, personal: :patient_id, optional: true
      field :practitioner_number, :id
      field :p1_reported, :boolean
    end
  end

  process_manager :documentation_chase, "Pogoń za dokumentacją wizyty" do
    correlate :visit_id
    starts_on :visit_completed, sets: :documentation_due

    timer :documentation_due, "Termin dokumentacji",
      wait: {24, :hour},
      issues: :create_documentation_overdue_task

    ends_on :visit_closed_clinically
  end

  # A physiotherapy visit as scheduling booked it, and the close without codes.
  @physiotherapy %{
    patient_id: "patient-anna",
    service_id: "service-physiotherapy",
    specialist_id: "specialist-ewa",
    scheduled_at: "2026-10-05T09:00:00Z",
    p1_reported: true
  }
  @close %{
    patient_id: "patient-anna",
    pesel: "85010112345",
    practitioner_number: "practitioner-ewa"
  }

  scenario "fizjoterapeuta koduje rozpoznanie i procedurę" do
    command :code_diagnosis, %{patient_id: "patient-anna", icd10: "M54.5", icd9: "93.39"}
    expect :diagnosis_coded, %{icd10: "M54.5", icd9: "93.39"}
  end

  scenario "fizjoterapia z kodami — wizyta zamyka się klinicznie" do
    actor :specialist
    as "specialist-ewa"
    given :visit_booked, @physiotherapy
    given :visit_completed, %{specialist_id: "specialist-ewa"}
    command :close_visit_clinically, Map.merge(@close, %{icd10: "M54.5", icd9: "93.39"})
    expect :visit_closed_clinically, %{icd10: "M54.5", icd9: "93.39", p1_reported: true}
  end

  # `AGG-02` invariant 3: the specialist who saw the patient closes the visit, not a
  # colleague with the same permission.
  scenario "wizytę zamyka inny specjalista — zamknięcie odrzucone" do
    actor :specialist
    as "specialist-ola"
    given :visit_booked, @physiotherapy
    given :visit_completed, %{specialist_id: "specialist-ewa"}
    command :close_visit_clinically, Map.merge(@close, %{icd10: "M54.5", icd9: "93.39"})
    rejected :closed_by_its_specialist
  end

  scenario "fizjoterapia bez kodów — zamknięcie kliniczne odrzucone" do
    actor :specialist
    as "specialist-ewa"
    given :visit_booked, @physiotherapy
    given :visit_completed, %{specialist_id: "specialist-ewa"}
    command :close_visit_clinically, @close
    rejected :codes_before_clinical_close
  end

  # H21: beauty, fitness and the stable are never reported, so nothing gates them.
  scenario "usługa niezgłaszana do P1 zamyka się bez kodów" do
    actor :specialist
    as "specialist-ewa"
    given :visit_booked, %{@physiotherapy | service_id: "service-fitness", p1_reported: false}
    given :visit_completed, %{specialist_id: "specialist-ewa"}
    command :close_visit_clinically, @close
    expect :visit_closed_clinically, %{p1_reported: false}
  end

  scenario "wizyta już zamknięta klinicznie — drugie zamknięcie odrzucone" do
    actor :specialist
    as "specialist-ewa"
    given :visit_booked, %{@physiotherapy | service_id: "service-fitness", p1_reported: false}
    given :visit_completed, %{specialist_id: "specialist-ewa"}
    given :visit_closed_clinically, Map.put(@close, :p1_reported, false)
    command :close_visit_clinically, @close
    rejected :closed_clinically_once
  end

  scenario "doba po wyjściu pacjenta bez zamknięcia — zadanie o zaległej dokumentacji" do
    target :documentation_chase
    given :visit_completed, %{specialist_id: "specialist-ewa"}
    on :documentation_due
    issues :create_documentation_overdue_task
  end
end
