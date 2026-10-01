defmodule BusRig.Stock do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  The warehouse reserves stock for every order the shop places, which it learns of
  only from the shop's publication: it has none of the shop's code. Its policy
  reserves every time it is told, so a reservation made twice for one order shows
  what the inbox did not drop.
  """

  use EhOsContract.Contract, domain: BusRig.Warehouse, context: :stock

  consumes "bus_rig_shop.order.placed.v1", as: :order_placed do
    field :order_id, :id
    field :total, :integer
  end

  aggregate :reservation, "Reservation" do
    identity :order_id

    command :reserve_stock, "Reserve stock", by: :keeper, emits: :reserved do
      field :total, :integer
    end

    event :reserved, "Stock reserved" do
      field :total, :integer
    end
  end

  policy :reserve_for_order, "Reserve stock for a placed order",
    handles: :order_placed,
    issues: :reserve_stock

  process :reservation, "Reservation", accountable: :keeper do
    correlate :order_id
  end

  scenario "a placed order has its total reserved" do
    on :order_placed, %{order_id: "o-1", total: 120}
    issues :reserve_stock, %{order_id: "o-1", total: 120}
  end

  scenario "stock is reserved for an order's total" do
    command :reserve_stock, %{total: 120}
    expect :reserved, %{total: 120}
  end
end
