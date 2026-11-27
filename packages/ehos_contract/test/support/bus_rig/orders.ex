defmodule BusRig.Orders do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  An order is placed and may be cancelled. Placing it is published, with its total
  and without the clerk's note, which stays inside the shop; a cancellation is not
  published at all.
  """

  use EhosContract.Contract, domain: BusRig.Shop, context: :sales, id: "bus_rig_shop.orders"

  aggregate :order, "Order" do
    identity :order_id

    command :place_order, "Place an order", by: :clerk, emits: :placed do
      field :total, :integer
      field :note, :string
    end

    command :cancel_order, "Cancel an order", by: :clerk, emits: :cancelled

    event :placed, "Order placed" do
      field :total, :integer
      field :note, :string
    end

    event :cancelled, "Order cancelled"
  end

  publish :order_placed,
    from: :placed,
    fields: [:order_id, :total],
    idempotent_on: [:order_id]

  scenario "an order is placed with its total" do
    command :place_order, %{total: 120, note: "gift wrap"}
    expect :placed, %{total: 120, note: "gift wrap"}
  end
end
