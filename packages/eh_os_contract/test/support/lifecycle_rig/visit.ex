defmodule LifecycleRig.Visit do
  @moduledoc """
  **Invented.** The decider of `LifecycleRig.Visits`' visit. No callback reads the
  status to refuse: `from:` does that. `evolve/2` reads it, as it stood when each
  event happened, to count the notes taken before the patient arrived.
  """

  use LifecycleRig.Visits, aggregate: :visit

  @impl true
  def book_visit(%BookVisit{visit_id: id}, _state), do: emit(%Booked{visit_id: id})

  @impl true
  def admit_patient(%AdmitPatient{visit_id: id}, _state), do: emit(%PatientArrived{visit_id: id})

  @impl true
  def cancel_visit(%CancelVisit{visit_id: id}, _state), do: emit(%Cancelled{visit_id: id})

  @impl true
  def close_visit(%CloseVisit{visit_id: id}, %State{notes_before_arrival: notes}),
    do: emit(%Closed{visit_id: id, notes_before_arrival: notes})

  @impl true
  def add_note(%AddNote{visit_id: id}, _state), do: emit(%NoteAdded{visit_id: id})

  @impl true
  def reopen_visit(%ReopenVisit{visit_id: id}, _state), do: emit(%PatientArrived{visit_id: id})

  # Only a note is folded, so a scenario's other givens count for coverage only through
  # the lifecycle. A test can make it return a bare map,
  # `Process.put(:lifecycle_rig_evolve_returns_map, true)`, to see what dispatch says of
  # a state that is not one.
  @impl true
  def evolve(%State{} = state, %NoteAdded{}) do
    cond do
      Process.get(:lifecycle_rig_evolve_returns_map) -> Map.from_struct(state)
      state.status == :booked -> %{state | notes_before_arrival: state.notes_before_arrival + 1}
      true -> state
    end
  end

  def evolve(state, _event), do: state
end
