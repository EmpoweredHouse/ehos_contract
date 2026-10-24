defmodule Fulfilment.Contracts.Shipping do
  @moduledoc """
  **Invented.** Shipping: a packed parcel is booked with the carrier, by its weight, as
  a parcel or as freight; the dispatcher hands it over, and the carrier reports it
  delivered.

  The booking reads the warehouse's `parcel_packed` and its `weight_grams`, which is
  why a rename of that field on the warehouse's side breaks this contract's scenarios
  and the policy's pattern.

  A shipment goes booked, with the carrier, delivered. The delivery is the carrier's to
  record, and a recorded event is appended whatever the shipment's status: a delivery
  reported for a parcel never handed over moves nothing, and the conformance report
  counts it as a transition the lifecycle does not declare.
  """

  use EhOsContract.Contract,
    domain: Fulfilment.Domain,
    context: :shipping,
    id: "fulfilment.shipping"

  consumes Fulfilment.Contracts.Warehouse, :parcel_packed

  aggregate :shipment, "Shipment" do
    identity order_id: {:id, :order}

    lifecycle do
      status :booked, "Booked"
      status :dispatched, "With the carrier"
      status :delivered, "Delivered", final: true

      initial :booked, on: :booked
      transition :booked, :dispatched, :dispatched
      transition :dispatched, :delivered, :delivered
    end

    invariant :booked_once, "A shipment is booked once"
    invariant :dispatched_once_when_booked, "A booked shipment is dispatched once"

    command :book_shipment, "Book a shipment",
      emits: :booked,
      rejects: :booked_once do
      field :service, :service
      field :weight_grams, :integer
    end

    command :dispatch_parcel, "Hand a parcel to the carrier",
      by: :dispatcher,
      emits: :dispatched,
      rejects: :dispatched_once_when_booked,
      from: :booked,
      or_rejects: :dispatched_once_when_booked

    event :booked, "Shipment booked" do
      field :service, :service
      field :weight_grams, :integer
    end

    event :dispatched, "Parcel handed to the carrier"

    event :delivered, "Parcel delivered",
      recorded_by: :carrier_integration,
      depends_on: :carrier
  end

  policy :book_carrier, "Book the carrier for a packed parcel, by its weight",
    handles: :parcel_packed,
    issues: :book_shipment,
    delivery: :at_least_once,
    idempotency: [key: :event_id, owner: :infrastructure] do
    constraint :freight_above_twenty_kilograms,
               "A parcel over twenty kilograms goes as freight"
  end

  scenario "a light parcel is booked as a parcel",
    illustrates: :freight_above_twenty_kilograms do
    target :book_carrier
    on :parcel_packed, %{warehouse_id: "w-1", order_id: "order-1", weight_grams: 1_200}
    issues :book_shipment, %{order_id: "order-1", service: :parcel, weight_grams: 1_200}
  end

  scenario "a heavy parcel is booked as freight",
    illustrates: :freight_above_twenty_kilograms do
    target :book_carrier
    on :parcel_packed, %{warehouse_id: "w-1", order_id: "order-1", weight_grams: 25_000}
    issues :book_shipment, %{order_id: "order-1", service: :freight, weight_grams: 25_000}
  end

  scenario "a shipment is booked" do
    command :book_shipment, %{order_id: "order-1", service: :parcel, weight_grams: 1_200}
    expect :booked, %{service: :parcel}
  end

  scenario "a shipment is booked once" do
    given :booked, %{order_id: "order-1", service: :parcel, weight_grams: 1_200}
    command :book_shipment, %{service: :parcel, weight_grams: 1_200}
    rejected :booked_once
  end

  scenario "a booked parcel is handed to the carrier" do
    given :booked, %{order_id: "order-1", service: :parcel, weight_grams: 1_200}
    command :dispatch_parcel
    expect :dispatched
  end

  scenario "a shipment not booked is not dispatched" do
    command :dispatch_parcel, %{order_id: "order-1"}
    rejected :dispatched_once_when_booked
  end

  scenario "the carrier records a parcel delivered" do
    actor :carrier_integration
    given :booked, %{order_id: "order-1", service: :parcel, weight_grams: 1_200}
    given :dispatched
    record :delivered
    expect :delivered, %{order_id: "order-1"}
  end
end
