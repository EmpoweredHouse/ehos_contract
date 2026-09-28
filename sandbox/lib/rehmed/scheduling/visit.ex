defmodule Rehmed.Scheduling.Visit do
  @moduledoc """
  Decides a visit's booking and its early ends (`AGG-01`). A cancellation or a
  no-show is refused once the patient has arrived or left: `AGG-01` reaches
  `Odwołana` and `Nieobecność` only from the states before `Obecny`.
  """

  use Rehmed.Contracts.Scheduling, aggregate: :visit

  @impl true
  def book_visit(%BookVisit{} = booking, _state) do
    emit(%VisitBooked{
      visit_id: booking.visit_id,
      patient_id: booking.patient_id,
      service_id: booking.service_id,
      specialist_id: booking.specialist_id,
      scheduled_at: booking.scheduled_at
    })
  end

  @impl true
  def cancel_visit(%CancelVisit{visit_id: id}, %State{ended: false}),
    do: emit(%VisitCancelled{visit_id: id})

  def cancel_visit(_command, _state), do: reject(:only_a_visit_not_yet_held_ends_early)

  @impl true
  def record_no_show(%RecordNoShow{visit_id: id}, %State{ended: false}),
    do: emit(%PatientNoShow{visit_id: id})

  def record_no_show(_command, _state), do: reject(:only_a_visit_not_yet_held_ends_early)

  # Arriving is the end of "not yet held" as much as leaving is: a no-show after an
  # arrival is the error `AGG-01` rules out.
  @impl true
  def evolve(state, %PatientArrived{}), do: %{state | ended: true}
  def evolve(state, %VisitCompleted{}), do: %{state | ended: true}
  def evolve(state, %VisitCancelled{}), do: %{state | ended: true}
  def evolve(state, %PatientNoShow{}), do: %{state | ended: true}
  def evolve(state, _booked), do: state
end
