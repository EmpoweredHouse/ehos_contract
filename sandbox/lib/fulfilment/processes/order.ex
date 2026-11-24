defmodule Fulfilment.Processes.Order do
  @moduledoc """
  **Invented.** One order, across the order desk, the warehouse and shipping: placed,
  paid, picked and packed, booked, dispatched, and delivered or cancelled.

  The shop promises that a paid order leaves the warehouse within a day. The day counts
  from the payment, an event in the middle of the run, not from the order's placing: an
  order left unpaid for a week has not broken that promise. The deadline is the whole
  run's, unpaid time included: an order is delivered, or cancelled by the desk, within
  two weeks of being placed, so an order left unpaid is the desk's to cancel.

  The promise waits on the carrier: the dispatcher hands a parcel to the carrier's
  collection, and a carrier that is down collects nothing, though no step before the
  delivery it reports calls it. The carrier down inside the day excuses a parcel not yet
  handed over.
  """

  use EhosContract.Process,
    id: "fulfilment.order",
    domain: Fulfilment.Domain,
    label: "An order, from its placing to its delivery",
    accountable: :dispatcher

  correlate :order_id

  stage :ordering, "Ordering",
    include: [{Fulfilment.Contracts.Orders, [:placed, :payment_confirmed, :cancelled]}]

  stage :picking, "Picking",
    include: [{Fulfilment.Contracts.Warehouse, [:opened, :assigned, :picked, :parcel_packed]}]

  stage :shipping, "Shipping",
    include: [{Fulfilment.Contracts.Shipping, [:booked, :dispatched, :delivered]}]

  ends_on [:delivered, :cancelled]

  promise :dispatched_within_a_day_of_payment do
    from :payment_confirmed
    eventually :dispatched
    within {24, :hour}
    waits_on [:carrier]
  end

  deadline {14, :day}

  @paid %{order_id: "order-1", warehouse_id: "w-1"}

  scenario "dispatched the evening of the payment — kept", verdict: :satisfied, via: :eventually do
    given :placed, %{order_id: "order-1", warehouse_id: "w-1", items: 3},
      at: "2026-09-01T09:00:00Z"

    given :payment_confirmed, @paid, at: "2026-09-08T09:00:00Z"
    given :dispatched, %{order_id: "order-1"}, at: "2026-09-08T18:00:00Z"
    promise :dispatched_within_a_day_of_payment, at: "2026-09-10T09:00:00Z"
  end

  scenario "dispatched two days after the payment — broken", verdict: :violated do
    given :payment_confirmed, @paid, at: "2026-09-08T09:00:00Z"
    given :dispatched, %{order_id: "order-1"}, at: "2026-09-10T09:00:00Z"
    promise :dispatched_within_a_day_of_payment, at: "2026-09-11T09:00:00Z"
  end

  scenario "the carrier down inside the day — suspended", verdict: :suspended do
    given :payment_confirmed, @paid, at: "2026-09-08T09:00:00Z"
    outage :carrier, at: "2026-09-08T15:00:00Z"
    promise :dispatched_within_a_day_of_payment, at: "2026-09-10T09:00:00Z"
  end

  scenario "paid this morning — still running", verdict: :pending do
    given :payment_confirmed, @paid, at: "2026-09-08T09:00:00Z"
    promise :dispatched_within_a_day_of_payment, at: "2026-09-08T12:00:00Z"
  end
end
