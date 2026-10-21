defmodule Billing.Payments.CollectPayment do
  @moduledoc """
  **Invented.** Charges a requested payment through the gateway, after the request's
  transaction, and records what the gateway took as the integration.

  A gateway that answers it is unavailable is an outage, not a refused payment: the call
  is wrapped in `EhOsContract.Dependency.observe/3`, which records an observation of it,
  and the effect fails, so the payment is tried again. The request's identifier is the
  idempotency key of both the charge and the record, so a second delivery neither
  charges again nor records anything new: the gateway keeps it for the charge
  (`owner: :downstream`).
  """

  use Billing.Contracts.Payments, effect: :collect_payment

  alias Billing.Adapters.PaymentGateway
  alias Billing.Contracts.Payments
  alias Billing.Contracts.Payments.Events.Collected
  alias EhOsContract.{Actor, Dependency}

  @impl true
  def requested(%Requested{} = requested) do
    %Requested{subscription_id: id, period_id: period, amount: amount, __meta__: meta} = requested

    with {:ok, _charge} <-
           Dependency.observe(Payments, :payment_gateway, fn ->
             PaymentGateway.charge(id, amount, "payment:#{meta.id}")
           end),
         {:ok, _receipt} <-
           EhOsContract.record(
             Payments,
             %Collected{subscription_id: id, period_id: period, amount: amount},
             actor: Actor.system(:gateway_integration),
             idempotency_key: "payment-collected:#{meta.id}",
             causation_id: meta.id,
             correlation_id: meta.correlation_id
           ),
         do: :ok
  end
end
