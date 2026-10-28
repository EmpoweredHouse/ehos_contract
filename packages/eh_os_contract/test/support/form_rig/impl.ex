defmodule FormRig.Period do
  @moduledoc "**Invented.** The check of `FormRig.Domain`'s value `:period`."

  use FormRig.Domain, value: :period

  @impl true
  def written_as_month(period), do: period =~ ~r/\A[0-9]{4}-(0[1-9]|1[0-2])\z/
end

defmodule FormRig.InvoiceDecider do
  @moduledoc "**Invented.** The decider of `FormRig.Invoicing`'s invoice: it issues what it is asked."

  use FormRig.Invoicing, aggregate: :invoice

  @impl true
  def issue_invoice(%IssueInvoice{} = c, _state),
    do:
      emit(%InvoiceIssued{
        invoice_id: c.invoice_id,
        period: c.period,
        amount: c.amount,
        lines: c.lines,
        method: c.method,
        due_on: c.due_on,
        paid: c.paid,
        sent_at: c.sent_at,
        note: c.note
      })
end
