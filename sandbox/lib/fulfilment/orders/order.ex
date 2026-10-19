defmodule Fulfilment.Orders.Order do
  @moduledoc """
  **Invented.** Decides an order: placed once, paid once while it is open, and
  cancelled only while it is unpaid.
  """

  use Fulfilment.Contracts.Orders, aggregate: :order

  @impl true
  def place_order(_command, %State{placed: true}), do: reject(:placed_once)

  def place_order(%PlaceOrder{} = command, _state) do
    emit(%Placed{
      order_id: command.order_id,
      warehouse_id: command.warehouse_id,
      items: command.items
    })
  end

  @impl true
  def confirm_payment(
        %ConfirmPayment{order_id: id},
        %State{placed: true, paid: false, cancelled: false} = state
      ),
      do: emit(%PaymentConfirmed{order_id: id, warehouse_id: state.warehouse_id})

  def confirm_payment(_command, _state), do: reject(:paid_once_while_open)

  @impl true
  def cancel_order(%CancelOrder{order_id: id}, %State{placed: true, paid: false, cancelled: false}),
      do: emit(%Cancelled{order_id: id})

  def cancel_order(_command, _state), do: reject(:only_an_unpaid_order_is_cancelled)

  @impl true
  def evolve(state, %Placed{warehouse_id: warehouse}),
    do: %{state | placed: true, warehouse_id: warehouse}

  def evolve(state, %PaymentConfirmed{}), do: %{state | paid: true}
  def evolve(state, %Cancelled{}), do: %{state | cancelled: true}
end
