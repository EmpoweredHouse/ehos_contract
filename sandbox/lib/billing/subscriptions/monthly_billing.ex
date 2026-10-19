defmodule Billing.Subscriptions.MonthlyBilling do
  @moduledoc """
  **Invented.** Closes a subscription's billing period on the first of each month: the
  month that ended before the date the run keeps. The first start sets the date to the
  first of the next month. A close of the period the date is for moves it one month on
  from itself, so a run that came late is due again at once, until it has caught up.
  A close of any other period leaves the date as it is, and the run passes over that
  period when its date comes, so a timer never asks for a period closed already, which
  would be refused and leave the run with nothing set. A cancellation cancels the next
  close.
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

  def evolve(%State{close_at: at, closed: closed} = state, %BillingPeriodClosed{period_id: period}) do
    closed = [period | closed]
    %{state | closed: closed, close_at: past_closed(at, closed)}
  end

  def evolve(state, %Cancelled{}), do: state

  # The date the next close is due: the stored one, moved a month on for as long as the
  # month it would close is closed already.
  defp past_closed(at, closed) do
    if Periods.ended_before(at) in closed,
      do: past_closed(Periods.next_month_start(at), closed),
      else: at
  end
end
