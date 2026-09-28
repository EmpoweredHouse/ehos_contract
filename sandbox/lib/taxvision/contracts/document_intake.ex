defmodule Taxvision.Contracts.DocumentIntake do
  @moduledoc """
  Document intake (03 §4.3, supporting), as far as matching needs it: the invoices
  KSeF gives a company, recorded by the integration that pulls them.

  Written on 28 September 2026 (v2 plan, E9c-2) from `03-ddd-architecture.md` §4.3
  and phase 3.2 of `02-event-storming.md`, whose event name this is. The rest of
  the context — the client accepting or rejecting an invoice, documents from
  outside KSeF, deduplication, categories — has no reader in E9 and is not here
  (plan, the decisions before E9c-2: only what the DSL's kinds do not yet have on a
  real contract).

  ## The number is KSeF's

  `ksef_number` is given by KSeF, not by TaxVision (`issued_by: :ksef`), and held to
  its format by the domain's value, since a number read from a PDF can lose a digit
  (02 §3.2).
  """

  use EhOsContract.Next.Contract, domain: Taxvision.Domain, context: :document_intake

  aggregate :ksef_inbox, "Faktury firmy z KSeF" do
    identity :company_id

    # The period the invoice is settled in, which the integration works out; pulled
    # in the month before it is booked (WF 01:17:14).
    event :invoice_pulled_from_ksef, "Pobrano fakturę z KSeF",
      recorded_by: :ksef_integration,
      depends_on: :ksef,
      source: "02 §3.2 InvoicePulledFromKSeF; WF 01:17:14" do
      field :period_id, :period
      field :ksef_number, :ksef_number, issued_by: :ksef
      field :amount_minor, :integer
      field :issued_on, :date
    end
  end

  process :ksef_intake, "Pobieranie faktur z KSeF", accountable: :accountant do
    correlate :company_id
  end
end
