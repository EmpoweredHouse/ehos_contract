defmodule EhOsContractHost.Repo.Migrations.DropAssignmentFromAppuniteEquipmentInventory do
  @moduledoc """
  The Inventory row no longer keeps the assignment it is out on: a return brings the
  computer to the office whatever assignment it names (#99, decision 3).
  """

  use Ecto.Migration

  def change do
    alter table(:appunite_equipment_inventory) do
      remove :assignment_id, :string
    end
  end
end
