defmodule Billing.Subscriptions do
  @moduledoc """
  **Invented.** The implementation of `Billing.Contracts.Subscriptions`: the
  subscription's and the invoice's decisions, which are pure, the monthly billing, and
  the policy that invoices a closed period.
  """

  use Boundary,
    deps: [EhOsContract, Billing.Contracts, Billing.Periods],
    exports: [Subscription, Invoice, MonthlyBilling, InvoiceThePeriod]
end
