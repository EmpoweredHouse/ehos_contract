defmodule Billing.Payments.RequestPaymentForInvoice do
  @moduledoc "**Invented.** Asks for the payment of each issued invoice, for its total."

  use Billing.Contracts.Payments, policy: :request_payment_for_invoice

  @impl true
  def issued(%Issued{subscription_id: id, period_id: period, total: total}),
    do: issue(%RequestPayment{subscription_id: id, period_id: period, amount: total})
end
