defmodule Fulfilment.Shipping do
  @moduledoc """
  **Invented.** The implementation of `Fulfilment.Contracts.Shipping`: the shipment's
  decision, and the policy that books the carrier for a packed parcel.
  """

  use Boundary, deps: [EhOsContract, Fulfilment.Contracts], exports: [Shipment, BookCarrier]
end
