defmodule Billing.Traffic do
  @moduledoc """
  **Invented.** The company's part of `mix sandbox.traffic`: four subscriptions over the
  first of a month at least four days old, drift included. Each step is how many hours
  ago it happened, what happened, and a function giving the operations to run then, which
  the task runs and checks (`Mix.Tasks.Sandbox.Traffic`).

  On that first of the month the monthly billing closes the period of sub-a, sub-b and
  sub-c, and their invoices ask for payment. The run charges through `Billing.Traffic.Gateway`,
  which will not charge sub-b and sub-c:

  - sub-a's payment is collected: kept;
  - sub-b's charge fails until Oban gives up, and the account manager writes the payment
    off the next day: kept the other way;
  - sub-c's charge fails the same way and nobody writes it off, but the gateway was down
    inside the three days: suspended, not broken.

  sub-d is cancelled before the first, so nothing is billed, and usage recorded on it
  afterwards is refused. Every active subscription's next period end waits. Nobody
  closes a period by hand. Run in the first four days of a month, the window also holds
  that month's first, and the three are billed again then, sub-b and sub-c refused again.
  """

  alias Billing.Contracts.{Payments, Subscriptions}
  alias Billing.Domain.Values.UsageRecord
  alias Billing.Contracts.Payments.Commands.WriteOffPayment

  alias Billing.Contracts.Subscriptions.Commands.{
    CancelSubscription,
    RecordUsage,
    StartSubscription
  }

  alias EhOsContract.Actor

  @manager Actor.credential(
             "manager-mo",
             ~w(billing.start_subscription billing.record_usage billing.cancel_subscription
                billing.write_off_payment)
           )

  @doc """
  The steps, as `{hours_ago, what, operations}`, with `now` the moment the task counts
  back from.
  """
  @spec steps(DateTime.t()) :: [{number(), String.t(), (-> [tuple()])}]
  def steps(now) do
    closed = closed_month_start(now)
    first = DateTime.diff(now, closed, :hour)
    start = first + 240
    period = closed |> DateTime.add(-1) |> Calendar.strftime("%Y-%m")

    [
      {start, "sub-a started", fn -> subscribe("sub-a") end},
      {start - 1, "sub-b started, a customer the gateway will not charge",
       fn -> subscribe("sub-b") end},
      {start - 2, "sub-c started, a customer the gateway will not charge",
       fn -> subscribe("sub-c") end},
      {start - 3, "sub-d started", fn -> subscribe("sub-d") end},
      {start - 24, "sub-a's usage recorded",
       fn -> [{:ok, Subscriptions, usage("sub-a", "usage-1", 40), @manager}] end},
      {start - 48, "sub-a's usage recorded",
       fn -> [{:ok, Subscriptions, usage("sub-a", "usage-2", 15), @manager}] end},
      {start - 72, "sub-d cancelled",
       fn ->
         [{:ok, Subscriptions, %CancelSubscription{subscription_id: "sub-d"}, @manager}]
       end},
      {start - 73, "sub-d's usage refused: it is cancelled",
       fn ->
         [
           {:refused, Subscriptions, usage("sub-d", "usage-3", 5), @manager,
            :only_an_active_subscription_is_billed}
         ]
       end},
      {first - 24, "sub-b's payment written off",
       fn ->
         [
           {:ok, Payments, %WriteOffPayment{subscription_id: "sub-b", period_id: period},
            @manager}
         ]
       end}
    ]
  end

  defp subscribe(id) do
    [
      {:ok, Subscriptions,
       %StartSubscription{subscription_id: id, monthly_fee: 2_000, unit_price: 5}, @manager}
    ]
  end

  defp usage(id, usage, units),
    do: %RecordUsage{subscription_id: id, usage: %UsageRecord{usage_id: usage, units: units}}

  # The latest first of a month, at midnight UTC, at least four days before `now`, so its
  # invoices' three days are over.
  defp closed_month_start(now) do
    latest = DateTime.new!(Date.beginning_of_month(DateTime.to_date(now)), ~T[00:00:00])

    if DateTime.diff(now, latest, :hour) >= 96,
      do: latest,
      else: DateTime.new!(Date.shift(DateTime.to_date(latest), month: -1), ~T[00:00:00])
  end
end

defmodule Billing.Traffic.Gateway do
  @moduledoc """
  **Invented.** The payment gateway of `mix sandbox.traffic`'s run: it will not charge
  sub-b and sub-c, answering as a gateway that is down, and passes every other charge to
  `Billing.Adapters.PaymentGateway.Fake`.
  """

  @behaviour Billing.Adapters.PaymentGateway

  @refused ~w(sub-b sub-c)

  @impl true
  def charge(subscription, _amount, _key) when subscription in @refused,
    do: {:error, :unavailable}

  def charge(subscription, amount, key),
    do: Billing.Adapters.PaymentGateway.Fake.charge(subscription, amount, key)
end
