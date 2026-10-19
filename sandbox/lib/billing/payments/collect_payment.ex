defmodule Billing.Payments.CollectPayment do
  @moduledoc """
  **Invented.** Charges a requested payment through the gateway, after the request's
  transaction, and records what the gateway took as the integration.

  A gateway that answers it is unavailable is an outage, not a refused payment: the
  effect records an observation of it (`EhOsContract.Dependency`), at the moment the
  engine's clock says, and fails, so the payment is tried again. The request's
  identifier is the idempotency key, so a second delivery records nothing new.
  """

  use Billing.Contracts.Payments, effect: :collect_payment

  alias Billing.Adapters.PaymentGateway
  alias Billing.Contracts.Payments
  alias Billing.Contracts.Payments.Events.Collected
  alias EhOsContract.{Actor, Clock, Dependency}

  @impl true
  def requested(%Requested{} = requested) do
    %Requested{subscription_id: id, period_id: period, amount: amount, __meta__: meta} =
      requested

    case PaymentGateway.charge(id, amount) do
      {:ok, _charge} ->
        with {:ok, _receipt} <-
               EhOsContract.record(
                 Payments,
                 %Collected{subscription_id: id, period_id: period, amount: amount},
                 actor: Actor.system(:gateway_integration),
                 idempotency_key: "payment-collected:#{meta.id}",
                 causation_id: meta.id,
                 correlation_id: meta.correlation_id
               ),
             do: :ok

      {:error, :unavailable} = unavailable ->
        Dependency.unavailable!(
          Payments,
          :payment_gateway,
          "the gateway answered :unavailable",
          Clock.now()
        )

        unavailable
    end
  end
end
