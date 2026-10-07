defmodule Rehmed.Processes.PayerSettlement do
  @moduledoc """
  The monthly settlement with an external payer as one run (plan DD, P2f, #222):
  the visits settlement charges to the payer in the period (`CTX-05`), each marked
  settled with the payer or excluded with a reason, then the invoice (`E-87`). Until
  P2f it was `:payer_settlement` inside `Rehmed.Contracts.ExternalPayers`, whose
  moduledoc holds the invariant over the period and what is left out.

  One run is one payer in one month; LuxMed, Enelmed and TuZdrowie settle
  independently and identically (2026-08-14). Once a month the practice manager
  opens the module, verifies and invoices: human-initiated, and nothing here starts
  a run on a schedule. A month whose every charged visit was excluded has nothing to
  invoice and so never ends.
  """

  use EhOsContract.Process,
    id: "rehmed.payer_settlement",
    domain: Rehmed.Domain,
    label: "Miesięczne rozliczenie z płatnikiem zewnętrznym",
    accountable: :manager

  correlate [:payer_id, :period_id]

  stage :charging, include: [{Rehmed.Contracts.Settlement, :visit_charged_to_payer}]

  stage :reconciliation,
    include: [
      {Rehmed.Contracts.ExternalPayers,
       [:visit_marked_settled_with_payer, :visit_excluded_from_invoice]}
    ]

  stage :invoicing, include: [{Rehmed.Contracts.ExternalPayers, :payer_invoice_issued}]

  ends_on :payer_invoice_issued
end
