defmodule Billing.Payments do
  @moduledoc """
  **Invented.** The implementation of `Billing.Contracts.Payments`: the payment's
  decision, which is pure, the policy that asks for a payment of each issued invoice,
  and the effect that charges it through the gateway.
  """

  use Boundary,
    deps: [EhosContract, Billing.Contracts, Billing.Adapters],
    exports: [Payment, RequestPaymentForInvoice, CollectPayment]
end
