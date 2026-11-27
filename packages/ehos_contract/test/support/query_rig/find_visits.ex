defmodule QueryRig.Visits do
  @moduledoc "**Invented.** A read model that keeps nothing: the query over it is here for its params."

  use QueryRig.Desk, read_model: :visits

  @impl true
  def visit_noted(_event), do: :ok
end

defmodule QueryRig.FindVisits do
  @moduledoc """
  **Invented.** Answers nothing, and tells the calling process the params it was asked
  with, `{:query_rig_params, params}`, so a test can compare two ways of asking.
  """

  use QueryRig.Desk, query: :find_visits

  @impl true
  def find_visits(%FindVisits{} = params, _ctx) do
    send(self(), {:query_rig_params, params})
    []
  end
end
