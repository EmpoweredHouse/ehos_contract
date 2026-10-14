defmodule GraphLab.Scheduling.Visit do
  @moduledoc """
  Decides a visit's booking, its confirmation and its early ends (`AGG-01`), in the
  test set (`GraphLab`). Unlike `Rehmed.Scheduling.Visit` it refuses nothing itself: the
  lifecycle says in which statuses each command may be issued, and the engine refuses
  the others before this decision runs.
  """

  use GraphLab.Contracts.Scheduling, aggregate: :visit

  @impl true
  def book_visit(%BookVisit{} = booking, _state, %{service: service}) do
    emit(%VisitBooked{
      visit_id: booking.visit_id,
      patient_id: booking.patient_id,
      service_id: booking.service_id,
      specialist_id: booking.specialist_id,
      scheduled_at: booking.scheduled_at,
      p1_reported: service.p1_reported
    })
  end

  @impl true
  def confirm_visit(%ConfirmVisit{visit_id: id}, _state),
    do: emit(%PatientConfirmed{visit_id: id})

  @impl true
  def cancel_visit(%CancelVisit{visit_id: id}, _state), do: emit(%VisitCancelled{visit_id: id})

  @impl true
  def record_no_show(%RecordNoShow{visit_id: id}, _state), do: emit(%PatientNoShow{visit_id: id})
end
