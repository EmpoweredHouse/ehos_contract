defmodule Fulfilment.Shipping.Shipment do
  @moduledoc """
  **Invented.** Decides a shipment: booked once, and dispatched once it is booked. Its
  status is the lifecycle's, which the engine computes from its events.
  """

  use Fulfilment.Contracts.Shipping, aggregate: :shipment

  @impl true
  def book_shipment(_command, %State{status: status}) when status != nil,
    do: reject(:booked_once)

  def book_shipment(%BookShipment{} = booking, _state) do
    emit(%Booked{
      order_id: booking.order_id,
      service: booking.service,
      weight_grams: booking.weight_grams
    })
  end

  # The lifecycle admits it from `:booked` alone, before this runs.
  @impl true
  def dispatch_parcel(%DispatchParcel{order_id: id}, _state), do: emit(%Dispatched{order_id: id})
end
