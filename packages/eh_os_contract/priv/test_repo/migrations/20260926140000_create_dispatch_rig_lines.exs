defmodule EhOsContract.TestRepo.Migrations.CreateDispatchRigLines do
  @moduledoc """
  The lines `DispatchRig`'s ordered read model projects (v2 plan, E7): one per event,
  keyed by its position, so a batch applied twice would fail on the key.
  """

  use Ecto.Migration

  def change do
    create table(:dispatch_rig_lines, primary_key: false) do
      add :position, :bigint, primary_key: true
      add :account_id, :text, null: false
      add :amount, :integer, null: false
    end
  end
end
