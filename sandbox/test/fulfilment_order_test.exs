defmodule Fulfilment.OrderTest do
  @moduledoc """
  An order run through the three contexts in the host, with the clock moved, and judged
  by the promise of `Fulfilment.Processes.Order`: dispatched within a day of the payment.
  The day counts from the payment, an event in the middle of the run, so an order placed
  a week before it was paid is judged from the payment, not from its placing.
  """

  use EhosContractHost.DataCase, async: false

  alias EhosContract.{Actor, Clock, Event, Testing, Trace}
  alias Fulfilment.Contracts.{Orders, Shipping, Warehouse}
  alias Fulfilment.Contracts.Orders.Commands.{ConfirmPayment, PlaceOrder}
  alias Fulfilment.Contracts.Shipping.Commands.DispatchParcel
  alias Fulfilment.Contracts.Shipping.Events.Delivered
  alias Fulfilment.Contracts.Warehouse.Commands.{AssignPickList, ConfirmPick, PackParcel}

  @desk Actor.credential("desk-cy", ["fulfilment.place_order", "fulfilment.confirm_payment"])
  @dispatcher Actor.credential("dispatcher-di", ["fulfilment.dispatch_parcel"])
  @picker_capabilities ~w(fulfilment.confirm_pick fulfilment.pack_parcel)
  @lead Actor.credential("lead-lu", ["fulfilment.assign_pick_list"], %{
          "fulfilment.assign_pick_list" => %{"warehouse_id" => ["w-1"]}
        })
  @picker Actor.credential(
            "picker-ada",
            @picker_capabilities,
            Map.new(@picker_capabilities, &{&1, %{"warehouse_id" => ["w-1"]}})
          )

  @placed ~U[2026-09-01 09:00:00Z]
  @paid ~U[2026-09-08 09:00:00Z]

  # The first drain is the deploy: the policies subscribe before the first order.
  setup do
    Testing.drain()
    :ok
  end

  defp at(moment, contract, command, actor) do
    {:ok, _} = Clock.at(moment, fn -> EhosContract.dispatch(contract, command, actor: actor) end)
  end

  # Order `id` placed and paid, picked, packed and booked, then dispatched at `dispatched`.
  defp fulfil(id, dispatched) do
    list = %{warehouse_id: "w-1", order_id: id}
    at(@placed, Orders, %PlaceOrder{order_id: id, warehouse_id: "w-1", items: 3}, @desk)
    at(@paid, Orders, %ConfirmPayment{order_id: id}, @desk)
    Clock.at(@paid, fn -> Testing.drain() end)

    at(@paid, Warehouse, struct!(AssignPickList, Map.put(list, :picker_id, "picker-ada")), @lead)
    at(@paid, Warehouse, struct!(ConfirmPick, list), @picker)
    at(@paid, Warehouse, struct!(PackParcel, Map.put(list, :weight_grams, 1_200)), @picker)
    Clock.at(@paid, fn -> Testing.drain() end)

    at(dispatched, Shipping, %DispatchParcel{order_id: id}, @dispatcher)
  end

  defp verdicts(now) do
    Trace.evaluate(Fulfilment.Processes.Order, :dispatched_within_a_day_of_payment, now: now)
    |> Map.new(&{&1.instance_id, &1.verdict})
  end

  defp types(id) do
    Repo.all(
      from(e in Event,
        where: fragment("? @> ?::text[]", e.tags, ^["order_id:#{id}"]),
        order_by: e.position,
        select: e.type
      )
    )
  end

  test "a run crosses the three contexts, its policies included" do
    fulfil("order-1", DateTime.add(@paid, 9 * 3600))

    assert types("order-1") == [
             "fulfilment.orders.placed",
             "fulfilment.orders.payment_confirmed",
             "fulfilment.warehouse.opened",
             "fulfilment.warehouse.assigned",
             "fulfilment.warehouse.picked",
             "fulfilment.warehouse.parcel_packed",
             "fulfilment.shipping.booked",
             "fulfilment.shipping.dispatched"
           ]
  end

  test "the day counts from the payment, not from the order placed a week before it" do
    fulfil("order-1", DateTime.add(@paid, 9 * 3600))
    fulfil("order-2", DateTime.add(@paid, 30 * 3600))

    verdicts = verdicts(DateTime.add(@paid, 3 * 24 * 3600))
    assert map_size(verdicts) == 2
    assert Enum.find_value(verdicts, fn {id, v} -> id =~ "order-1" && v end) == :satisfied
    assert Enum.find_value(verdicts, fn {id, v} -> id =~ "order-2" && v end) == :violated
  end

  test "the carrier's integration records the delivery, the run's last event" do
    fulfil("order-1", DateTime.add(@paid, 9 * 3600))

    {:ok, _} =
      Clock.at(DateTime.add(@paid, 2 * 24 * 3600), fn ->
        EhosContract.record(Shipping, %Delivered{order_id: "order-1"},
          actor: Actor.system(:carrier_integration)
        )
      end)

    assert List.last(types("order-1")) == "fulfilment.shipping.delivered"

    assert Repo.one!(
             from(e in Event, where: e.type == "fulfilment.shipping.delivered", select: e.actor)
           ) == "system:carrier_integration"
  end
end
