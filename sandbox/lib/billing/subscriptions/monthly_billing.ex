defmodule Billing.Subscriptions.MonthlyBilling do
  @moduledoc """
  **Invented.** Closes a subscription's billing period on the first of each month: the
  month that ended before the date the run keeps. The first start sets the date to the
  first of the next month. A close of the period the date is for moves it one month on
  from itself, so a run that came late is due again at once, until it has caught up.
  A close of any other period leaves the date as it is, and a cancellation cancels the
  next close.
  """

  use Billing.Contracts.Subscriptions, process_manager: :monthly_billing

  alias Billing.Periods

  @impl true
  def period_end(%State{subscription_id: id, close_at: at}),
    do: issue(%CloseBillingPeriod{subscription_id: id, period_id: Periods.ended_before(at)})

  @impl true
  def evolve(%State{close_at: nil} = state, %Subscribed{__meta__: meta}),
    do: %{state | close_at: Periods.next_month_start(meta.occurred_at)}

  def evolve(state, %Subscribed{}), do: state

  def evolve(%State{close_at: at} = state, %BillingPeriodClosed{period_id: period}) do
    if period == Periods.ended_before(at),
      do: %{state | close_at: Periods.next_month_start(at)},
      else: state
  end

  def evolve(state, %Cancelled{}), do: state
end
