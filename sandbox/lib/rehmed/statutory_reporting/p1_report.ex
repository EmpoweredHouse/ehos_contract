defmodule Rehmed.StatutoryReporting.P1Report do
  @moduledoc "Decides a report's queueing and its waiver (`AGG-10`); neither can be refused."

  use Rehmed.Contracts.StatutoryReporting, aggregate: :p1_report

  @impl true
  def queue_p1_report(%QueueP1Report{} = report, _state) do
    emit(%P1ReportQueued{
      visit_id: report.visit_id,
      patient_id: report.patient_id,
      pesel: report.pesel,
      icd10: report.icd10,
      icd9: report.icd9,
      practitioner_number: report.practitioner_number
    })
  end

  @impl true
  def waive_p1_report(%WaiveP1Report{visit_id: id}, _state),
    do: emit(%P1ReportingNotRequired{visit_id: id})
end
