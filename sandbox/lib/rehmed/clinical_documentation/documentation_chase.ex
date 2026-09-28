defmodule Rehmed.ClinicalDocumentation.DocumentationChase do
  @moduledoc """
  A day after the patient leaves, creates the overdue-documentation task, unless the
  visit was closed clinically first (client decision, 2026-08-13).
  """

  use Rehmed.Contracts.ClinicalDocumentation, process_manager: :documentation_chase

  @impl true
  def documentation_due(%State{visit_id: id}),
    do: issue(%CreateDocumentationOverdueTask{visit_id: id})
end
