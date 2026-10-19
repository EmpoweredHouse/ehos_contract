defmodule Billing.Processes.Month do
  @moduledoc """
  **Invented.** One subscription's billing month, across subscriptions and payments:
  the period closed, its invoice issued, and its payment asked for and collected or
  written off.

  It has no end and no deadline. A month is never finished in the sense the process
  could count: a payment collected can still be disputed, and a written-off one paid
  later, by people this model does not cover. What the company does promise is that an
  issued invoice is collected, or written off, within three days. The gateway it is
  collected through may be down, and a month whose window saw it down is suspended, not
  broken.
  """

  use EhOsContract.Process,
    id: "billing.month",
    domain: Billing.Domain,
    label: "A subscription's billing month",
    accountable: :account_manager

  correlate [:subscription_id, :period_id]

  stage :closing, "Closing",
    include: [{Billing.Contracts.Subscriptions, [:billing_period_closed, :line_added, :issued]}]

  stage :collection, "Collection",
    include: [
      {Billing.Contracts.Payments, [:requested, :collected, :written_off]}
    ]

  promise :collected_within_three_days do
    from :issued
    eventually :collected
    within {3, :day}
    or_else :written_off
  end

  @issued %{subscription_id: "sub-1", period_id: "2026-09", total: 2_200}

  scenario "collected the next day — kept", verdict: :satisfied, via: :eventually do
    given :issued, @issued, at: "2026-10-01T00:05:00Z"

    given :collected, %{subscription_id: "sub-1", period_id: "2026-09", amount: 2_200},
      at: "2026-10-02T09:00:00Z"

    promise :collected_within_three_days, at: "2026-10-10T00:00:00Z"
  end

  scenario "written off — kept the other way", verdict: :satisfied, via: :or_else do
    given :issued, @issued, at: "2026-10-01T00:05:00Z"

    given :written_off, %{subscription_id: "sub-1", period_id: "2026-09"},
      at: "2026-10-03T09:00:00Z"

    promise :collected_within_three_days, at: "2026-10-10T00:00:00Z"
  end

  scenario "nothing in three days — broken", verdict: :violated do
    given :issued, @issued, at: "2026-10-01T00:05:00Z"
    promise :collected_within_three_days, at: "2026-10-05T00:00:00Z"
  end

  scenario "the gateway down inside the window — suspended", verdict: :suspended do
    given :issued, @issued, at: "2026-10-01T00:05:00Z"
    outage :payment_gateway, at: "2026-10-02T10:00:00Z"
    promise :collected_within_three_days, at: "2026-10-05T00:00:00Z"
  end

  scenario "a day after the invoice — still running", verdict: :pending do
    given :issued, @issued, at: "2026-10-01T00:05:00Z"
    promise :collected_within_three_days, at: "2026-10-02T00:05:00Z"
  end
end
