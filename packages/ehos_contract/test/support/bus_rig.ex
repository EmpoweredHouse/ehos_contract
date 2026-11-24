defmodule BusRig do
  @moduledoc """
  **An engine fixture, and invented.** Applications that exchange integration events
  over `EhosContract.Bus` (v2 plan, E12): a shop that publishes an order's placing,
  and a warehouse that reserves stock for it.
  No workshop stands behind it, and no name in it comes from one.
  """

  use Boundary, deps: [EhosContract], exports: [Shop, Orders, Warehouse, Stock]
end
