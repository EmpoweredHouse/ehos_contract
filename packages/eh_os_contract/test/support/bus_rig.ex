defmodule BusRig do
  @moduledoc """
  **An engine fixture, and invented.** Applications that exchange integration events
  over `EhOsContract.Bus` (v2 plan, E12): a shop that publishes an order's placing.
  No workshop stands behind it, and no name in it comes from one.
  """

  use Boundary, deps: [EhOsContract], exports: [Shop, Orders]
end
