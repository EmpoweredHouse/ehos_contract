defmodule Rehmed.StatutoryReporting.ReportOnClinicalClose do
  @moduledoc """
  The policy `report_on_clinical_close`. Its rule is the contract's constraint
  `only_reported_services` (`P-07`), which the callback's generated doc carries with
  the scenarios that illustrate it; the report is queued with the payload the close
  carries.
  """

  use Rehmed.Contracts.StatutoryReporting, policy: :report_on_clinical_close

  @impl true
  def visit_closed_clinically(%VisitClosedClinically{p1_reported: true} = close) do
    issue(%QueueP1Report{
      visit_id: close.visit_id,
      patient_id: close.patient_id,
      pesel: close.pesel,
      icd10: close.icd10,
      icd9: close.icd9,
      practitioner_number: close.practitioner_number
    })
  end

  def visit_closed_clinically(%VisitClosedClinically{visit_id: id}),
    do: issue(%WaiveP1Report{visit_id: id})
end
