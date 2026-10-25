defmodule Billing.Contracts.Payments do
  @moduledoc """
  **Invented.** Payments: what is collected for each invoice.

  An issued invoice asks for its payment, after the invoice's transaction: a reaction
  to another context's event says when it runs (`delivery: :at_least_once`). The
  payment is then charged through the payment gateway, by an effect. The gateway may
  be down. The effect reports that as an outage of the gateway, fails, and is tried
  again, and the integration records the payment once the gateway takes it. A payment
  the gateway never takes is written off by the account manager. A write-off while an
  attempt is still to come does not stop that attempt: a payment the gateway takes after
  its write-off is recorded collected all the same, and refunding it is the account
  manager's.
  """

  use EhOsContract.Contract,
    domain: Billing.Domain,
    context: :payments,
    id: "billing.payments"

  consumes Billing.Contracts.Subscriptions, :issued

  aggregate :payment, "Payment" do
    identity [:subscription_id, period_id: :billing_period]

    state do
      field :requested, :boolean, default: false
      field :settled, :boolean, default: false
    end

    invariant :requested_once, "A payment is asked for once"
    invariant :only_an_unpaid_payment_is_written_off, "Only a payment still owed is written off"

    command :request_payment, "Ask for a payment",
      emits: :requested,
      rejects: :requested_once do
      field :amount, :money
    end

    command :write_off_payment, "Write a payment off",
      by: :account_manager,
      emits: :written_off,
      rejects: :only_an_unpaid_payment_is_written_off

    event :requested, "Payment requested" do
      field :amount, :money
    end

    event :collected, "Payment collected",
      recorded_by: :gateway_integration,
      depends_on: :payment_gateway do
      field :amount, :money
    end

    event :written_off, "Payment written off"
  end

  policy :request_payment_for_invoice, "Ask for the payment of an issued invoice",
    handles: :issued,
    issues: :request_payment,
    delivery: :at_least_once,
    idempotency: [key: :event_id, owner: :infrastructure]

  effect :collect_payment, "Charge the customer through the gateway",
    handles: :requested,
    calls: {:payment_gateway, :charge},
    idempotency: [key: :event_id, owner: :downstream]

  @requested %{subscription_id: "sub-1", period_id: "2026-01", amount: 2_200}

  scenario "an issued invoice asks for its payment" do
    target :request_payment_for_invoice
    on :issued, %{subscription_id: "sub-1", period_id: "2026-01", total: 2_200}
    issues :request_payment, %{subscription_id: "sub-1", period_id: "2026-01", amount: 2_200}
  end

  scenario "a payment is asked for" do
    command :request_payment, @requested
    expect :requested, %{amount: 2_200}
  end

  scenario "a payment is asked for once" do
    given :requested, @requested
    command :request_payment, %{amount: 2_200}
    rejected :requested_once
  end

  scenario "a payment the gateway never took is written off" do
    given :requested, @requested
    command :write_off_payment
    expect :written_off
  end

  scenario "a payment collected is not written off" do
    given :requested, @requested
    given :collected, %{amount: 2_200}
    command :write_off_payment
    rejected :only_an_unpaid_payment_is_written_off
  end

  scenario "the gateway records a payment it collected" do
    actor :gateway_integration
    given :requested, @requested
    record :collected, %{amount: 2_200}
    expect :collected, %{amount: 2_200}
  end

  scenario "the gateway cannot record a negative amount collected" do
    actor :gateway_integration
    given :requested, @requested
    record :collected, %{amount: -1}
    rejected :not_negative
  end
end
