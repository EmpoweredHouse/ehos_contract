defmodule Billing.Subscriptions.Subscription do
  @moduledoc """
  **Invented.** Decides a subscription: started once, billed while active, each period
  closed once, only once it has ended and not before the subscription's first month,
  with the usage recorded since the close before it.
  """

  use Billing.Contracts.Subscriptions, aggregate: :subscription

  alias Billing.Periods

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

  def close_billing_period(%CloseBillingPeriod{period_id: period} = command, %State{} = state) do
    cond do
      period in state.closed ->
        reject(:period_closed_once)

      not of_the_subscription?(period, state) or not ended?(period, command.__meta__) ->
        reject(:only_an_ended_period_of_the_subscription_is_closed)

      true ->
        emit(%BillingPeriodClosed{
          subscription_id: command.subscription_id,
          period_id: command.period_id,
          monthly_fee: state.monthly_fee,
          unit_price: state.unit_price,
          usage: Enum.reverse(state.unbilled)
        })
    end
  end

  # Names are YYYY-MM, so they compare as the months do.
  defp of_the_subscription?(_period, %State{first_period: nil}), do: true
  defp of_the_subscription?(period, %State{first_period: first}), do: period >= first

  # A command decided without the moment it was issued at, as a property decides one,
  # is not held to it.
  defp ended?(_period, nil), do: true
  defp ended?(period, meta), do: Periods.ended_by?(period, meta.occurred_at)

  @impl true
  def cancel_subscription(%CancelSubscription{subscription_id: id}, %State{active: true}),
    do: emit(%Cancelled{subscription_id: id})

  def cancel_subscription(_command, _state), do: reject(:only_an_active_subscription_is_billed)

  @impl true
  def evolve(state, %Subscribed{monthly_fee: fee, unit_price: price} = subscribed) do
    first = subscribed.__meta__ && Periods.name_of(subscribed.__meta__.occurred_at)
    %{state | active: true, monthly_fee: fee, unit_price: price, first_period: first}
  end

  def evolve(state, %UsageRecorded{usage: usage}),
    do: %{state | unbilled: [usage | state.unbilled], recorded: [usage.usage_id | state.recorded]}

  def evolve(state, %BillingPeriodClosed{period_id: period}),
    do: %{state | closed: [period | state.closed], unbilled: []}

  def evolve(state, %Cancelled{}), do: %{state | active: false, cancelled: true}
end
