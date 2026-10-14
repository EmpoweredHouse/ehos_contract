defmodule GraphLab.Contracts.ClinicalDocumentation do
  @moduledoc """
  **A copy of `Rehmed.Contracts.ClinicalDocumentation` changed to test the graph on; not client
  material** (`GraphLab`). Why each declaration is as it is, that module says.
  """

  use EhOsContract.Contract,
    domain: GraphLab.Domain,
    context: :clinical_documentation,
    id: "graph-lab.clinical_documentation"

  consumes GraphLab.Contracts.Scheduling, [:visit_booked, :visit_completed]

  # A boundary, not an aggregate (plan DD, A2 (#249)): what the close depends on was
  # recorded by scheduling when the visit was booked — the service's P1 flag (`AGG-15`)
  # and the specialist the visit is booked with — so the documentation reads that event
  # of its visit beside its own. The specialist comes from reception's booking, not from
  # anything a specialist records: a colleague could record the patient leaving, but not
  # rebook the visit.
  dcb :visit_documentation, "Dokumentacja wizyty" do
    identity visit_id: {:id, :visit}

    consults :visit_booked, match: :visit_id

    state do
      field :closed, :boolean, default: false
      field :p1_reported, :boolean, optional: true
      field :specialist_id, :id, optional: true
    end

    # `AGG-02`'s clinical close is its final state, and each close queues a report to
    # P1: a second close would send the registry the same visit twice.
    invariant :closed_clinically_once, "Wizytę zamyka się klinicznie raz",
      source: "AGG-02, stan ZamkniętaKlinicznie"

    # Enforced by the clinic today; the engine compares the specialist the visit is
    # booked with and whoever closes (`actor_is`). With no booking, nobody is named, and
    # every close is refused.
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
    command :close_visit_clinically, Map.merge(@close, %{icd10: "M54.5", icd9: "93.39"})
    expect :visit_closed_clinically, %{icd10: "M54.5", icd9: "93.39", p1_reported: true}
  end

  # `AGG-02` invariant 3: the specialist who saw the patient closes the visit, not a
  # colleague with the same permission.
  scenario "wizytę zamyka inny specjalista — zamknięcie odrzucone" do
    actor :specialist
    as "specialist-ola"
    given :visit_booked, @physiotherapy
    command :close_visit_clinically, Map.merge(@close, %{icd10: "M54.5", icd9: "93.39"})
    rejected :closed_by_its_specialist
  end

  scenario "fizjoterapia bez kodów — zamknięcie kliniczne odrzucone" do
    actor :specialist
    as "specialist-ewa"
    given :visit_booked, @physiotherapy
    command :close_visit_clinically, @close
    rejected :codes_before_clinical_close
  end

  # H21: beauty, fitness and the stable are never reported, so nothing gates them.
  scenario "usługa niezgłaszana do P1 zamyka się bez kodów" do
    actor :specialist
    as "specialist-ewa"
    given :visit_booked, %{@physiotherapy | service_id: "service-fitness", p1_reported: false}
    command :close_visit_clinically, @close
    expect :visit_closed_clinically, %{p1_reported: false}
  end

  scenario "wizyta już zamknięta klinicznie — drugie zamknięcie odrzucone" do
    actor :specialist
    as "specialist-ewa"
    given :visit_booked, %{@physiotherapy | service_id: "service-fitness", p1_reported: false}
    given :visit_closed_clinically, Map.put(@close, :p1_reported, false)
    command :close_visit_clinically, @close
    rejected :closed_clinically_once
  end

  scenario "doba po wyjściu pacjenta bez zamknięcia — zadanie o zaległej dokumentacji" do
    target :documentation_chase
    given :visit_completed
    on :documentation_due
    issues :create_documentation_overdue_task
  end
end
