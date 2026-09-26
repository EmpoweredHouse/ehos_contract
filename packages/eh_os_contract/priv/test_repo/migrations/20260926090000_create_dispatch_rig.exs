defmodule EhOsContract.TestRepo.Migrations.CreateDispatchRig do
  @moduledoc """
  The tables of `DispatchRig`'s read models, an invented fixture's (v2 plan, E6). A
  read model writes its own tables inside the dispatch transaction, so testing that
  its failure rolls the append back needs a table to write.
  """

  use Ecto.Migration

  def change do
    create table(:dispatch_rig_balances, primary_key: false) do
      add :account_id, :text, primary_key: true
      add :branch_id, :text
      add :balance, :integer, null: false, default: 0
    end

    create table(:dispatch_rig_movements) do
      add :account_id, :text, null: false
      add :amount, :integer, null: false
    end
  end
end
