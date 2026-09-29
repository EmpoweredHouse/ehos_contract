defmodule EhOsContract.TestRepo.Migrations.CreateDispatchRig do
  @moduledoc """
  The tables of `DispatchRig`, an invented fixture's (v2 plan, E6 and E7).

    * `dispatch_rig_balances` and `dispatch_rig_movements`, its read models in the
      dispatch transaction: a read model writes its own tables there, so testing that
      its failure rolls the append back needs a table to write. `last_position` is
      how far a balance has read, taken from the event's `__meta__`, and not null, so
      a projection handed an event without a position fails loudly.
    * `dispatch_rig_notices`, what its effect writes when an account is flagged: one
      per event, so a second delivery of the same event writes nothing.
    * `dispatch_rig_lines`, what its ordered read model projects: one per event,
      keyed by its position, so a batch applied twice would fail on the key.
  """

  use Ecto.Migration

  def change do
    create table(:dispatch_rig_balances, primary_key: false) do
      add :account_id, :text, primary_key: true
      add :branch_id, :text
      add :balance, :integer, null: false, default: 0
      add :last_position, :bigint, null: false
    end

    create table(:dispatch_rig_movements) do
      add :account_id, :text, null: false
      add :amount, :integer, null: false
    end

    create table(:dispatch_rig_notices, primary_key: false) do
      add :event_id, :binary_id, primary_key: true
      add :account_id, :text, null: false
    end

    create table(:dispatch_rig_lines, primary_key: false) do
      add :position, :bigint, primary_key: true
      add :account_id, :text, null: false
      add :amount, :integer, null: false
    end
  end
end
