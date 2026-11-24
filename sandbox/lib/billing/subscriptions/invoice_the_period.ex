defmodule Billing.Subscriptions.InvoiceThePeriod do
  @moduledoc """
  **Invented.** Invoices a closed period in the transaction that closed it: the monthly
  fee, one line per usage record at the subscription's unit price, then the invoice. A
  usage line's id is the record's prefixed with `usage:`, so no record can share the
  fee's.

  It is the shape `mix ehos_contract.check` warns of (`in-transaction-policy-fan-out`):
  every line is decided while the application's append lock is held, so a period with
  many records holds every other append. A host billing at volume delivers it
  `:at_least_once`; this one is in the transaction so that the warning has a real
  implementation to report.
  Each `issue/1` answers `{:ok, commands}`, so the three are issued in that order as one
  list.
  """

  use Billing.Contracts.Subscriptions, policy: :invoice_the_period

  @impl true
  def billing_period_closed(%BillingPeriodClosed{subscription_id: id, period_id: period} = closed) do
    {:ok, fee} =
      issue(%AddInvoiceLine{
        subscription_id: id,
        period_id: period,
        line_id: "fee",
        amount: closed.monthly_fee
      })

    {:ok, usage} =
      issue(
        for record <- closed.usage do
          %AddInvoiceLine{
            subscription_id: id,
            period_id: period,
            line_id: "usage:" <> record.usage_id,
            amount: record.units * closed.unit_price
          }
        end
      )

    {:ok, invoice} = issue(%IssueInvoice{subscription_id: id, period_id: period})
    {:ok, fee ++ usage ++ invoice}
  end
end
