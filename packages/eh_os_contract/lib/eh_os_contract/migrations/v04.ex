defmodule EhOsContract.Migrations.V04 do
  @moduledoc false

  # The tables of the consumers that run outside the dispatch transaction (v2 §10.3,
  # §12; plan stage E7).
  #
  #   * `eh_os_contract_subscriptions`: one row per ordered consumer, and per read
  #     model delivered in the transaction. `position` is the last event it applied.
  #     A runner takes the row `FOR UPDATE SKIP LOCKED`, so two nodes never apply one
  #     batch, and advances it in the transaction that applied the batch, so a batch
  #     is applied exactly once. `status` is `running`, `stale` (its declaration
  #     changed and it has not been rebuilt), `rebuilding` or `failing` (an event it
  #     could not apply, at `failed_position`; never skipped by itself).
  #   * `eh_os_contract_process_managers`: one row per running process manager, for
  #     stage E7b.
  #   * `eh_os_contract_event_runs`: every run an event belongs to (D7), for stage E7c.
  #
  # The last two are here, as `_commands` was in V03, so that the stages that start
  # writing them do not each need a version of their own.

  use Ecto.Migration

  @doc false
  @spec up() :: :ok
  def up do
    create table(:eh_os_contract_subscriptions, primary_key: false) do
      add :name, :text, primary_key: true
      add :kind, :text, null: false
      add :mode, :text, null: false
      add :position, :bigint, null: false, default: 0
      add :version, :text, null: false
      add :status, :text, null: false, default: "running"
      add :failed_position, :bigint
      add :failure, :text
      add :attempts, :integer, null: false, default: 0
      add :updated_at, :utc_datetime_usec, null: false, default: fragment("clock_timestamp()")
    end

    create constraint(:eh_os_contract_subscriptions, :eh_os_contract_subscriptions_status,
             check: "status IN ('running', 'stale', 'rebuilding', 'failing')"
           )

    create constraint(:eh_os_contract_subscriptions, :eh_os_contract_subscriptions_mode,
             check: "mode IN ('inline', 'ordered')"
           )

    create table(:eh_os_contract_process_managers, primary_key: false) do
      add :name, :text, primary_key: true
      add :correlation, :text, primary_key: true
      add :state, :binary, null: false
      add :timers, :map, null: false, default: %{}
      add :position, :bigint, null: false
      add :completed_at, :utc_datetime_usec
    end

    create table(:eh_os_contract_event_runs, primary_key: false) do
      add :position, :bigint, primary_key: true
      add :process, :text, primary_key: true
      add :instance_id, :text, null: false
    end

    create index(:eh_os_contract_event_runs, [:process, :instance_id])

    :ok
  end

  @doc false
  @spec down() :: :ok
  def down do
    drop table(:eh_os_contract_event_runs)
    drop table(:eh_os_contract_process_managers)
    drop table(:eh_os_contract_subscriptions)
    :ok
  end
end
