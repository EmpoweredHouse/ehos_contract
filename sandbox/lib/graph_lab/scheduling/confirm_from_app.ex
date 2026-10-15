defmodule GraphLab.Scheduling.ConfirmFromApp do
  @moduledoc """
  The policy `confirm_from_app`: the patient confirmed the visit in the patient app, so
  the visit is confirmed. A visit no longer waiting for it is refused by the lifecycle,
  and that refusal is the answer.
  """

  use GraphLab.Contracts.Scheduling, policy: :confirm_from_app

  @impl true
  def confirmed_in_app(%ConfirmedInApp{visit_id: id}), do: issue(%ConfirmVisit{visit_id: id})
end
