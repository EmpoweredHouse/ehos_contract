defmodule EhOsContract.Migrations.V03 do
  @moduledoc false

  # The log becomes a store, in place (v2 §10, plan stage E2).
  #
  # **The table keeps its name.** `EhOsContract.Migrations` reads the schema version
  # from the comment on `eh_os_contract_events`, and a new table would take the
  # comment with it into a rename. `ALTER TABLE` keeps the comment.
  #
  # What it adds, all of it from v2 §10.3:
  #
  #   * `position`, the order of appends and the primary key. Rows already in the log
  #     get positions in `occurred_at` order, so a reader walking positions sees the
  #     history in the order it happened. `id` stays unique and stays what the Ecto
  #     schema calls its primary key, so every v1 lookup by id keeps working.
  #   * streams (`stream_id`, `stream_version`), `tags`, `schema_version`, `command_id`,
  #     `metadata` and `recorded_at`. Old rows get `recorded_at = occurred_at`, which is
  #     the best either column knows. The time of this migration would be a claim
  #     about every row, and a false one.
  #   * `actor` becomes NOT NULL. The emitter never wrote nil, so only rows written
  #     around it can be affected, and those get the system actor.
  #   * one advisory lock for every append (v2 §10.2). The key lives in exactly one
  #     place, `eh_os_contract_append_lock()`. `EhOsContract.Store.Postgres` calls
  #     that function, and so does a statement-level trigger that catches an insert
  #     going around the store. The lock is transaction-scoped and re-entrant, so
  #     taking it twice costs nothing.
  #   * append-only: UPDATE, DELETE and TRUNCATE are refused by trigger. A test
  #     database that leaked rows is recovered with `ecto.drop`, as `CLAUDE.md` says.
  #   * `eh_os_contract_commands`, which will replace `_handler_failures` (v2 §10.3).
  #     Nothing writes it yet. It is here so that the stage that starts writing it
  #     does not need a V04.
  #
  # The key is the first eight bytes of sha256("eh_os_contract_events append"),
  # read as a signed integer. Its value does not matter, as long as it never changes
  # and nothing else in the database takes the same one.

  use Ecto.Migration

  @lock_key -1_231_462_987_025_514_095

  @doc false
  @spec up() :: :ok
  def up do
    alter table(:eh_os_contract_events) do
      add :position, :bigint
      add :schema_version, :integer, null: false, default: 1
      add :stream_id, :text
      add :stream_version, :bigint
      add :tags, {:array, :text}, null: false, default: []
      add :command_id, :binary_id
      add :metadata, :map, null: false, default: %{}
      add :recorded_at, :utc_datetime_usec
    end

    execute """
    UPDATE eh_os_contract_events AS e
    SET position = ordered.n, recorded_at = e.occurred_at
    FROM (SELECT id, row_number() OVER (ORDER BY occurred_at, id) AS n
          FROM eh_os_contract_events) AS ordered
    WHERE e.id = ordered.id
    """

    execute "UPDATE eh_os_contract_events SET actor = 'system' WHERE actor IS NULL"

    execute """
    ALTER TABLE eh_os_contract_events
      ALTER COLUMN position SET NOT NULL,
      ALTER COLUMN position ADD GENERATED ALWAYS AS IDENTITY (CACHE 1),
      ALTER COLUMN recorded_at SET NOT NULL,
      ALTER COLUMN recorded_at SET DEFAULT clock_timestamp(),
      ALTER COLUMN actor SET NOT NULL,
      DROP CONSTRAINT eh_os_contract_events_pkey,
      ADD CONSTRAINT eh_os_contract_events_pkey PRIMARY KEY (position),
      ADD CONSTRAINT eh_os_contract_events_id_key UNIQUE (id),
      ADD CONSTRAINT eh_os_contract_events_stream_pair
        CHECK ((stream_id IS NULL) = (stream_version IS NULL)),
      ADD CONSTRAINT eh_os_contract_events_stream_version_positive CHECK (stream_version > 0)
    """

    # The identity starts after the positions just assigned. `false`: the next value
    # handed out is exactly this one.
    execute """
    SELECT setval(pg_get_serial_sequence('eh_os_contract_events', 'position'),
                  coalesce(max(position), 0) + 1, false)
    FROM eh_os_contract_events
    """

    create unique_index(:eh_os_contract_events, [:stream_id, :stream_version],
             where: "stream_id IS NOT NULL",
             name: :eh_os_contract_events_stream_index
           )

    create index(:eh_os_contract_events, [:tags], using: :gin)
    create index(:eh_os_contract_events, [:type, :position])
    create index(:eh_os_contract_events, [:command_id])
    create index(:eh_os_contract_events, [:contract, :contract_version])

    execute """
    CREATE FUNCTION eh_os_contract_append_lock() RETURNS void LANGUAGE sql AS
    $$ SELECT pg_advisory_xact_lock(#{@lock_key}) $$
    """

    execute """
    CREATE FUNCTION eh_os_contract_events_take_append_lock() RETURNS trigger LANGUAGE plpgsql AS
    $$ BEGIN PERFORM eh_os_contract_append_lock(); RETURN NULL; END $$
    """

    execute """
    CREATE FUNCTION eh_os_contract_events_refuse_change() RETURNS trigger LANGUAGE plpgsql AS
    $$ BEGIN
      RAISE EXCEPTION 'eh_os_contract_events is append-only: % is refused', TG_OP
        USING ERRCODE = 'restrict_violation';
    END $$
    """

    execute """
    CREATE TRIGGER eh_os_contract_events_append_lock
    BEFORE INSERT ON eh_os_contract_events
    FOR EACH STATEMENT EXECUTE FUNCTION eh_os_contract_events_take_append_lock()
    """

    execute """
    CREATE TRIGGER eh_os_contract_events_append_only
    BEFORE UPDATE OR DELETE ON eh_os_contract_events
    FOR EACH STATEMENT EXECUTE FUNCTION eh_os_contract_events_refuse_change()
    """

    execute """
    CREATE TRIGGER eh_os_contract_events_no_truncate
    BEFORE TRUNCATE ON eh_os_contract_events
    FOR EACH STATEMENT EXECUTE FUNCTION eh_os_contract_events_refuse_change()
    """

    create table(:eh_os_contract_commands, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :contract, :text, null: false
      add :type, :text, null: false
      add :issued_by, :text, null: false
      add :idempotency_key, :text
      add :causation_event_id, :binary_id
      add :correlation_id, :binary_id, null: false
      add :outcome, :text, null: false
      add :invariant, :text
      add :failed_in, :text
      add :error, :text
      add :given_types, {:array, :text}, null: false, default: []
      add :emitted_types, {:array, :text}, null: false, default: []
      add :first_position, :bigint
      add :last_position, :bigint
      add :process, :text
      add :instance_id, :text
      add :recorded_at, :utc_datetime_usec, null: false, default: fragment("clock_timestamp()")
    end

    create constraint(:eh_os_contract_commands, :eh_os_contract_commands_outcome,
             check: "outcome IN ('accepted', 'rejected', 'failed')"
           )

    create unique_index(:eh_os_contract_commands, [:idempotency_key],
             where: "outcome = 'accepted' AND idempotency_key IS NOT NULL",
             name: :eh_os_contract_commands_idempotency_index
           )

    :ok
  end

  @doc false
  @spec down() :: :ok
  def down do
    drop table(:eh_os_contract_commands)

    execute "DROP TRIGGER eh_os_contract_events_no_truncate ON eh_os_contract_events"
    execute "DROP TRIGGER eh_os_contract_events_append_only ON eh_os_contract_events"
    execute "DROP TRIGGER eh_os_contract_events_append_lock ON eh_os_contract_events"
    execute "DROP FUNCTION eh_os_contract_events_refuse_change()"
    execute "DROP FUNCTION eh_os_contract_events_take_append_lock()"
    execute "DROP FUNCTION eh_os_contract_append_lock()"

    drop index(:eh_os_contract_events, [:contract, :contract_version])
    drop index(:eh_os_contract_events, [:command_id])
    drop index(:eh_os_contract_events, [:type, :position])
    drop index(:eh_os_contract_events, [:tags])

    drop index(:eh_os_contract_events, [:stream_id, :stream_version],
           name: :eh_os_contract_events_stream_index
         )

    # `actor` goes back to nullable but keeps the system actor it was given: v02 allowed
    # nil and did not require it, and putting nil back would erase a value.
    execute """
    ALTER TABLE eh_os_contract_events
      DROP CONSTRAINT eh_os_contract_events_pkey,
      DROP CONSTRAINT eh_os_contract_events_id_key,
      ADD CONSTRAINT eh_os_contract_events_pkey PRIMARY KEY (id),
      ALTER COLUMN actor DROP NOT NULL
    """

    alter table(:eh_os_contract_events) do
      remove :recorded_at
      remove :metadata
      remove :command_id
      remove :tags
      remove :stream_version
      remove :stream_id
      remove :schema_version
      remove :position
    end

    :ok
  end
end
