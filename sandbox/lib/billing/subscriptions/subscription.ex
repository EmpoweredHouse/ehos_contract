defmodule Billing.Subscriptions.Subscription do
  @moduledoc """
  **Invented.** Decides a subscription: started once, billed while active, each period
  closed once with the usage recorded since the close before it.
  """

  use Billing.Contracts.Subscriptions, aggregate: :subscription

  @impl true
  def start_subscription(_command, %State{active: true}), do: reject(:started_once)
  def start_subscription(_command, %State{cancelled: true}), do: reject(:started_once)

  def start_subscription(%StartSubscription{} = command, _state) do
    emit(%Subscribed{
      subscription_id: command.subscription_id,
      monthly_fee: command.monthly_fee,
      unit_price: command.unit_price
    })
  end

  @impl true
  def record_usage(_command, %State{active: false}),
    do: reject(:only_an_active_subscription_is_billed)

  def record_usage(%RecordUsage{subscription_id: id, usage: usage}, %State{} = state) do
    if usage.usage_id in state.recorded,
      do: reject(:usage_recorded_once),
      else: emit(%UsageRecorded{subscription_id: id, usage: usage})
  end

  @impl true
  def close_billing_period(_command, %State{active: false}),
    do: reject(:only_an_active_subscription_is_billed)

  def close_billing_period(%CloseBillingPeriod{} = command, %State{} = state) do
    if command.period_id in state.closed do
      reject(:period_closed_once)
    else
      emit(%BillingPeriodClosed{
        subscription_id: command.subscription_id,
        period_id: command.period_id,
        monthly_fee: state.monthly_fee,
        unit_price: state.unit_price,
        usage: Enum.reverse(state.unbilled)
      })
    end
  end

  @impl true
  def cancel_subscription(%CancelSubscription{subscription_id: id}, %State{active: true}),
    do: emit(%Cancelled{subscription_id: id})

  def cancel_subscription(_command, _state), do: reject(:only_an_active_subscription_is_billed)

  @impl true
  def evolve(state, %Subscribed{monthly_fee: fee, unit_price: price}),
    do: %{state | active: true, monthly_fee: fee, unit_price: price}

  def evolve(state, %UsageRecorded{usage: usage}),
    do: %{state | unbilled: [usage | state.unbilled], recorded: [usage.usage_id | state.recorded]}

  def evolve(state, %BillingPeriodClosed{period_id: period}),
    do: %{state | closed: [period | state.closed], unbilled: []}

  def evolve(state, %Cancelled{}), do: %{state | active: false, cancelled: true}
end
