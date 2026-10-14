defmodule GraphLab.Processes.PayerSettlement do
  @moduledoc """
  **Part of the test set for drawing the graph; not client material** (`GraphLab`).

  One external payer's month as one run: the visits charged to the payer, each marked
  settled with the payer or excluded with a reason, then the invoice. A month whose every
  charged visit was excluded has nothing to invoice, and never ends.
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
