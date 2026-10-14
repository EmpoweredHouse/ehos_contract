defmodule GraphLab.Settlement.SettlementChase do
  @moduledoc """
  Eight hours after the patient leaves, flags the visit as unsettled, unless reception
  closed it first, in the test set (`GraphLab`).
  """

  use GraphLab.Contracts.Settlement, process_manager: :settlement_chase

  @impl true
  def settlement_due(%State{visit_id: id}), do: issue(%FlagUnsettledVisit{visit_id: id})
end
