defmodule Rehmed.ClinicalDocumentation.VisitDocumentation do
  @moduledoc """
  Decides the codes and the clinical close of a visit (`AGG-02`). A service
  reported to P1 is refused a close without both codes (`DEC-19`), and a visit is
  closed once: each close queues a report to P1.
  """

  use Rehmed.Contracts.ClinicalDocumentation, aggregate: :visit_documentation

  @impl true
  def code_diagnosis(%CodeDiagnosis{} = coding, _state) do
    emit(%DiagnosisCoded{
      visit_id: coding.visit_id,
      patient_id: coding.patient_id,
      icd10: coding.icd10,
      icd9: coding.icd9
    })
  end

  @impl true
  def close_visit_clinically(_close, %State{closed: true}), do: reject(:closed_clinically_once)

  def close_visit_clinically(%CloseVisitClinically{p1_reported: true, icd10: nil}, _state),
    do: reject(:codes_before_clinical_close)

  def close_visit_clinically(%CloseVisitClinically{p1_reported: true, icd9: nil}, _state),
    do: reject(:codes_before_clinical_close)

  def close_visit_clinically(%CloseVisitClinically{} = close, _state) do
    emit(%VisitClosedClinically{
      visit_id: close.visit_id,
      patient_id: close.patient_id,
      pesel: close.pesel,
      icd10: close.icd10,
      icd9: close.icd9,
      practitioner_number: close.practitioner_number,
      p1_reported: close.p1_reported
    })
  end

  @impl true
  def create_documentation_overdue_task(%CreateDocumentationOverdueTask{visit_id: id}, _state),
    do: emit(%DocumentationOverdueTaskCreated{visit_id: id})

  @impl true
  def evolve(state, %VisitClosedClinically{}), do: %{state | closed: true}
  def evolve(state, _event), do: state
end
