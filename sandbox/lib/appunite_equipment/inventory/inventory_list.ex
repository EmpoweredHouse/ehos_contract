defmodule AppuniteEquipment.Inventory.InventoryList do
  @moduledoc "Answers the Inventory tab: every computer, in the order they were ordered."

  use AppuniteEquipment.Contracts.Computers, query: :inventory_list

  import Ecto.Query

  @impl true
  def inventory_list(%InventoryList{}, _ctx) do
    query =
      from(r in "appunite_equipment_inventory",
        order_by: r.computer_id,
        select: %{
          computer_id: r.computer_id,
          profile: r.profile,
          serial_number: r.serial_number,
          chip: r.chip,
          status: r.status,
          set_up: r.set_up,
          employee_id: r.employee_id,
          asking_price: r.asking_price,
          reserved: r.reserved
        }
      )

    for row <- Application.fetch_env!(:eh_os_contract, :repo).all(query) do
      struct!(Row, %{
        row
        | profile: String.to_existing_atom(row.profile),
          chip: row.chip && String.to_existing_atom(row.chip),
          status: String.to_existing_atom(row.status)
      })
    end
  end
end
