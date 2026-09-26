defmodule EhOsContract.TestRepo.Migrations.CreateDispatchRigNotices do
  @moduledoc """
  The notices `DispatchRig`'s effect writes when an account is flagged (v2 plan, E7):
  one per event, so a second delivery of the same event writes nothing.
  """

  use Ecto.Migration

  def change do
    create table(:dispatch_rig_notices, primary_key: false) do
      add :event_id, :binary_id, primary_key: true
      add :account_id, :text, null: false
    end
  end
end
