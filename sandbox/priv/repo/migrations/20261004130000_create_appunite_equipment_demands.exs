defmodule EhOsContractHost.Repo.Migrations.CreateAppuniteEquipmentDemands do
  @moduledoc "The table of `AppuniteEquipment.Demanding.WaitingRows`: one row per demand still waiting."

  use Ecto.Migration

  def change do
    create table(:appunite_equipment_demands, primary_key: false) do
      add :demand_id, :string, primary_key: true
      add :employee_id, :string, null: false
      add :reason, :string, null: false
      add :starts_on, :date
      add :status, :string, null: false
      add :profile, :string
    end
  end
end
