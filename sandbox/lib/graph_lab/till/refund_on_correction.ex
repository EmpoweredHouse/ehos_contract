defmodule GraphLab.Till.RefundOnCorrection do
  @moduledoc """
  The policy `refund_on_correction`: a settlement corrected downwards owes the patient
  the difference from the till. A correction upwards is the patient's to pay at the
  settlement, so the till owes nothing.
  """

  use GraphLab.Contracts.Till, policy: :refund_on_correction

  @impl true
  def settlement_corrected(%SettlementCorrected{visit_id: id, delta: delta}) when delta < 0,
    do: issue(%OweRefund{visit_id: id, amount: -delta})

  def settlement_corrected(%SettlementCorrected{}), do: issue([])
end
