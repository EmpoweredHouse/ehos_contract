defmodule EhOsContractHost.Repo.Migrations.CreateAppuniteEquipmentInventory do
  @moduledoc "The table of `AppuniteEquipment.Inventory.InventoryRows`: one row per computer."

  use Ecto.Migration

  def change do
    create table(:appunite_equipment_inventory, primary_key: false) do
      add :computer_id, :string, primary_key: true
      add :profile, :string, null: false
      add :serial_number, :string
      add :chip, :string
      add :status, :string, null: false
      add :set_up, :boolean, null: false
      add :employee_id, :string
      add :assignment_id, :string
      add :asking_price, :bigint
      add :reserved, :boolean, null: false
    end
  end
end
