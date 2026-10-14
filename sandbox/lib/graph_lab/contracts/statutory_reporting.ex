defmodule GraphLab.Contracts.StatutoryReporting do
  @moduledoc """
  **A copy of `Rehmed.Contracts.StatutoryReporting` changed to test the graph on; not client
  material** (`GraphLab`). Why each declaration is as it is, that module says.
  """

  use EhOsContract.Contract,
    domain: GraphLab.Domain,
    context: :statutory_reporting,
    id: "graph-lab.statutory_reporting"

  consumes GraphLab.Contracts.ClinicalDocumentation, :visit_closed_clinically

  aggregate :p1_report, "Zgłoszenie P1" do
    identity visit_id: {:id, :visit}

    # Both issued by the policy on the clinical close, never by a person.
    command :queue_p1_report, "Zakolejkuj zgłoszenie do P1",
      emits: :p1_report_queued,
      source: "P-07" do
      field :patient_id, :id, subject: :patient
      field :pesel, :string, personal: :patient_id
      field :icd10, :string, personal: :patient_id
      field :icd9, :string, personal: :patient_id
      field :practitioner_number, :id
    end

    command :waive_p1_report, "Pomiń zgłoszenie usługi niezgłaszanej do P1",
      emits: :p1_reporting_not_required,
      source: "P-07, warunek: usługa raportowana (AGG-15)"

    # `AGG-10`, state `Zakolejkowane`: the payload the registry will get.
    event :p1_report_queued, "Zgłoszenie P1 zakolejkowane", source: "AGG-10" do
      field :patient_id, :id, subject: :patient
      field :pesel, :string, personal: :patient_id
      field :icd10, :string, personal: :patient_id
      field :icd9, :string, personal: :patient_id
      field :practitioner_number, :id
    end

    # `E-54`, observed.
    event :p1_report_sent, "Wysłano informację do systemu P1",
      recorded_by: :p1_integration,
      depends_on: :p1,
      source: "E-54"

    # `AGG-10`'s error state: a rejection or no connection. Not an end: the
    # report is retried.
    event :p1_report_failed, "Zgłoszenie do P1 odrzucone albo nie doszło do rejestru",
      recorded_by: :p1_integration,
      depends_on: :p1,
      source: "AGG-10"

    event :p1_reporting_not_required, "Usługa nie podlega zgłoszeniu do P1", source: "H21, DEC-20"
  end

  policy :report_on_clinical_close,
         "Zamknięcie kliniczne — zgłoszenie do P1 albo jego pominięcie",
         handles: :visit_closed_clinically,
         issues: [:queue_p1_report, :waive_p1_report],
         delivery: :at_least_once,
         idempotency: [key: :event_id, owner: :infrastructure],
         source: "P-07" do
    # The service's flag decides, "one flag, not two" (2026-08-17, `AGG-15`).
    constraint :only_reported_services,
               "Do P1 zgłaszamy tylko zamknięcia usług raportowanych do P1; pozostałe pomijamy",
               source: "P-07"
  end

  effect :send_p1_report, "Wyślij zgłoszenie do rejestru P1",
    handles: :p1_report_queued,
    calls: {:p1, :submit_report},
    idempotency: [key: :event_id, owner: :downstream]

  scenario "fizjoterapia zamknięta klinicznie — zgłoszenie idzie do kolejki P1",
    illustrates: :only_reported_services do
    target :report_on_clinical_close

    on :visit_closed_clinically, %{
      patient_id: "patient-anna",
      pesel: "85010112345",
      icd10: "M54.5",
      icd9: "93.39",
      practitioner_number: "practitioner-ewa",
      p1_reported: true
    }

    issues :queue_p1_report, %{pesel: "85010112345", icd10: "M54.5"}
  end

  scenario "masaż zamknięty klinicznie — do P1 nic nie idzie",
    illustrates: :only_reported_services do
    target :report_on_clinical_close

    on :visit_closed_clinically, %{
      patient_id: "patient-anna",
      pesel: "85010112345",
      practitioner_number: "practitioner-ewa",
      p1_reported: false
    }

    issues :waive_p1_report
  end

  scenario "zgłoszenie kolejkowane z ładunkiem zamknięcia" do
    command :queue_p1_report, %{
      patient_id: "patient-anna",
      pesel: "85010112345",
      icd10: "M54.5",
      icd9: "93.39",
      practitioner_number: "practitioner-ewa"
    }

    expect :p1_report_queued, %{pesel: "85010112345"}
  end

  scenario "usługa niezgłaszana — zgłoszenie pominięte" do
    command :waive_p1_report
    expect :p1_reporting_not_required
  end
end
