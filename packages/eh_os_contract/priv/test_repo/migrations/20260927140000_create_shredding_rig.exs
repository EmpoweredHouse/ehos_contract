defmodule EhOsContract.TestRepo.Migrations.CreateShreddingRig do
  @moduledoc """
  The tables of `ShreddingRig`'s read models (v2 plan, E8): members, projected in
  the dispatch transaction, and member names, projected after it. Both keep a
  member's name in the clear, which is why each forgets an erased member.
  """

  use Ecto.Migration

  def change do
    create table(:shredding_rig_members, primary_key: false) do
      add :membership_id, :text, primary_key: true
      add :member_id, :text, null: false
      add :name, :text
    end

    create table(:shredding_rig_member_names, primary_key: false) do
      add :membership_id, :text, primary_key: true
      add :member_id, :text, null: false
      add :name, :text
    end
  end
end
