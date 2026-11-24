defmodule BusRig.ReserveForOrder do
  @moduledoc """
  **Invented.** Reserves stock for a placed order — and raises for an order of total
  13, so that a test can watch a failing policy roll its inbox row back.
  """

  use BusRig.Stock, policy: :reserve_for_order

  @impl true
  def order_placed(%OrderPlaced{total: 13}), do: raise("the warehouse is closed")

  def order_placed(%OrderPlaced{order_id: id, total: total}),
    do: issue(%ReserveStock{order_id: id, total: total})
end
