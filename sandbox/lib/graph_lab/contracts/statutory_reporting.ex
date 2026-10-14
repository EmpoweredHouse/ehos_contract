defmodule GraphLab.Contracts.StatutoryReporting do
  @moduledoc """
  **Part of the test set for drawing the graph; not client material** (`GraphLab`).

  Statutory reporting: the report a visit owes the medical events register. A policy
  queues it on the clinical close, or waives it for a service that is not reported; an
  effect sends it, and the register's integration records the answer. The report records
  only: none of its commands can be refused.
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
      field :pesel, :pesel, personal: :patient_id
      field :icd10, :string, personal: :patient_id
      field :icd9, :string, personal: :patient_id
      field :practitioner_number, :id
    end

    command :waive_p1_report, "Pomiń zgłoszenie usługi niezgłaszanej do P1",
      emits: :p1_reporting_not_required,
      source: "P-07, warunek: usługa raportowana (AGG-15)"

    # The payload the registry will get, queued (`AGG-10`).
    event :p1_report_queued, "Zgłoszenie P1 zakolejkowane", source: "AGG-10" do
      field :patient_id, :id, subject: :patient
      field :pesel, :pesel, personal: :patient_id
      field :icd10, :string, personal: :patient_id
      field :icd9, :string, personal: :patient_id
      field :practitioner_number, :id
    end

    event :p1_report_sent, "Wysłano informację do systemu P1",
      recorded_by: :p1_integration,
      depends_on: :p1,
      source: "E-54"

    # The report's error state, a rejection or no connection (`AGG-10`). Not an end: the
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
    # The service's flag decides, one flag for the service and its report (`AGG-15`).
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
