defmodule GraphLab.ClinicalDocumentation.VisitNote do
  @moduledoc "Records a visit's note in the test set (`GraphLab`); nothing refuses it."

  use GraphLab.Contracts.ClinicalDocumentation, aggregate: :visit_note

  @impl true
  def write_note(%WriteNote{} = note, _state) do
    emit(%NoteWritten{visit_id: note.visit_id, patient_id: note.patient_id, text: note.text})
  end
end
