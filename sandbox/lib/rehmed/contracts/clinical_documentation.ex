defmodule Rehmed.Contracts.ClinicalDocumentation do
  @moduledoc """
  Clinical documentation (`CTX-03`): the codes of a visit and the specialist's
  clinical close, which is what hands a medical event to statutory reporting.

  Written from `AGG-02` in `2-Solution/20-aggregates.md` and process 2 of
  `docs/rehmed-2026-08-18-distillation.md` (v2 plan, E9), the best-evidenced process
  of the corpus: `E-41`, `E-42` and `E-44` are observed, not stated.

  ## The payload travels with the close

  The context map makes statutory reporting a conformist of this context: "ICD-10,
  ICD-9, PESEL, practitioner number; payload assembly on clinical close". So
  `visit_closed_clinically` carries what P1 needs, and whether the service is
  reported at all. The PESEL comes from the patient record and the flag from the
  catalogue (`AGG-15`, "one flag, not two"); the application reads both and puts
  them on the command, because a decision reads no other context.

  **PESEL and the codes are the patient's personal data**, and so are sealed per
  patient (v2 §14). The distillation's hardest question stays open beside it:
  medical records are kept for twenty years by statute, so whether erasing a patient
  may shred them is the clinic's lawyer's answer, not the library's.

  ## The one gate, and the one that cannot be written

  `DEC-19`: a service reported to P1 closes clinically only with both codes. The close
  carries the codes, so this is a constraint on the command. It is a proposal and contradicts the room's 2026-08-13 decision ("remind, don't block"), so
  if it becomes a reminder this invariant goes.

  `AGG-02` invariant 3, **only the specialist who delivered the visit may close it**,
  is enforced today and is not here. A decision sees the command and the state, not
  who issued the command, and the capability says only that *a* specialist may close
  a visit. The finding is in the plan (E9a).

  ## Twenty-four hours

  The client decided on 2026-08-13 that a visit is closed within 24 hours of the
  patient leaving, deliberately inside the statutory 48 (the old watchdog fired at 48
  and was "a post-mortem, not a warning"). The chase is the process manager below:
  it starts on the patient leaving, from scheduling, and a day later creates the task
  unless the close came first. The task itself is work coordination's (`CTX-07`),
  which E9 does not write; the fact that it was created is this context's.
  """

  use EhOsContract.Contract, domain: Rehmed.Domain, context: :clinical_documentation

  consumes Rehmed.Contracts.Scheduling, :visit_completed

  aggregate :visit_documentation, "Dokumentacja wizyty" do
    identity :visit_id

    state do
      field :closed, :boolean, default: false
    end

    # `AGG-02`'s clinical close is its final state, and each close queues a report to
    # P1: a second close would send the registry the same visit twice.
    invariant :closed_clinically_once, "Wizytę zamyka się klinicznie raz",
      source: "AGG-02, stan ZamkniętaKlinicznie"

    command :code_diagnosis, "Wybierz kody ICD",
      by: :specialist,
      emits: :diagnosis_coded,
      source: "C-22, aktor A-03" do
      field :patient_id, :id, subject: :patient
      field :icd10, :string, personal: :patient_id
      field :icd9, :string, personal: :patient_id
    end

    # The codes come with the close, from the screen the specialist closes on, so the
    # rule is about the command's own fields: a constraint, not an invariant. The
    # state could not hold them: a personal field folds under a patient the first
    # event names, and before it the state has no patient (F5).
    command :close_visit_clinically, "Zamknij wizytę klinicznie",
      by: :specialist,
      emits: :visit_closed_clinically,
      rejects: [:closed_clinically_once, :codes_before_clinical_close],
      source: "C-29, aktor A-03" do
      field :patient_id, :id, subject: :patient
      field :pesel, :string, personal: :patient_id
      field :icd10, :string, personal: :patient_id, optional: true
      field :icd9, :string, personal: :patient_id, optional: true
      field :practitioner_number, :id
      # The service's P1 flag (`AGG-15`), not the specialist's to say: the host gives it
      # (plan T1s, `Rehmed.Supplier`).
      field :p1_reported, :boolean, supplied_by: :host

      constraint :codes_before_clinical_close,
                 "Wizyta z usługą raportowaną do P1 zamyka się klinicznie dopiero z kodami ICD-10 i ICD-9",
                 source: "AGG-02 niezmiennik 2, DEC-19 (propozycja)"
    end

    # Issued by the chase only, so no actor may.
    command :create_documentation_overdue_task, "Utwórz zadanie o zaległej dokumentacji",
      emits: :documentation_overdue_task_created,
      source: "P-23; decyzja klienta 2026-08-13"

    stage :documentation do
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
    end

    stage :closing do
      # `E-52`, "triggers P1 dispatch". The codes are optional because a service that
      # is not reported closes without them.
      event :visit_closed_clinically, "Zamknięto wizytę przez specjalistę",
        terminal: true,
        source: "E-52" do
        field :patient_id, :id, subject: :patient
        field :pesel, :string, personal: :patient_id
        field :icd10, :string, personal: :patient_id, optional: true
        field :icd9, :string, personal: :patient_id, optional: true
        field :practitioner_number, :id
        field :p1_reported, :boolean
      end
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

  process :visit_documentation,
          "Dokumentacja wizyty: od wyjścia pacjenta do zamknięcia klinicznego" do
    correlate :visit_id

    stage :departure do
      include :visit_completed
    end

    stage :documentation
    stage :closing
  end

  scenario "fizjoterapeuta koduje rozpoznanie i procedurę" do
    command :code_diagnosis, %{patient_id: "patient-anna", icd10: "M54.5", icd9: "93.39"}
    expect :diagnosis_coded, %{icd10: "M54.5", icd9: "93.39"}
  end

  scenario "fizjoterapia z kodami — wizyta zamyka się klinicznie" do
    command :close_visit_clinically, %{
      patient_id: "patient-anna",
      pesel: "85010112345",
      icd10: "M54.5",
      icd9: "93.39",
      practitioner_number: "practitioner-ewa",
      p1_reported: true
    }

    expect :visit_closed_clinically, %{icd10: "M54.5", icd9: "93.39", p1_reported: true}
  end

  scenario "fizjoterapia bez kodów — zamknięcie kliniczne odrzucone" do
    command :close_visit_clinically, %{
      patient_id: "patient-anna",
      pesel: "85010112345",
      practitioner_number: "practitioner-ewa",
      p1_reported: true
    }

    rejected :codes_before_clinical_close
  end

  # H21: beauty, fitness and the stable are never reported, so nothing gates them.
  scenario "usługa niezgłaszana do P1 zamyka się bez kodów" do
    command :close_visit_clinically, %{
      patient_id: "patient-anna",
      pesel: "85010112345",
      practitioner_number: "practitioner-ewa",
      p1_reported: false
    }

    expect :visit_closed_clinically, %{p1_reported: false}
  end

  scenario "wizyta już zamknięta klinicznie — drugie zamknięcie odrzucone" do
    given :visit_closed_clinically, %{
      patient_id: "patient-anna",
      pesel: "85010112345",
      practitioner_number: "practitioner-ewa",
      p1_reported: false
    }

    command :close_visit_clinically, %{
      patient_id: "patient-anna",
      pesel: "85010112345",
      practitioner_number: "practitioner-ewa",
      p1_reported: false
    }

    rejected :closed_clinically_once
  end

  scenario "doba po wyjściu pacjenta bez zamknięcia — zadanie o zaległej dokumentacji" do
    target :documentation_chase
    given :visit_completed
    on :documentation_due
    issues :create_documentation_overdue_task
  end
end
