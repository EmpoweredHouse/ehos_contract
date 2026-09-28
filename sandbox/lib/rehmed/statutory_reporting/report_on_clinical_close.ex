defmodule Rehmed.StatutoryReporting.ReportOnClinicalClose do
  @moduledoc """
  `P-07`: the clinical close of a service reported to P1 queues its report, with the
  payload the close carries; any other close waives it.
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
