defmodule GraphLab.ClinicalDocumentation.VisitDocumentation do
  @moduledoc """
  Decides the codes and the clinical close of a visit (`AGG-02`). A service
  reported to P1, by the flag recorded when the visit was booked, is refused a close
  without both codes, and a visit is closed once: each close queues a report
  to P1. Who may close it — the specialist the visit is booked with — the engine checks
  before this decision runs.
  """

  use GraphLab.Contracts.ClinicalDocumentation, dcb: :visit_documentation

  alias GraphLab.Contracts.Scheduling.Events.VisitBooked

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

  def close_visit_clinically(%CloseVisitClinically{icd10: nil}, %State{p1_reported: true}),
    do: reject(:codes_before_clinical_close)

  def close_visit_clinically(%CloseVisitClinically{icd9: nil}, %State{p1_reported: true}),
    do: reject(:codes_before_clinical_close)

  def close_visit_clinically(%CloseVisitClinically{} = close, %State{} = state) do
    emit(%VisitClosedClinically{
      visit_id: close.visit_id,
      patient_id: close.patient_id,
      pesel: close.pesel,
      icd10: close.icd10,
      icd9: close.icd9,
      practitioner_number: close.practitioner_number,
      p1_reported: state.p1_reported
    })
  end

  @impl true
  def create_documentation_overdue_task(%CreateDocumentationOverdueTask{visit_id: id}, _state),
    do: emit(%DocumentationOverdueTaskCreated{visit_id: id})

  @impl true
  def evolve(state, %VisitBooked{p1_reported: reported, specialist_id: specialist}),
    do: %{state | p1_reported: reported, specialist_id: specialist}

  def evolve(state, %VisitClosedClinically{}), do: %{state | closed: true}
  def evolve(state, _event), do: state
end
