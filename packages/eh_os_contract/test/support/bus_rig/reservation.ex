defmodule BusRig.Reservation do
  @moduledoc "**Invented.** The decider of `BusRig.Stock`'s reservation: it always reserves."

  use BusRig.Stock, aggregate: :reservation

  @impl true
  def reserve_stock(%ReserveStock{order_id: id, total: total}, _state),
    do: emit(%Reserved{order_id: id, total: total})
end
