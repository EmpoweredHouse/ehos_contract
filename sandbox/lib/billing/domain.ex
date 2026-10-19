defmodule Billing.Domain do
  @moduledoc """
  The vocabulary of subscription billing: subscriptions, billed once a month with the
  usage they recorded, and payments, collected through a payment gateway.
  """

  use EhOsContract.Domain, name: :billing, language: :en
  use Boundary, deps: [EhOsContract], exports: [{Values, []}]

  subdomain :core, "Billing", type: :core
  subdomain :generic, "Payments", type: :generic

  context :subscriptions, "Subscriptions", subdomain: :core do
    term "Subscription", definition: "A customer's plan, billed every month until cancelled"
    term "Usage", definition: "Units a subscription consumed, billed at the next close"
    term "Invoice", definition: "What a subscription owes for one billing period"
    term "Period", definition: "A calendar month, named YYYY-MM"
  end

  context :payments, "Payments", subdomain: :generic do
    term "Payment", definition: "What is collected for one invoice"
  end

  # Payments collects what subscriptions invoiced, and conforms to the gateway it
  # charges through.
  relation :customer_supplier, upstream: :subscriptions, downstream: :payments
  relation :conformist, upstream: :payment_gateway, downstream: :payments

  actor :account_manager, :human, "Account manager"

  actor :gateway_integration, :system, "Payment gateway integration",
    backed_by: :payment_gateway,
    context: :payments

  external :payment_gateway, "Payment gateway",
    direction: :bidirectional,
    unavailable_looks_like: "the gateway answers that it is unavailable, or does not answer" do
    operation :charge, "Charge a customer's card"
  end

  # A billing period is named by its month, and the name is its identifier: the timer
  # that closes a period works the next one out itself.
  value :billing_period, :id, label: "Billing period" do
    invariant :named_by_month, "A billing period is a month written YYYY-MM",
      violated_by: ["2026-7", "2026-13", "July 2026", "2026-07-01"],
      satisfied_by: ["2026-07", "2026-12"]
  end

  value :money, :integer, unit: :cents, label: "Amount"

  value :usage_record, label: "Usage record" do
    field :usage_id, :id
    field :units, :integer
  end
end
