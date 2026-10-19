defmodule Billing.MonthTest do
  @moduledoc """
  A subscription billed in the host, with the clock moved. The monthly billing closes
  each period by itself on the first of the month, catches up after a late run and is
  not moved by a retry. The close invoices the period in its own transaction. The
  payment is collected through a gateway that may be down, and the month's promise is
  judged on what happened (`Billing.Processes.Month`).
  """

  use EhOsContractHost.DataCase, async: false

  alias Billing.Adapters.PaymentGateway.Fake
  alias Billing.Contracts.Subscriptions
  alias Billing.Contracts.Subscriptions.Commands.{CancelSubscription, CloseBillingPeriod}
  alias Billing.Contracts.Subscriptions.Commands.{RecordUsage, StartSubscription}
  alias EhOsContract.{Actor, Clock, Event, Testing, Trace}

  @manager Actor.credential("manager-mo", [
             "billing.start_subscription",
             "billing.record_usage",
             "billing.close_billing_period",
             "billing.cancel_subscription"
           ])

  @promise :collected_within_three_days

  # The first drain is the deploy: the monthly billing, the payment's policy and the
  # effect subscribe before any subscription starts. The gateway takes every charge
  # unless a test says otherwise.
  setup do
    Application.delete_env(:eh_os_contract_host, Fake)
    on_exit(fn -> Application.delete_env(:eh_os_contract_host, Fake) end)
    Testing.drain()
    :ok
  end

  defp send!(command, at) do
    {:ok, _} =
      Clock.at(at, fn -> EhOsContract.dispatch(Subscriptions, command, actor: @manager) end)
  end

  defp subscribe(id, at) do
    send!(%StartSubscription{subscription_id: id, monthly_fee: 2_000, unit_price: 5}, at)
  end

  defp drain(at), do: Clock.at(at, fn -> Testing.drain() end)

  # This subscription's events, in the order they were appended: their names, or with
  # the period's identifier when they have one.
  defp log(id) do
    Repo.all(
      from(e in Event,
        where: fragment("? @> ?::text[]", e.tags, ^["subscription_id:#{id}"]),
        order_by: e.position,
        select: {e.type, fragment("?->>'period_id'", e.payload)}
      )
    )
  end

  defp closed(id),
    do: for({"billing.subscriptions.billing_period_closed", p} <- log(id), do: p)

  defp verdicts(now), do: Trace.evaluate(Billing.Processes.Month, @promise, now: now)

  test "the first of the month closes the month before, invoices it with its usage, and collects" do
    subscribe("sub-1", ~U[2026-08-15 10:00:00Z])

    for {usage, units} <- [{"usage-1", 40}, {"usage-2", 10}] do
      send!(
        %RecordUsage{subscription_id: "sub-1", usage: %{usage_id: usage, units: units}},
        ~U[2026-08-20 10:00:00Z]
      )
    end

    drain(~U[2026-08-31 23:00:00Z])
    assert closed("sub-1") == []

    drain(~U[2026-09-01 01:00:00Z])

    assert Enum.drop(log("sub-1"), 3) == [
             {"billing.subscriptions.billing_period_closed", "2026-08"},
             {"billing.subscriptions.line_added", "2026-08"},
             {"billing.subscriptions.line_added", "2026-08"},
             {"billing.subscriptions.line_added", "2026-08"},
             {"billing.subscriptions.issued", "2026-08"},
             {"billing.payments.requested", "2026-08"},
             {"billing.payments.collected", "2026-08"}
           ]

    [total] =
      Repo.all(
        from(e in Event,
          where: e.type == "billing.subscriptions.issued",
          select: fragment("(?->>'total')::bigint", e.payload)
        )
      )

    assert total == 2_000 + 40 * 5 + 10 * 5

    assert [%{verdict: :satisfied, via: :eventually}] = verdicts(~U[2026-09-10 00:00:00Z])
  end

  test "a run that comes late catches up the months it missed, and no more" do
    subscribe("sub-1", ~U[2026-08-15 10:00:00Z])

    drain(~U[2026-11-02 08:00:00Z])

    assert closed("sub-1") == ["2026-08", "2026-09", "2026-10"]
  end

  test "a period closed by hand ahead of the run is skipped, and moves nothing else" do
    # The run is due to close June on 1 July, and has not run. July is closed by hand.
    subscribe("sub-1", ~U[2026-06-15 10:00:00Z])

    send!(
      %CloseBillingPeriod{subscription_id: "sub-1", period_id: "2026-07"},
      ~U[2026-08-20 10:00:00Z]
    )

    drain(~U[2026-09-01 01:00:00Z])

    assert closed("sub-1") == ["2026-07", "2026-06", "2026-08"]
  end

  test "a month still running, or one before the subscription, is not closed by hand" do
    subscribe("sub-1", ~U[2026-08-15 10:00:00Z])

    for period <- ["2026-09", "2026-07"] do
      assert {:error,
              %EhOsContract.Rejection{
                invariant: :only_an_ended_period_of_the_subscription_is_closed
              }} =
               Clock.at(~U[2026-09-15 10:00:00Z], fn ->
                 EhOsContract.dispatch(
                   Subscriptions,
                   %CloseBillingPeriod{subscription_id: "sub-1", period_id: period},
                   actor: @manager
                 )
               end)
    end

    assert closed("sub-1") == []
  end

  test "a cancelled subscription's next close is cancelled, not refused" do
    subscribe("sub-1", ~U[2026-08-15 10:00:00Z])
    send!(%CancelSubscription{subscription_id: "sub-1"}, ~U[2026-08-20 10:00:00Z])

    drain(~U[2026-10-02 08:00:00Z])
    assert closed("sub-1") == []

    # Had the timer stayed set, its close would have been decided, and refused as a
    # close of a subscription no longer billed.
    assert Repo.all(
             from(c in "eh_os_contract_commands",
               where: c.invariant == "only_an_active_subscription_is_billed",
               select: c.id
             )
           ) == []
  end

  test "the invoice's lines and the invoice are appended in the close's transaction" do
    subscribe("sub-1", ~U[2026-08-15 10:00:00Z])

    send!(
      %RecordUsage{subscription_id: "sub-1", usage: %{usage_id: "usage-1", units: 40}},
      ~U[2026-08-20 10:00:00Z]
    )

    # No drain: what the in-transaction policy issued is there when the close returns,
    # and the payment, asked for after the transaction, is not yet.
    send!(
      %CloseBillingPeriod{subscription_id: "sub-1", period_id: "2026-08"},
      ~U[2026-09-01 00:30:00Z]
    )

    assert Enum.drop(log("sub-1"), 2) == [
             {"billing.subscriptions.billing_period_closed", "2026-08"},
             {"billing.subscriptions.line_added", "2026-08"},
             {"billing.subscriptions.line_added", "2026-08"},
             {"billing.subscriptions.issued", "2026-08"}
           ]
  end

  test "the gateway down once: the outage is observed, and the next attempt collects" do
    Application.put_env(:eh_os_contract_host, Fake, down: 1)
    subscribe("sub-1", ~U[2026-08-15 10:00:00Z])

    drain(~U[2026-09-01 01:00:00Z])

    assert {"billing.payments.collected", "2026-08"} in log("sub-1")
    assert [observed] = observations()
    assert DateTime.compare(observed, ~U[2026-09-01 01:00:00Z]) == :eq
    assert [%{verdict: :satisfied, via: :eventually}] = verdicts(~U[2026-09-10 00:00:00Z])
  end

  test "the gateway down throughout: nothing is collected, and the month is suspended, not broken" do
    Application.put_env(:eh_os_contract_host, Fake, down: :always)
    subscribe("sub-1", ~U[2026-08-15 10:00:00Z])

    drain(~U[2026-09-01 01:00:00Z])

    refute Enum.any?(log("sub-1"), &match?({"billing.payments.collected", _}, &1))
    assert observations() != []
    assert [%{verdict: :suspended}] = verdicts(~U[2026-09-05 00:00:00Z])
  end

  test "a period not named by its month is refused before it is decided" do
    subscribe("sub-1", ~U[2026-08-15 10:00:00Z])

    assert {:error, {:invalid, [period_id: {:invariant, :named_by_month}]}} =
             Clock.at(~U[2026-09-15 10:00:00Z], fn ->
               EhOsContract.dispatch(
                 Subscriptions,
                 %CloseBillingPeriod{subscription_id: "sub-1", period_id: "2026-8"},
                 actor: @manager
               )
             end)

    assert closed("sub-1") == []
  end

  defp observations do
    Repo.all(
      from(o in "eh_os_contract_dependency_observations",
        where: o.external == "payment_gateway",
        select: type(o.observed_at, :utc_datetime_usec)
      )
    )
  end
end
