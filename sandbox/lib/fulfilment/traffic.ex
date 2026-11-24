defmodule Fulfilment.Traffic do
  @moduledoc """
  **Invented.** The shop's part of `mix sandbox.traffic`: about two weeks of orders,
  drift included. Each step is how many hours ago it happened, what happened, and a
  function giving the operations to run then, which the task runs and checks
  (`Mix.Tasks.Sandbox.Traffic`).

  - order-1 goes the whole way, handed over nine hours after its payment and delivered.
  - order-2 is handed over two days after its payment: broken. A picker it is not
    assigned to tries to confirm its pick list first, and is refused.
  - order-3 is placed and left, never paid and never cancelled, past the run's two weeks.
  - order-4 is cancelled before it is paid.
  - order-5 is booked with the carrier, never handed over, and reported delivered: a move
    its shipment's lifecycle does not declare, and its day after the payment broken.
  - order-6 is reported delivered before it is paid, so before its pick list opens: the
    shipping stage entered before the picking stage, a stage counting from its first
    event, and a delivery of a shipment that never started. Its parcel is never handed
    over either: broken.
  - order-7 is not handed over while the carrier is down: suspended, not broken.
  - order-8 was paid two hours ago, its day still running.
  """

  alias EhosContract.Actor
  alias Fulfilment.Contracts.{Orders, Shipping, Warehouse}
  alias Fulfilment.Contracts.Orders.Commands.{CancelOrder, ConfirmPayment, PlaceOrder}
  alias Fulfilment.Contracts.Shipping.Commands.DispatchParcel
  alias Fulfilment.Contracts.Shipping.Events.Delivered
  alias Fulfilment.Contracts.Warehouse.Commands.{AssignPickList, ConfirmPick, PackParcel}

  @desk Actor.credential(
          "desk-cy",
          ~w(fulfilment.place_order fulfilment.confirm_payment fulfilment.cancel_order)
        )
  @dispatcher Actor.credential("dispatcher-di", ["fulfilment.dispatch_parcel"])
  @carrier Actor.system(:carrier_integration)

  @warehouse "w-1"
  @lead Actor.credential("lead-lu", ["fulfilment.assign_pick_list"], %{
          "fulfilment.assign_pick_list" => %{"warehouse_id" => [@warehouse]}
        })
  @picking ~w(fulfilment.confirm_pick fulfilment.pack_parcel)
  @scoped Map.new(@picking, &{&1, %{"warehouse_id" => [@warehouse]}})
  @picker Actor.credential("picker-pia", @picking, @scoped)
  @other_picker Actor.credential("picker-oz", @picking, @scoped)

  @doc "The steps, as `{hours_ago, what, operations}`."
  @spec steps() :: [{number(), String.t(), (-> [tuple()])}]
  def steps do
    [
      {300, "order-1 placed", fn -> place("order-1") end},
      {299, "order-1 paid", fn -> pay("order-1") end},
      {298, "order-1 picked and packed", fn -> assign("order-1") ++ pick("order-1") end},
      {290, "order-1 handed to the carrier", fn -> dispatch("order-1") end},
      {270, "order-1 delivered", fn -> delivered("order-1") end},
      {250, "order-2 placed", fn -> place("order-2") end},
      {249, "order-2 paid", fn -> pay("order-2") end},
      {248, "order-2's pick list confirmed by a picker it is not assigned to: refused",
       fn ->
         assign("order-2") ++
           [
             {:refused, Warehouse, struct!(ConfirmPick, list("order-2")), @other_picker,
              :confirmed_by_its_picker}
           ]
       end},
      {247, "order-2 picked and packed", fn -> pick("order-2") end},
      {201, "order-2 handed to the carrier, two days after its payment",
       fn -> dispatch("order-2") end},
      {420, "order-3 placed, and left", fn -> place("order-3") end},
      {180, "order-4 placed", fn -> place("order-4") end},
      {170, "order-4 cancelled",
       fn -> [{:ok, Orders, %CancelOrder{order_id: "order-4"}, @desk}] end},
      {150, "order-5 placed", fn -> place("order-5") end},
      {149, "order-5 paid", fn -> pay("order-5") end},
      {148, "order-5 picked and packed", fn -> assign("order-5") ++ pick("order-5") end},
      {120, "order-5 reported delivered, never handed over", fn -> delivered("order-5") end},
      {110, "order-6 placed", fn -> place("order-6") end},
      {105, "order-6 reported delivered, nothing picked", fn -> delivered("order-6") end},
      {100, "order-6 paid, its pick list opened", fn -> pay("order-6") end},
      {95, "order-6 picked and packed, after its delivery was reported",
       fn -> assign("order-6") ++ pick("order-6") end},
      {80, "order-7 placed", fn -> place("order-7") end},
      {79, "order-7 paid", fn -> pay("order-7") end},
      {78, "order-7 picked and packed", fn -> assign("order-7") ++ pick("order-7") end},
      {70, "the carrier's tracking does not answer",
       fn -> [{:outage, Shipping, :carrier, "tracking timed out"}] end},
      {3, "order-8 placed", fn -> place("order-8") end},
      {2, "order-8 paid", fn -> pay("order-8") end}
    ]
  end

  defp place(order),
    do: [{:ok, Orders, %PlaceOrder{order_id: order, warehouse_id: @warehouse, items: 3}, @desk}]

  defp pay(order), do: [{:ok, Orders, %ConfirmPayment{order_id: order}, @desk}]

  defp list(order), do: %{warehouse_id: @warehouse, order_id: order}

  # The pick list was opened by the policy on the payment, at the drain after it.
  defp assign(order),
    do: [
      {:ok, Warehouse, struct!(AssignPickList, Map.put(list(order), :picker_id, "picker-pia")),
       @lead}
    ]

  defp pick(order),
    do: [
      {:ok, Warehouse, struct!(ConfirmPick, list(order)), @picker},
      {:ok, Warehouse, struct!(PackParcel, Map.put(list(order), :weight_grams, 1_200)), @picker}
    ]

  defp dispatch(order), do: [{:ok, Shipping, %DispatchParcel{order_id: order}, @dispatcher}]

  defp delivered(order), do: [{:recorded, Shipping, %Delivered{order_id: order}, @carrier}]
end
