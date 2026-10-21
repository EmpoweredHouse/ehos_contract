defmodule Fulfilment.Shipping.BookCarrier do
  @moduledoc """
  **Invented.** Books the carrier for a packed parcel: as freight over twenty
  kilograms, as a parcel otherwise. It reads the warehouse's `weight_grams`, so a rename
  of that field is refused here by the compiler, at the pattern that names it.
  """

  use Fulfilment.Contracts.Shipping, policy: :book_carrier

  @freight 20_000

  @impl true
  def parcel_packed(%ParcelPacked{order_id: order, weight_grams: grams}) when grams > @freight,
    do: issue(%BookShipment{order_id: order, service: :freight, weight_grams: grams})

  def parcel_packed(%ParcelPacked{order_id: order, weight_grams: grams}),
    do: issue(%BookShipment{order_id: order, service: :parcel, weight_grams: grams})
end
