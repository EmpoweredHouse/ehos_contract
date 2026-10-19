defmodule Fulfilment.Domain do
  @moduledoc """
  **Invented.** The vocabulary of order fulfilment: the order desk takes orders and
  confirms their payment, the warehouse picks and packs them, and shipping books a
  carrier and dispatches the parcel.
  """

  use EhOsContract.Domain, name: :fulfilment, language: :en
  use Boundary, deps: [EhOsContract], exports: [{Values, []}]

  subdomain :core, "Fulfilment", type: :core
  subdomain :supporting, "Logistics", type: :supporting

  context :orders, "Orders", subdomain: :core do
    term "Order", definition: "What a customer bought, from one warehouse"
    term "Payment", definition: "The customer's payment for an order, as the desk confirms it"
  end

  context :warehouse, "Warehouse", subdomain: :supporting do
    term "Order", definition: "What a pick list is opened for, once it is paid"
    term "Pick list", definition: "The items of one order to take off the shelves"

    term "Picker",
      definition: "Who takes a pick list's items off the shelves, as the lead assigns"

    term "Parcel", definition: "A picked order, packed and weighed"
  end

  context :shipping, "Shipping", subdomain: :supporting do
    term "Order", definition: "Whose parcel a shipment carries"
    term "Shipment", definition: "A parcel booked with a carrier, until it is delivered"
    term "Parcel", definition: "What a shipment carries, by its weight"
  end

  relation :customer_supplier, upstream: :orders, downstream: :warehouse
  relation :customer_supplier, upstream: :orders, downstream: :shipping
  relation :customer_supplier, upstream: :warehouse, downstream: :shipping
  relation :conformist, upstream: :carrier, downstream: :shipping

  actor :order_desk, :human, "Order desk"

  # A lead and a picker are granted the warehouses they work in, and act in no other.
  actor :lead, :human, "Warehouse lead", scope: [:warehouse_id]
  actor :picker, :human, "Picker", scope: [:warehouse_id]

  actor :dispatcher, :human, "Dispatcher"

  actor :carrier_integration, :system, "Carrier integration",
    backed_by: :carrier,
    context: :shipping

  external :carrier, "Carrier",
    direction: :bidirectional,
    unavailable_looks_like: "the carrier's tracking does not answer"

  value :service, {:enum, [parcel: "Parcel", freight: "Freight"]}, label: "Carrier service"
end
