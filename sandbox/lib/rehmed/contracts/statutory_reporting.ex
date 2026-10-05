defmodule Rehmed.Contracts.StatutoryReporting do
  @moduledoc """
  Statutory reporting (`CTX-04`): the medical event a visit owes the national
  registry, and the promise that it gets there within the statutory two days.

  Written from `AGG-10` in `2-Solution/20-aggregates.md` and process 3 of
  `docs/rehmed-2026-08-18-distillation.md` (v2 plan, E9), which calls it the process
  worth a contract first: a deadline set by regulation, a defined payload, a defined
  failure, and a state nobody can see today.

  ## The run crosses three contexts

  `process :clinical_visit` is the distillation's finding 1 made legal: the visit is
  one run, from the patient leaving (scheduling, `E-51`) through the clinical close
  (documentation, `E-52`) to the report. v1 had to write it as one contract that
  declared all of those events; here each context declares its own, and this one
  includes the other two's.

  ## Two days from what

  The regulation (Dz.U. 2025 poz. 866) counts two days **from the end of the
  service**, not from the documentation, and the system sends on the clinical close
  (`P-07`), which can lag by days ("sixteen visits not closed"). A promise anchored on
  the close would report green while the clinic breaks the law, so it is anchored on
  `visit_completed` (the distillation's recommendation). Whether "the end of the
  service" is the patient leaving is still for a lawyer or the P1 documentation.

  ## A visit that owes nothing

  Beauty, fitness and the stable are not reported (`H21`, `DEC-20`): the flag is on
  the service. The model has no event for that — the report is simply never created
  — but a promise is per run, and every visit is a run, so without a fact every
  massage would breach the statute. `p1_reporting_not_required` is that fact, and the
  promise's `or_else`. It is ours, not the client's word, and says so here.

  ## The registry's answer

  `AGG-10` has no commands: the report is queued by policy on the clinical close and
  sent by an effect, and what the registry answers is recorded by the integration
  (D6) — sent (`E-54`, observed), or rejected (its error state). The outage is `X-01`'s, and
  a promise whose window saw the registry unavailable is suspended rather than
  breached. The regulation's own rule is different — three days from the end of the
  outage — and suspension only approximates it (distillation, finding 3). Whether
  "sent" is also "accepted" is `H64`, open. The retry (`S-46`) and the statutory
  overdue state are not written: the promise's breach is that state.
  """

  use EhOsContract.Contract, domain: Rehmed.Domain, context: :statutory_reporting

  consumes Rehmed.Contracts.Scheduling, :visit_completed
  consumes Rehmed.Contracts.ClinicalDocumentation, :visit_closed_clinically

  aggregate :p1_report, "Zgłoszenie P1" do
    identity :visit_id

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

    stage :reporting do
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
        terminal: true,
        source: "E-54"

      # `AGG-10`'s error state: a rejection or no connection. Not an end: the
      # report is retried.
      event :p1_report_failed, "Zgłoszenie do P1 odrzucone albo nie doszło do rejestru",
        recorded_by: :p1_integration,
        depends_on: :p1,
        source: "AGG-10"

      event :p1_reporting_not_required, "Usługa nie podlega zgłoszeniu do P1",
        terminal: true,
        source: "H21, DEC-20"
    end
  end

  policy :report_on_clinical_close,
         "Zamknięcie kliniczne — zgłoszenie do P1 albo jego pominięcie",
         handles: :visit_closed_clinically,
         issues: [:queue_p1_report, :waive_p1_report],
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

  # The old watchdog "notified the manager at the moment the deadline had already
  # passed" (distillation, process 3), and overdue work surfaces to the manager as a
  # count (`P-25`): the manager is who a breach is addressed to.
  process :clinical_visit, "Wizyta: wykonanie, dokumentacja i zgłoszenie zdarzenia medycznego",
    accountable: :manager do
    correlate :visit_id

    stage :departure do
      include :visit_completed
    end

    stage :closing do
      include :visit_closed_clinically
    end

    stage :reporting

    promise :medical_event_reported_within_statutory_window do
      from :visit_completed
      eventually :p1_report_sent
      within {2, :day}
      or_else :p1_reporting_not_required
      source "Dz.U. 2025 poz. 866"
    end
  end

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
