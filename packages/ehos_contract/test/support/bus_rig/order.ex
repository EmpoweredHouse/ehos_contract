defmodule BusRig.Order do
  @moduledoc "**Invented.** The decider of `BusRig.Orders`' order."

  use BusRig.Orders, aggregate: :order

  @impl true
  def place_order(%PlaceOrder{order_id: id, total: total, note: note}, _state),
    do: emit(%Placed{order_id: id, total: total, note: note})

  @impl true
  def cancel_order(%CancelOrder{order_id: id}, _state), do: emit(%Cancelled{order_id: id})
end
