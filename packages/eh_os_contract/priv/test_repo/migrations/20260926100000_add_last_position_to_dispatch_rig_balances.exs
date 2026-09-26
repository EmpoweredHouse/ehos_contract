defmodule EhOsContract.TestRepo.Migrations.AddLastPositionToDispatchRigBalances do
  @moduledoc """
  How far `DispatchRig`'s balances read model has read, per row: the position of the
  last event it projected, which a projection takes from the event's `__meta__`. Not
  null, so a projection handed an event without a position fails loudly.
  """

  use Ecto.Migration

  def change do
    alter table(:dispatch_rig_balances) do
      add :last_position, :bigint, null: false
    end
  end
end
