defmodule EhosContract.Migrations.V07 do
  @moduledoc false

  # The library was called `eh_os_contract` until 0.11 (#428). V01–V06 created its
  # storage under that name and stay as databases ran them; this version renames what
  # they created, and the rows the engine itself wrote under the old name.
  #
  # Renamed by prefix, from the catalog of `current_schema()`, inside one `DO` block,
  # so that it finds what V01–V06 created earlier in the same `up/1` of a fresh
  # database: a query from Elixir would run before the queued statements did. The
  # credential package's tables share the prefix and are left to its own V04.
  #
  # Two function bodies name the old storage, and are written again: the refusal's
  # message, and the channel the log's trigger wakes, which the runners listen on
  # under the package's name. The append lock's functions hold only its key, whose
  # class stays computed from the old name: it is what every existing log takes.
  #
  # The engine's two event types, and the contract name erasures are filed under, are
  # rewritten in the log rather than read under both names: conformance and the check
  # of undeclared types filter them in SQL. Neither event seals a field, so no
  # ciphertext is bound to the type. Oban's jobs of the engine's workers are
  # rewritten too, so a timer or an effect scheduled before the upgrade still runs;
  # Oban's table is the one the `search_path` finds, where the engine's moduledoc says
  # Oban's prefix belongs.

  use Ecto.Migration

  @old "eh_os_contract"
  @new "ehos_contract"

  @doc false
  @spec up() :: :ok
  def up do
    execute EhosContract.Migrations.rename_prefix(@old <> "_", @new <> "_", @old <> "_auth_")
    execute refuse_change(@new)
    execute notify(@new)
    rows(@old, @new, "EhOsContract.", "EhosContract.")
    :ok
  end

  @doc false
  @spec down() :: :ok
  def down do
    rows(@new, @old, "EhosContract.", "EhOsContract.")
    execute EhosContract.Migrations.rename_prefix(@new <> "_", @old <> "_", @new <> "_auth_")
    execute notify(@old)
    execute refuse_change(@old)
    :ok
  end

  defp refuse_change(name) do
    """
    CREATE OR REPLACE FUNCTION #{name}_events_refuse_change() RETURNS trigger LANGUAGE plpgsql AS
    $$ BEGIN
      RAISE EXCEPTION '#{name}_events is append-only: % is refused', TG_OP
        USING ERRCODE = 'restrict_violation';
    END $$
    """
  end

  defp notify(name) do
    """
    CREATE OR REPLACE FUNCTION #{name}_events_notify() RETURNS trigger LANGUAGE plpgsql AS
    $$ DECLARE
      channel text := TG_TABLE_SCHEMA || '.oban_#{name}';
    BEGIN
      IF pg_catalog.octet_length(channel) < 64
         AND pg_catalog.pg_notification_queue_usage() < 0.5 THEN
        PERFORM pg_catalog.pg_notify(channel, '{}');
      END IF;
      RETURN NULL;
    END $$
    """
  end

  # The append-only trigger is off for these two statements only, inside the
  # migration's transaction, and on again before it commits. Both directions run
  # while the storage has the new names: after the rename up, before it down.
  defp rows(from, to, from_worker, to_worker) do
    table = "#{@new}_events"

    execute "ALTER TABLE #{table} DISABLE TRIGGER #{@new}_events_append_only"

    execute """
    UPDATE #{table}
    SET type = '#{to}.' || pg_catalog.substr(type, #{String.length(from) + 2})
    WHERE type IN ('#{from}.subject_erased', '#{from}.timer_elapsed')
    """

    execute "UPDATE #{table} SET contract = '#{to}' WHERE contract = '#{from}'"
    execute "ALTER TABLE #{table} ENABLE TRIGGER #{@new}_events_append_only"

    execute """
    DO $$ BEGIN
      IF pg_catalog.to_regclass('oban_jobs') IS NOT NULL THEN
        UPDATE oban_jobs
        SET worker = '#{to_worker}' || pg_catalog.substr(worker, #{String.length(from_worker) + 1})
        WHERE worker IN ('#{from_worker}EffectJob', '#{from_worker}TimerJob');
      END IF;
    END $$
    """
  end
end
