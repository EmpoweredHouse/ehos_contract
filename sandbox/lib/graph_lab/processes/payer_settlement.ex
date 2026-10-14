defmodule GraphLab.Processes.PayerSettlement do
  @moduledoc """
  **A copy of `Rehmed.Processes.PayerSettlement` changed to test the graph on; not client
  material** (`GraphLab`). Why each declaration is as it is, that module says.
  """

  use EhOsContract.Process,
    id: "graph-lab.payer_settlement",
    domain: GraphLab.Domain,
    label: "Miesięczne rozliczenie z płatnikiem zewnętrznym",
    accountable: :manager

  correlate [:payer_id, :period_id]

  stage :charging, include: [{GraphLab.Contracts.Settlement, :visit_charged_to_payer}]

  stage :reconciliation,
    include: [
      {GraphLab.Contracts.ExternalPayers,
       [:visit_marked_settled_with_payer, :visit_excluded_from_invoice]}
    ]

  stage :invoicing, include: [{GraphLab.Contracts.ExternalPayers, :payer_invoice_issued}]

  ends_on :payer_invoice_issued
end
