defmodule EhOsContractHost.Repo.Migrations.DropAssignmentFromAppuniteEquipmentInventory do
  @moduledoc """
  The Inventory row no longer keeps the assignment it is out on: a return brings the
  computer to the office whatever assignment it names (#99, decision 3). If it exists:
  #120 added the column by editing the table's first migration, so a database migrated
  before it never had one.

  `up/0` and `down/0` rather than `change/0`, which cannot reverse `remove_if_exists`.
  Rolling back gives the table the column, as the first migration has it today, on a
  database that never had one too: the schema the code before this migration reads.
  """

  use Ecto.Migration

  def up do
    alter table(:appunite_equipment_inventory) do
      remove_if_exists :assignment_id, :string
    end
  end

  def down do
    alter table(:appunite_equipment_inventory) do
      add_if_not_exists :assignment_id, :string
    end
  end
end
