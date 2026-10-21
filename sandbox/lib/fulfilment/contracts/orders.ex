defmodule Fulfilment.Contracts.Orders do
  @moduledoc """
  **Invented.** Orders: the order desk places an order for one warehouse, confirms its
  payment, or cancels it while it is unpaid.
  """

  use EhOsContract.Contract,
    domain: Fulfilment.Domain,
    context: :orders,
    id: "fulfilment.orders"

  aggregate :order, "Order" do
    identity :order_id

    state do
      field :placed, :boolean, default: false
      field :warehouse_id, :id, optional: true
      field :paid, :boolean, default: false
      field :cancelled, :boolean, default: false
    end

    invariant :placed_once, "An order is placed once"
    invariant :paid_once_while_open, "An order still open is paid, once"

    invariant :only_an_open_unpaid_order_is_cancelled,
              "Only an order still open and unpaid is cancelled"

    command :place_order, "Place an order",
      by: :order_desk,
      emits: :placed,
      rejects: :placed_once do
      field :warehouse_id, :id
      field :items, :integer
    end

    command :confirm_payment, "Confirm an order's payment",
      by: :order_desk,
      emits: :payment_confirmed,
      rejects: :paid_once_while_open

    command :cancel_order, "Cancel an order",
      by: :order_desk,
      emits: :cancelled,
      rejects: :only_an_open_unpaid_order_is_cancelled

    event :placed, "Order placed" do
      field :warehouse_id, :id
      field :items, :integer
    end

    event :payment_confirmed, "Payment confirmed" do
      field :warehouse_id, :id
    end

    event :cancelled, "Order cancelled"
  end

  @placed %{order_id: "order-1", warehouse_id: "w-1", items: 3}

  scenario "an order is placed" do
    command :place_order, @placed
    expect :placed, %{warehouse_id: "w-1"}
  end

  scenario "an order is placed once" do
    given :placed, @placed
    command :place_order, %{warehouse_id: "w-1", items: 3}
    rejected :placed_once
  end

  scenario "an order's payment is confirmed" do
    given :placed, @placed
    command :confirm_payment
    expect :payment_confirmed, %{warehouse_id: "w-1"}
  end

  scenario "an order is paid once" do
    given :placed, @placed
    given :payment_confirmed, %{warehouse_id: "w-1"}
    command :confirm_payment
    rejected :paid_once_while_open
  end

  scenario "a cancelled order is not paid" do
    given :placed, @placed
    given :cancelled
    command :confirm_payment
    rejected :paid_once_while_open
  end

  scenario "an unpaid order is cancelled" do
    given :placed, @placed
    command :cancel_order
    expect :cancelled
  end

  scenario "a cancelled order is not cancelled again" do
    given :placed, @placed
    given :cancelled
    command :cancel_order
    rejected :only_an_open_unpaid_order_is_cancelled
  end

  scenario "a paid order is not cancelled" do
    given :placed, @placed
    given :payment_confirmed, %{warehouse_id: "w-1"}
    command :cancel_order
    rejected :only_an_open_unpaid_order_is_cancelled
  end
end
