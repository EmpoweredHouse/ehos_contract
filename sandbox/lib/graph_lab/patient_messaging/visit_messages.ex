defmodule GraphLab.PatientMessaging.VisitMessages do
  @moduledoc """
  Decides a visit's messages in the test set (`GraphLab`): each kind is queued once.
  """

  use GraphLab.Contracts.PatientMessaging, aggregate: :visit_messages

  @impl true
  def queue_message(%QueueMessage{visit_id: id, kind: kind}, %State{queued: queued}) do
    if kind in queued,
      do: reject(:one_message_of_a_kind),
      else: emit(%MessageQueued{visit_id: id, kind: kind})
  end

  @impl true
  def evolve(state, %MessageQueued{kind: kind}), do: %{state | queued: [kind | state.queued]}
  def evolve(state, _event), do: state
end
