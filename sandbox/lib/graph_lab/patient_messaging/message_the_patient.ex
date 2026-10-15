defmodule GraphLab.PatientMessaging.MessageThePatient do
  @moduledoc """
  The policy `message_the_patient`: one message per thing that happened to the visit —
  a reminder on the booking, a notice on the cancellation, a survey once the patient
  has left.
  """

  use GraphLab.Contracts.PatientMessaging, policy: :message_the_patient

  @impl true
  def visit_booked(%VisitBooked{visit_id: id}),
    do: issue(%QueueMessage{visit_id: id, kind: :reminder})

  @impl true
  def visit_cancelled(%VisitCancelled{visit_id: id}),
    do: issue(%QueueMessage{visit_id: id, kind: :cancellation})

  @impl true
  def patient_left(%PatientLeft{visit_id: id}),
    do: issue(%QueueMessage{visit_id: id, kind: :survey})
end
