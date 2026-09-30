defmodule EhOsContract.Migrations.V01 do
  @moduledoc false

  # The engine's storage as it stood at the cut (v2 §10.3, D2; plan stage E11c),
  # created in one step.
  #
  # **The final shape, not the history.** Five versions reached this shape, one of
  # them altering v1's log in place so that v1 kept running until it was deleted.
  # Replaying them would make every new consumer pay for the move, and create two v1
  # tables nothing reads. Nothing is migrated from before the cut: there was no
  # consumer to migrate, so a database with an older schema is recreated.
  #
  # Text is `text`, never `varchar(255)`: a limit nobody chose is a failure waiting
  # for the first long name. Times are Ecto's `utc_datetime_usec`, as they were.
  #
  # The comments below are the reasons the earlier versions gave for each table and
  # column. They are the expensive half of a collapse to lose.

  use Ecto.Migration

  # The append lock's key is two integers, one per log: the first four bytes of
  # sha256("eh_os_contract_events append") — the engine's — and the first four of
  # sha256 of the schema the log is created in, each read as a signed integer.
  #
  # One per schema, not one per database. An advisory lock belongs to the whole
  # database, and EHOS keeps every application of an instance in one, each in a
  # schema of its own (`eh-os` D-54): a single fixed key made all of them append one
  # after another (issue #51, v2 §10.2). Two integers are PostgreSQL's other key
  # space, apart from every single-integer key anybody takes. The key is computed
  # here and written into the SQL, so neither function resolves anything through a
  # `search_path`, and `pg_dump` of one schema carries its key with it. The store's
  # call of `eh_os_contract_append_lock()` finds it through the path, as it finds the
  # table: V01 creates both in one schema.
  <<lock_class::signed-32, _::binary>> = :crypto.hash(:sha256, "eh_os_contract_events append")
  @lock_class lock_class

  @doc false
  @spec lock_key(String.t()) :: {integer(), integer()}
  def lock_key(schema) do
    <<log::signed-32, _::binary>> = :crypto.hash(:sha256, schema)
    {@lock_class, log}
  end

  @doc false
  @spec up() :: :ok
  def up do
    events(current_schema!())
    event_runs()
    commands()
    subscriptions()
    process_managers()
    subject_keys()
    erasures()
    deployments()
    dependency_observations()
    :ok
  end

  @doc false
  @spec down() :: :ok
  def down do
    drop table(:eh_os_contract_dependency_observations)
    drop table(:eh_os_contract_deployments)
    drop table(:eh_os_contract_erasures)
    drop table(:eh_os_contract_subject_keys)
    drop table(:eh_os_contract_process_managers)
    drop table(:eh_os_contract_subscriptions)
    drop table(:eh_os_contract_commands)
    drop table(:eh_os_contract_event_runs)
    drop table(:eh_os_contract_events)

    execute "DROP FUNCTION eh_os_contract_events_refuse_change()"
    execute "DROP FUNCTION eh_os_contract_events_take_append_lock()"
    execute "DROP FUNCTION eh_os_contract_append_lock()"

    :ok
  end

  # Where `create table` puts the log: the first schema of the `search_path` that
  # exists. `EhOsContract.Migrations` has flushed what the host queued before it.
  defp current_schema! do
    case repo().query!("SELECT current_schema()", [], log: false).rows do
      [[schema]] when is_binary(schema) ->
        schema

      _none ->
        raise ArgumentError,
              "eh_os_contract creates its tables in the first schema of the search_path " <>
                "that exists, and this connection's search_path names none"
    end
  end

  # The log (v2 §10). Append-only, ordered by `position`, one advisory lock for every
  # append to it.
  defp events(schema) do
    create table(:eh_os_contract_events, primary_key: false) do
      # The order of appends. `id` is unique and is what the Ecto schema calls its
      # primary key; `position` is the table's.
      add :position, :bigint, primary_key: true
      add :id, :binary_id, null: false
      # "<process>.<event>"
      add :type, :text, null: false
      add :schema_version, :integer, null: false, default: 1
      add :contract, :text, null: false
      # Which agreement was in force. Without it, every deploy that removes an event
      # produces false alarms in the overlay.
      add :contract_version, :text, null: false
      # 'accounting_month:c-1|p-7'; nil for an event that belongs to no stream.
      add :stream_id, :text
      add :stream_version, :bigint
      # 'payer_id:p-1', 'visit_id:w-1'
      add :tags, {:array, :text}, null: false, default: []
      # The home run, computed at append from the fields the process correlates on.
      # Computing it in a query from the payload would tie every query to today's
      # contract version, and the log spans every version since the first deploy.
      # Every run an event belongs to is in `_event_runs`.
      add :process, :text
      add :instance_id, :text
      add :command_id, :binary_id
      add :correlation_id, :binary_id, null: false
      # The command, or the timer event, that caused it.
      add :causation_id, :binary_id
      add :actor, :text, null: false
      # The dispatcher's clock, injectable: what `Trace` and `Run` measure.
      add :occurred_at, :utc_datetime_usec, null: false
      add :recorded_at, :utc_datetime_usec, null: false, default: fragment("clock_timestamp()")
      # Personal fields as ciphertext.
      add :payload, :map, null: false, default: %{}
      # The command's type, who issued it, the chain, the idempotency key.
      add :metadata, :map, null: false, default: %{}
    end

    execute """
    ALTER TABLE eh_os_contract_events
      ALTER COLUMN position ADD GENERATED ALWAYS AS IDENTITY (CACHE 1),
      ADD CONSTRAINT eh_os_contract_events_id_key UNIQUE (id),
      ADD CONSTRAINT eh_os_contract_events_stream_pair
        CHECK ((stream_id IS NULL) = (stream_version IS NULL)),
      ADD CONSTRAINT eh_os_contract_events_stream_version_positive CHECK (stream_version > 0)
    """

    create unique_index(:eh_os_contract_events, [:stream_id, :stream_version],
             where: "stream_id IS NOT NULL",
             name: :eh_os_contract_events_stream_index
           )

    create index(:eh_os_contract_events, [:tags], using: :gin)
    create index(:eh_os_contract_events, [:type, :position])
    create index(:eh_os_contract_events, [:correlation_id])
    create index(:eh_os_contract_events, [:command_id])
    create index(:eh_os_contract_events, [:occurred_at])
    create index(:eh_os_contract_events, [:contract, :contract_version])

    # One key, `lock_key/1`'s, written into two places: `eh_os_contract_append_lock()`,
    # which `EhOsContract.Store.Postgres` calls, and a statement-level trigger that
    # catches an insert going around the store. Neither names anything the path could
    # resolve elsewhere. The lock is transaction-scoped and re-entrant, so taking it
    # twice costs nothing.
    {class, log} = lock_key(schema)

    execute """
    CREATE FUNCTION eh_os_contract_append_lock() RETURNS void LANGUAGE sql AS
    $$ SELECT pg_catalog.pg_advisory_xact_lock(#{class}, #{log}) $$
    """

    execute """
    CREATE FUNCTION eh_os_contract_events_take_append_lock() RETURNS trigger LANGUAGE plpgsql AS
    $$ BEGIN PERFORM pg_catalog.pg_advisory_xact_lock(#{class}, #{log}); RETURN NULL; END $$
    """

    # UPDATE, DELETE and TRUNCATE are refused. A test database that leaked rows is
    # recovered with `ecto.drop`, as `CLAUDE.md` says.
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
  end

  # Every run an event belongs to (D7). Rebuildable from the log.
  defp event_runs do
    create table(:eh_os_contract_event_runs, primary_key: false) do
      add :position, :bigint, primary_key: true
      add :process, :text, primary_key: true
      add :instance_id, :text, null: false
    end

    # Every per-run query runs on this: a promise, the runs on a step, one run's events.
    create index(:eh_os_contract_event_runs, [:process, :instance_id])
  end

  # One row per command: accepted, rejected on an invariant, or failed. A rejected or
  # failed command appends nothing, and this row is what survives it.
  defp commands do
    create table(:eh_os_contract_commands, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :contract, :text, null: false
      add :type, :text, null: false

      # `EhOsContract.Actor.label/1`: 'actor:<subject>' | 'system:<name>' | 'policy:<n>' | 'pm:<n>'.
      # Half of an idempotency key's scope.
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

    # A key belongs to whoever sent it: two actors with one key are two commands.
    create unique_index(:eh_os_contract_commands, [:issued_by, :idempotency_key],
             where: "outcome = 'accepted' AND idempotency_key IS NOT NULL",
             name: :eh_os_contract_commands_idempotency_index
           )
  end

  # One row per ordered consumer, and per read model delivered in the transaction.
  # `position` is the last event it applied. A runner takes the row `FOR UPDATE SKIP
  # LOCKED`, so two nodes never apply one batch, and advances it in the transaction
  # that applied the batch, so a batch is applied exactly once. `status` is
  # `running`, `stale` (its declaration changed and it has not been rebuilt),
  # `rebuilding` or `failing` (an event it could not apply, at `failed_position`;
  # never skipped by itself).
  defp subscriptions do
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
  end

  # One row per running process manager: its state, its timers, the last event it took.
  defp process_managers do
    create table(:eh_os_contract_process_managers, primary_key: false) do
      add :name, :text, primary_key: true
      add :correlation, :text, primary_key: true
      add :state, :binary, null: false
      add :timers, :map, null: false, default: %{}
      add :position, :bigint, null: false
      add :completed_at, :utc_datetime_usec
    end
  end

  # One data key per subject and key version (v2 §14), wrapped by a master key of
  # `EhOsContract.Vault`, `kek_id` naming which. The personal fields of a subject's
  # events are encrypted with it; deleting its rows is what erases the subject.
  # `key_version` is always 1 until a subject's key can be rotated, which waits for
  # someone who needs it. Not append-only: rotating a master key rewraps every data
  # key in place.
  defp subject_keys do
    create table(:eh_os_contract_subject_keys, primary_key: false) do
      add :subject_type, :text, primary_key: true
      add :subject_id, :text, primary_key: true
      add :key_version, :integer, primary_key: true
      add :kek_id, :text, null: false
      add :wrapped_key, :binary, null: false
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("clock_timestamp()")
    end

    create constraint(:eh_os_contract_subject_keys, :eh_os_contract_subject_keys_version,
             check: "key_version > 0"
           )

    # `mix eh_os_contract.rewrap` looks for the keys a retired master key still wraps.
    create index(:eh_os_contract_subject_keys, [:kek_id])
  end

  # One row per erased subject, so that nothing is appended for it again.
  defp erasures do
    create table(:eh_os_contract_erasures, primary_key: false) do
      add :subject_type, :text, primary_key: true
      add :subject_id, :text, primary_key: true
      add :erased_at, :utc_datetime_usec, null: false
      add :requested_by, :text, null: false
    end
  end

  # What was declared, and when it was in force.
  #
  # `contract_version` on an event answers which agreement was in force. It cannot
  # answer whether a **path** was wired at the time: the wiring is the modules that
  # implement the steps, and changing them changes no version stamped anywhere. One
  # row per distinct wiring that has booted, written at startup, so the graph still
  # comes from the binary that actually runs.
  defp deployments do
    create table(:eh_os_contract_deployments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :contract, :text, null: false
      add :contract_version, :text, null: false
      # Separate from `contract_version` on purpose: an implementation change alters
      # what the code does without altering what the client agreed to, and conflating
      # the two would either hide wiring changes or bump the agreement for a refactor.
      add :wiring_version, :text, null: false
      add :events, {:array, :text}, null: false
      add :edges, {:array, :text}, null: false
      # One digest per declaration, so a change to a single declaration is
      # attributable. **Nullable, and deliberately without a default**: `%{}` would
      # claim the contract declared nothing, and `EhOsContract.Deployment.diff/2` has
      # to be able to say "could not compare" instead of "nothing changed".
      add :declaration_digests, :map
      add :first_seen_at, :utc_datetime_usec, null: false
    end

    # Named explicitly: the generated name is 73 characters, and Postgres truncates
    # identifiers past 63 without an error.
    create unique_index(
             :eh_os_contract_deployments,
             [:contract, :contract_version, :wiring_version],
             name: :eh_os_contract_deployments_versions_index
           )

    create index(:eh_os_contract_deployments, [:first_seen_at])
  end

  # When a declared external dependency was seen to be unavailable.
  #
  # A promise's fourth verdict needs this and nothing else can supply it. Without it
  # a registry outage inside a promise's window counts as a **violation** — the
  # report tells a client they broke their own agreement when somebody else's server
  # was down, which is the most expensive kind of false positive this product can
  # produce.
  #
  # **Observations, not intervals.** An adapter learns that one call failed. It never
  # learns when the service came back, because nothing tells it. So each row is one
  # moment, and "was it down during this window" is answered by whether any moment
  # falls inside it. No reference to a run: a registry being down happens to
  # everybody at once.
  defp dependency_observations do
    create table(:eh_os_contract_dependency_observations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :contract, :text, null: false
      # The name from the domain's `external` declaration, never a vendor's.
      add :external, :text, null: false
      add :reason, :text
      add :observed_at, :utc_datetime_usec, null: false
    end

    # The only query there is: this dependency, within this window.
    create index(:eh_os_contract_dependency_observations, [:contract, :external, :observed_at],
             name: :eh_os_contract_dependency_observations_lookup_index
           )
  end
end
