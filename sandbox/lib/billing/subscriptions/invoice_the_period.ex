defmodule Billing.Subscriptions.InvoiceThePeriod do
  @moduledoc """
  **Invented.** Invoices a closed period in the transaction that closed it: the monthly
  fee, one line per usage record at the subscription's unit price, then the invoice.
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
            line_id: record.usage_id,
            amount: record.units * closed.unit_price
          }
        end
      )

    {:ok, invoice} = issue(%IssueInvoice{subscription_id: id, period_id: period})
    {:ok, fee ++ usage ++ invoice}
  end
end
