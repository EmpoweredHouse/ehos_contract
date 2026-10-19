defmodule Billing.Contracts.Subscriptions do
  @moduledoc """
  **Invented.** Subscriptions and their invoices.

  - **A subscription** is started on a plan with a monthly fee and a price per unit of
    usage, records usage as it comes, and is closed for each billing period, once. A
    close bills the usage recorded since the close before it. A cancelled subscription is closed no more.
  - **The monthly billing** is a process manager that never ends. It keeps the date the
    next period closes in its state. The first period closes on the first of the month
    after the subscription started, and each close of the period the date is for moves
    it a month on from itself, not from when the close ran. So a run that comes late
    catches up the months it missed, one after another, and no more. A close of any
    other period, by the account manager, leaves the date as it is, and the run skips that
    period when its date comes, so a period closed by hand is not closed twice. A close
    bills the usage recorded since the close before it, so after a late run the first
    month caught up carries all of it. Cancelling
    the subscription cancels the next close, and the run is left with nothing to do: it
    has no `ends_on`, which `mix eh_os_contract.check` warns of.
  - **An invoice** is drafted in the transaction that closes the period: a policy adds
    the monthly fee and one line per usage record, then issues it. The invoice is
    published to other applications as `billing.invoice.issued.v1`.
  """

  use EhOsContract.Contract,
    domain: Billing.Domain,
    context: :subscriptions,
    id: "billing.subscriptions"

  aggregate :subscription, "Subscription" do
    identity :subscription_id

    state do
      field :active, :boolean, default: false
      field :cancelled, :boolean, default: false
      field :monthly_fee, :money, default: 0
      field :unit_price, :money, default: 0
      field :first_period, :billing_period, optional: true
      field :closed, {:list, :billing_period}, default: []
      field :unbilled, {:list, :usage_record}, default: []
      field :recorded, {:list, :id}, default: []
    end

    invariant :started_once, "A subscription is started once"
    invariant :only_an_active_subscription_is_billed, "Only an active subscription is billed"
    invariant :period_closed_once, "A billing period is closed once"

    # A month still running would be billed without the usage still to come, and one
    # before the subscription began would be billed a fee nobody owes.
    invariant :only_an_ended_period_of_the_subscription_is_closed,
              "Only a month that has ended, since the subscription started, is closed"

    invariant :usage_recorded_once, "A usage record is recorded once"

    command :start_subscription, "Start a subscription",
      by: :account_manager,
      emits: :subscribed,
      rejects: :started_once do
      field :monthly_fee, :money
      field :unit_price, :money
    end

    command :record_usage, "Record usage",
      by: :account_manager,
      emits: :usage_recorded,
      rejects: [:only_an_active_subscription_is_billed, :usage_recorded_once] do
      field :usage, :usage_record
    end

    # The monthly billing issues it, and the account manager may, for a period the
    # billing never closed.
    command :close_billing_period, "Close a billing period",
      by: :account_manager,
      emits: :billing_period_closed,
      rejects: [
        :only_an_active_subscription_is_billed,
        :period_closed_once,
        :only_an_ended_period_of_the_subscription_is_closed
      ] do
      field :period_id, :billing_period
    end

    command :cancel_subscription, "Cancel a subscription",
      by: :account_manager,
      emits: :cancelled,
      rejects: :only_an_active_subscription_is_billed

    event :subscribed, "Subscription started" do
      field :monthly_fee, :money
      field :unit_price, :money
    end

    event :usage_recorded, "Usage recorded" do
      field :usage, :usage_record
    end

    event :billing_period_closed, "Billing period closed" do
      field :period_id, :billing_period
      field :monthly_fee, :money
      field :unit_price, :money
      field :usage, {:list, :usage_record}
    end

    event :cancelled, "Subscription cancelled"
  end

  aggregate :invoice, "Invoice" do
    identity [:subscription_id, :period_id]

    state do
      field :lines, {:list, :id}, default: []
      field :total, :money, default: 0
      field :issued, :boolean, default: false
    end

    invariant :line_added_once, "A line is added to an invoice once"
    invariant :issued_once_with_lines, "An invoice is issued once, with its lines"

    # An amount is a 64-bit integer of cents: lines that sum past it would make a total
    # no event can carry.
    invariant :total_fits_an_amount, "An invoice's total fits in an amount"

    command :add_invoice_line, "Add an invoice line",
      emits: :line_added,
      rejects: [:line_added_once, :issued_once_with_lines, :total_fits_an_amount] do
      field :line_id, :id
      field :amount, :money
    end

    command :issue_invoice, "Issue an invoice",
      emits: :issued,
      rejects: [:issued_once_with_lines, :total_fits_an_amount]

    event :line_added, "Invoice line added" do
      field :line_id, :id
      field :amount, :money
    end

    event :issued, "Invoice issued" do
      field :total, :money
    end
  end

  process_manager :monthly_billing, "Monthly billing" do
    correlate :subscription_id

    state do
      field :close_at, :timestamp, optional: true
      field :closed, {:list, :billing_period}, default: []
    end

    starts_on :subscribed, sets: :period_end
    on :billing_period_closed, sets: :period_end
    on :cancelled, cancels: :period_end

    timer :period_end, "End of the billing period",
      at: :close_at,
      issues: :close_billing_period
  end

  policy :invoice_the_period, "Invoice a closed period, one line per usage record",
    handles: :billing_period_closed,
    issues: [:add_invoice_line, :issue_invoice]

  publish :issued,
    as: "billing.invoice.issued.v1",
    from: :issued,
    fields: [:subscription_id, :period_id, :total],
    idempotent_on: [:subscription_id, :period_id]

  @started %{subscription_id: "sub-1", monthly_fee: 2_000, unit_price: 5}

  # The subscription

  scenario "a subscription is started" do
    command :start_subscription, @started
    expect :subscribed, %{monthly_fee: 2_000}
  end

  scenario "a subscription is started once" do
    given :subscribed, @started
    command :start_subscription, %{monthly_fee: 3_000, unit_price: 5}
    rejected :started_once
  end

  scenario "usage is recorded for its month" do
    given :subscribed, @started

    command :record_usage, %{usage: %{usage_id: "usage-1", units: 40}}
    expect :usage_recorded, %{usage: %{usage_id: "usage-1", units: 40}}
  end

  scenario "a usage record is recorded once" do
    given :subscribed, @started
    given :usage_recorded, %{usage: %{usage_id: "usage-1", units: 40}}

    command :record_usage, %{usage: %{usage_id: "usage-1", units: 40}}
    rejected :usage_recorded_once
  end

  scenario "a period closes with the usage recorded since the last close" do
    given :subscribed, @started, at: "2026-01-01T09:00:00Z"
    given :usage_recorded, %{usage: %{usage_id: "usage-1", units: 40}}, at: "2026-01-20T09:00:00Z"

    given :billing_period_closed,
          %{
            period_id: "2026-01",
            monthly_fee: 2_000,
            unit_price: 5,
            usage: [%{usage_id: "usage-1", units: 40}]
          },
          at: "2026-02-01T00:00:00Z"

    given :usage_recorded, %{usage: %{usage_id: "usage-2", units: 10}}, at: "2026-03-01T08:00:00Z"

    command :close_billing_period, %{period_id: "2026-02"}

    expect :billing_period_closed, %{
      period_id: "2026-02",
      monthly_fee: 2_000,
      unit_price: 5,
      usage: [%{usage_id: "usage-2", units: 10}]
    }
  end

  scenario "a period is closed once" do
    given :subscribed, @started

    given :billing_period_closed, %{
      period_id: "2026-01",
      monthly_fee: 2_000,
      unit_price: 5,
      usage: []
    }

    command :close_billing_period, %{period_id: "2026-01"}
    rejected :period_closed_once
  end

  scenario "a month still running is not closed" do
    given :subscribed, @started
    command :close_billing_period, %{period_id: "2026-01"}
    rejected :only_an_ended_period_of_the_subscription_is_closed
  end

  scenario "a month before the subscription started is not closed" do
    given :subscribed, @started, at: "2026-01-01T09:00:00Z"

    given :usage_recorded, %{usage: %{usage_id: "usage-1", units: 40}}, at: "2026-03-01T08:00:00Z"

    command :close_billing_period, %{period_id: "2025-12"}
    rejected :only_an_ended_period_of_the_subscription_is_closed
  end

  scenario "a cancelled subscription is billed no more" do
    given :subscribed, @started
    given :cancelled
    command :close_billing_period, %{period_id: "2026-01"}
    rejected :only_an_active_subscription_is_billed
  end

  scenario "a subscription is cancelled" do
    given :subscribed, @started
    command :cancel_subscription
    expect :cancelled
  end

  # The invoice

  scenario "a line is added to an invoice" do
    command :add_invoice_line, %{
      subscription_id: "sub-1",
      period_id: "2026-01",
      line_id: "fee",
      amount: 2_000
    }

    expect :line_added, %{line_id: "fee", amount: 2_000}
  end

  scenario "a line is added once" do
    given :line_added, %{
      subscription_id: "sub-1",
      period_id: "2026-01",
      line_id: "fee",
      amount: 2_000
    }

    command :add_invoice_line, %{line_id: "fee", amount: 2_000}
    rejected :line_added_once
  end

  scenario "an invoice is issued for the sum of its lines" do
    given :line_added, %{
      subscription_id: "sub-1",
      period_id: "2026-01",
      line_id: "fee",
      amount: 2_000
    }

    given :line_added, %{line_id: "usage-1", amount: 200}
    command :issue_invoice
    expect :issued, %{total: 2_200}
  end

  scenario "a line that takes the total past an amount is not added" do
    given :line_added, %{
      subscription_id: "sub-1",
      period_id: "2026-01",
      line_id: "fee",
      amount: 9_223_372_036_854_775_000
    }

    command :add_invoice_line, %{line_id: "usage-1", amount: 1_000}
    rejected :total_fits_an_amount
  end

  scenario "an invoice without lines is not issued" do
    command :issue_invoice, %{subscription_id: "sub-1", period_id: "2026-01"}
    rejected :issued_once_with_lines
  end

  # The monthly billing

  scenario "a subscription started in January first closes on 1 February" do
    target :monthly_billing
    on :subscribed, @started
    sets :period_end
    state %{close_at: "2026-02-01T00:00:00Z"}
  end

  scenario "the end of the period closes the month before it" do
    target :monthly_billing
    given :subscribed, @started
    on :period_end
    issues :close_billing_period, %{subscription_id: "sub-1", period_id: "2026-01"}
  end

  scenario "January closed — the next period closes on 1 March" do
    target :monthly_billing
    given :subscribed, @started

    on :billing_period_closed, %{
      subscription_id: "sub-1",
      period_id: "2026-01",
      monthly_fee: 2_000,
      unit_price: 5,
      usage: []
    }

    sets :period_end
    state %{close_at: "2026-03-01T00:00:00Z"}
  end

  scenario "an older period closed by hand leaves the date as it is" do
    target :monthly_billing
    given :subscribed, @started

    on :billing_period_closed, %{
      subscription_id: "sub-1",
      period_id: "2025-11",
      monthly_fee: 2_000,
      unit_price: 5,
      usage: []
    }

    state %{close_at: "2026-02-01T00:00:00Z"}
  end

  scenario "a period closed by hand ahead of the run is skipped when its date comes" do
    target :monthly_billing
    given :subscribed, @started

    given :billing_period_closed, %{
      subscription_id: "sub-1",
      period_id: "2026-02",
      monthly_fee: 2_000,
      unit_price: 5,
      usage: []
    }

    on :billing_period_closed, %{
      subscription_id: "sub-1",
      period_id: "2026-01",
      monthly_fee: 2_000,
      unit_price: 5,
      usage: []
    }

    state %{close_at: "2026-04-01T00:00:00Z"}
  end

  scenario "a cancelled subscription is closed no more" do
    target :monthly_billing
    given :subscribed, @started
    on :cancelled, %{subscription_id: "sub-1"}
    cancels :period_end
  end

  # The invoice of a closed period

  scenario "a closed period is invoiced: the fee, and a line per usage record" do
    target :invoice_the_period

    on :billing_period_closed, %{
      subscription_id: "sub-1",
      period_id: "2026-01",
      monthly_fee: 2_000,
      unit_price: 5,
      usage: [%{usage_id: "usage-1", units: 40}, %{usage_id: "usage-2", units: 10}]
    }

    issues :add_invoice_line, %{line_id: "fee", amount: 2_000}
    issues :add_invoice_line, %{line_id: "usage:usage-1", amount: 200}
    issues :add_invoice_line, %{line_id: "usage:usage-2", amount: 50}
    issues :issue_invoice, %{subscription_id: "sub-1", period_id: "2026-01"}
  end
end
