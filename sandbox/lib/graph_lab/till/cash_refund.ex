defmodule GraphLab.Till.CashRefund do
  @moduledoc """
  Decides a cash refund in the test set (`GraphLab`): owed on the policy's word, paid
  out once. A second payout is refused by the lifecycle before this decision runs.
  """

  use GraphLab.Contracts.Till, aggregate: :cash_refund

  @impl true
  def owe_refund(%OweRefund{visit_id: id, amount: amount}, _state),
    do: emit(%RefundOwed{visit_id: id, amount: amount})

  @impl true
  def pay_out_refund(%PayOutRefund{visit_id: id}, _state), do: emit(%RefundPaidOut{visit_id: id})
end
