defmodule Fulfilment.Warehouse.OpenPickListWhenPaid do
  @moduledoc "**Invented.** Opens a pick list in the order's warehouse once it is paid."

  use Fulfilment.Contracts.Warehouse, policy: :open_pick_list_when_paid

  @impl true
  def payment_confirmed(%PaymentConfirmed{order_id: order, warehouse_id: warehouse}),
    do: issue(%OpenPickList{warehouse_id: warehouse, order_id: order})
end
