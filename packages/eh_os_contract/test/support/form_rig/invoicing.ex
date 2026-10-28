defmodule FormRig.Invoicing do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  An accountant issues an invoice for a period. `issue_invoice` carries a field of every
  built-in type a form sends as text, and a period, a domain value with an invariant.
  """

  use EhOsContract.Contract,
    domain: FormRig.Domain,
    context: :invoicing,
    id: "form_rig.invoicing"

  aggregate :invoice, "Invoice" do
    identity :invoice_id

    command :issue_invoice, "Issue an invoice", by: :accountant, emits: :invoice_issued do
      field :period, :period
      field :amount, :decimal
      field :lines, :integer
      field :method, {:enum, [:card, :transfer]}
      field :due_on, :date
      field :paid, :boolean, optional: true
      field :sent_at, :timestamp, optional: true
      field :note, :string, optional: true
    end

    event :invoice_issued, "Invoice issued" do
      field :period, :period
      field :amount, :decimal
      field :lines, :integer
      field :method, {:enum, [:card, :transfer]}
      field :due_on, :date
      field :paid, :boolean, optional: true
      field :sent_at, :timestamp, optional: true
      field :note, :string, optional: true
    end
  end

  scenario "an accountant issues an invoice for a month" do
    command :issue_invoice, %{
      invoice_id: "i-1",
      period: "2026-07",
      amount: "120.50",
      lines: 2,
      method: :transfer,
      due_on: "2026-08-14"
    }

    expect :invoice_issued
  end
end
