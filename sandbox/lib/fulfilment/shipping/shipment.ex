defmodule Fulfilment.Shipping.Shipment do
  @moduledoc "**Invented.** Decides a shipment: booked once, and dispatched once it is booked."

  use Fulfilment.Contracts.Shipping, aggregate: :shipment

  @impl true
  def book_shipment(_command, %State{booked: true}), do: reject(:booked_once)

  def book_shipment(%BookShipment{} = booking, _state) do
    emit(%Booked{
      order_id: booking.order_id,
      service: booking.service,
      weight_grams: booking.weight_grams
    })
  end

  @impl true
  def dispatch_parcel(%DispatchParcel{order_id: id}, %State{booked: true, dispatched: false}),
    do: emit(%Dispatched{order_id: id})

  def dispatch_parcel(_command, _state), do: reject(:dispatched_once_when_booked)

  @impl true
  def evolve(state, %Booked{}), do: %{state | booked: true}
  def evolve(state, %Dispatched{}), do: %{state | dispatched: true}
  def evolve(state, %Delivered{}), do: state
end
