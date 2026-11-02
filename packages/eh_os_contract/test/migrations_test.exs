defmodule EhOsContract.MigrationsTest.Host do
  @moduledoc "A host's migration, as the moduledoc of `EhOsContract.Migrations` tells one to write."

  use Ecto.Migration

  def up, do: EhOsContract.Migrations.up()
  def down, do: EhOsContract.Migrations.down()
end

defmodule EhOsContract.MigrationsTest do
  @moduledoc """
  v2 plan, E11c: **the engine's storage is V01, in its final shape** — created from
  nothing, dropped to nothing, and created again — and since plan DD, T2a (#240), a
  second version, V02, which a host runs as a migration of its own; since plan DD, P2h
  (#221), a third, V03, the first that removes columns.

  Runs against `EhOsContract.CommitRepo`, because migrations commit and the sandbox
  would roll them back. Rolling back the package's first migration rolls back every
  later one of the test database too, so every test leaves it migrated in full.
  """

  use ExUnit.Case, async: false

  alias EhOsContract.CommitRepo, as: Repo

  @add_eh_os_contract 20_260_821_000_000

  @tables ~w(
    eh_os_contract_commands
    eh_os_contract_dependency_observations
    eh_os_contract_deployments
    eh_os_contract_erasures
    eh_os_contract_event_runs
    eh_os_contract_events
    eh_os_contract_inbox
    eh_os_contract_process_managers
    eh_os_contract_subject_keys
    eh_os_contract_subscriptions
  )

  @functions ~w(
    eh_os_contract_append_lock
    eh_os_contract_events_refuse_change
    eh_os_contract_events_take_append_lock
  )

  setup do
    on_exit(fn -> migrate(:up, all: true) end)
    :ok
  end

  defp migrate(direction, opts), do: Repo.migrate(direction, opts)

  defp one(sql, params \\ []), do: Repo.query!(sql, params).rows |> List.first() |> List.first()

  defp column(sql, params \\ []),
    do: Repo.query!(sql, params).rows |> List.flatten() |> Enum.sort()

  defp version do
    one("SELECT obj_description('public.eh_os_contract_events'::regclass, 'pg_class')")
  end

  # The engine's own tables, which the auth package's (`eh_os_contract_auth_*`) are not.
  defp tables do
    column("""
    SELECT table_name FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name LIKE 'eh\\_os\\_contract\\_%'
      AND table_name NOT LIKE 'eh\\_os\\_contract\\_auth\\_%'
    """)
  end

  defp functions do
    column("""
    SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname LIKE 'eh\\_os\\_contract\\_%'
    """)
  end

  defp triggers do
    column(
      "SELECT tgname FROM pg_trigger WHERE tgrelid = 'eh_os_contract_events'::regclass AND NOT tgisinternal"
    )
  end

  test "V01 creates the whole store, V02 adds what a decision read, V03 drops a contract's run, V04 adds the words' digest, V05 the status a subscription failed in" do
    assert EhOsContract.Migrations.initial_version() == 1
    assert EhOsContract.Migrations.current_version() == 5
    assert version() == "5"

    # Issue #550: a failing subscription keeps the status it failed in, for a skip.
    assert resume_status?()

    # Plan DD, V5 (#322): a deployment records its words beside its version, and a change
    # of the words alone is a row of its own.
    assert words_columns() == ["text_digest", "text_digests"]
    assert versions_index() =~ "(contract, contract_version, wiring_version, text_digest)"

    # Plan DD, P2h (#221): a contract no longer declares a process, so no event and no
    # command has a run of its own; an event's runs are the rows of the index of runs.
    assert runs_columns() == %{events: [], commands: []}

    assert column("""
           SELECT column_name FROM information_schema.columns
           WHERE table_name = 'eh_os_contract_event_runs'
           """) == ["instance_id", "position", "process"]

    # Plan DD, T2a (#240).
    assert one("""
           SELECT data_type FROM information_schema.columns
           WHERE table_name = 'eh_os_contract_commands' AND column_name = 'inputs'
           """) == "jsonb"

    assert tables() == @tables
    assert functions() == @functions

    assert triggers() == [
             "eh_os_contract_events_append_lock",
             "eh_os_contract_events_append_only",
             "eh_os_contract_events_no_truncate"
           ]

    assert one("""
           SELECT string_agg(a.attname, ',')
           FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
           WHERE i.indrelid = 'eh_os_contract_events'::regclass AND i.indisprimary
           """) == "position"

    # The database hands out positions, and nothing may choose one: `a` is ALWAYS.
    assert one("""
           SELECT attidentity FROM pg_attribute
           WHERE attrelid = 'eh_os_contract_events'::regclass AND attname = 'position'
           """) == "a"

    # `id` is not the primary key any more, and still unique.
    assert one("""
           SELECT pg_get_constraintdef(oid) FROM pg_constraint
           WHERE conname = 'eh_os_contract_events_id_key'
           """) == "UNIQUE (id)"

    # The conformance queries find one contract's commands by outcome and time (#185).
    assert one("""
           SELECT pg_get_indexdef(indexrelid) FROM pg_index
           WHERE indexrelid = 'eh_os_contract_commands_contract_outcome_recorded_at_index'::regclass
           """) =~ "btree (contract, outcome, recorded_at)"
  end

  test "no column of the engine's tables is limited to 255 characters" do
    assert column(
             """
             SELECT table_name || '.' || column_name FROM information_schema.columns
             WHERE table_schema = 'public' AND table_name = ANY($1)
               AND (data_type = 'character varying'
                    OR (data_type = 'ARRAY' AND udt_name = '_varchar'))
             """,
             [@tables]
           ) == []
  end

  test "down drops every table and function V01 created, and up creates them again" do
    migrate(:down, to: @add_eh_os_contract)

    assert tables() == []
    assert functions() == []

    migrate(:up, all: true)

    assert version() == "5"
    assert tables() == @tables
    assert functions() == @functions
  end

  # The host's second migration, `up(version: 2)` (plan DD, T2a, #240), and its third,
  # `up(version: 3)` (plan DD, P2h, #221).
  @upgrade_to_v2 20_261_007_120_000
  @upgrade_to_v3 20_261_013_120_000
  @upgrade_to_v4 20_261_016_120_000
  @upgrade_to_v5 20_261_102_120_000

  defp resume_status? do
    one("""
    SELECT count(*) FROM information_schema.columns
    WHERE table_name = 'eh_os_contract_subscriptions' AND column_name = 'resume_status'
    """) == 1
  end

  defp words_columns do
    column("""
    SELECT column_name FROM information_schema.columns
    WHERE table_name = 'eh_os_contract_deployments' AND column_name LIKE 'text\\_%'
    """)
  end

  defp versions_index do
    one("""
    SELECT pg_get_indexdef('eh_os_contract_deployments_versions_index'::regclass)
    """)
  end

  defp deployment!(text_digest, at) do
    Repo.query!(
      """
      INSERT INTO eh_os_contract_deployments
        (id, contract, contract_version, wiring_version, events, edges, text_digest, first_seen_at)
      VALUES (gen_random_uuid(), 'MigrationsTest', 'v', 'w', '{}', '{}', $1, $2)
      """,
      [text_digest, at]
    )
  end

  # The columns that filed an event and a command under a contract's process, by table.
  defp runs_columns do
    for table <- [:events, :commands], into: %{} do
      {table,
       column(
         """
         SELECT column_name || ' ' || is_nullable FROM information_schema.columns
         WHERE table_name = $1 AND column_name IN ('process', 'instance_id')
         """,
         ["eh_os_contract_#{table}"]
       )}
    end
  end

  defp inputs? do
    one("""
    SELECT count(*) FROM information_schema.columns
    WHERE table_name = 'eh_os_contract_commands' AND column_name = 'inputs'
    """) == 1
  end

  test "a host's upgrades roll back one at a time, and run again" do
    # Two deployments that differ only in their words: the index of three columns that
    # V04 gives back holds one, the first, which says since when the version ran.
    deployment!("t1", ~U[2026-10-01 00:00:00.000000Z])
    deployment!("t2", ~U[2026-10-02 00:00:00.000000Z])

    on_exit(fn ->
      Repo.query!("DELETE FROM eh_os_contract_deployments WHERE contract = 'MigrationsTest'")
    end)

    migrate(:down, to: @upgrade_to_v5)

    assert version() == "4"
    refute resume_status?()

    # Issue #550: before V05, dispatch went on projecting an inline read model that
    # failed while it was rebuilt, so V05 has it rebuilt from the start.
    Repo.query!(
      "INSERT INTO eh_os_contract_subscriptions (name, kind, mode, version, status) " <>
        "VALUES ('MigrationsTest', 'read_model', 'inline', 'v', 'failing'), " <>
        "('MigrationsTest:ordered', 'read_model', 'ordered', 'v', 'failing')"
    )

    on_exit(fn ->
      Repo.query!("DELETE FROM eh_os_contract_subscriptions WHERE name LIKE 'MigrationsTest%'")
    end)

    migrate(:up, all: true)

    assert column("""
           SELECT name || ' ' || status || ' ' || coalesce(resume_status, '-')
           FROM eh_os_contract_subscriptions WHERE name LIKE 'MigrationsTest%' ORDER BY name
           """) == ["MigrationsTest stale -", "MigrationsTest:ordered failing -"]

    migrate(:down, to: @upgrade_to_v5)

    migrate(:down, to: @upgrade_to_v4)

    assert version() == "3"
    assert words_columns() == []
    assert versions_index() =~ "(contract, contract_version, wiring_version)"

    assert one("""
           SELECT min(first_seen_at)::text FROM eh_os_contract_deployments
           WHERE contract = 'MigrationsTest'
           """) =~ "2026-10-01"

    assert one(
             "SELECT count(*) FROM eh_os_contract_deployments WHERE contract = 'MigrationsTest'"
           ) == 1

    migrate(:down, to: @upgrade_to_v3)

    # V03 gives the columns back, empty and nullable as they always were.
    assert version() == "2"
    assert inputs?()

    assert runs_columns() == %{
             events: ["instance_id YES", "process YES"],
             commands: ["instance_id YES", "process YES"]
           }

    migrate(:down, to: @upgrade_to_v2)

    assert version() == "1"
    refute inputs?()
    assert tables() == @tables

    migrate(:up, all: true)

    assert version() == "5"
    assert inputs?()
    assert runs_columns() == %{events: [], commands: []}
    assert words_columns() == ["text_digest", "text_digests"]
    assert resume_status?()
  end

  # A version no migration file in the test database has, so running it touches
  # nothing but this test's row in `schema_migrations`.
  @host_version 99_990_101_000_000

  test "a database recording a version this release does not know is refused, both ways" do
    Repo.query!("COMMENT ON TABLE eh_os_contract_events IS '6'")

    Repo.query!(
      "INSERT INTO schema_migrations (version, inserted_at) VALUES ($1, now())",
      [@host_version]
    )

    on_exit(fn ->
      Repo.query!("DELETE FROM schema_migrations WHERE version = $1", [@host_version])
      current = EhOsContract.Migrations.current_version()
      Repo.query!("COMMENT ON TABLE eh_os_contract_events IS '#{current}'")
    end)

    refused = ~r/records version 6, and this release of eh_os_contract knows versions up to/

    assert_raise ArgumentError, refused, fn ->
      Ecto.Migrator.down(Repo, @host_version, EhOsContract.MigrationsTest.Host, log: false)
    end

    Repo.query!("DELETE FROM schema_migrations WHERE version = $1", [@host_version])

    assert_raise ArgumentError, refused, fn ->
      Ecto.Migrator.up(Repo, @host_version, EhOsContract.MigrationsTest.Host, log: false)
    end

    # Nothing ran: the tables are there, and the database still says what it said.
    assert tables() == @tables
    assert version() == "6"
  end

  test "a database migrated before 0.3.0 is refused by its column, whatever it records" do
    Repo.query!("ALTER TABLE eh_os_contract_events ADD COLUMN instance_id text")
    on_exit(fn -> Repo.query!("ALTER TABLE eh_os_contract_events DROP COLUMN instance_id") end)

    assert_raise ArgumentError, ~r/records version 5, and it was migrated before 0\.3\.0/, fn ->
      Ecto.Migrator.up(Repo, @host_version, EhOsContract.MigrationsTest.Host, log: false)
    end

    assert version() == "5"
  end

  test "a version this release does not have is refused as a target" do
    assert_raise ArgumentError, ~r/and 6 is not one of them/, fn ->
      EhOsContract.Migrations.up(version: 6)
    end

    assert_raise ArgumentError, ~r/and 0 is not one of them/, fn ->
      EhOsContract.Migrations.down(version: 0)
    end
  end

  test "the tables refuse what their checks refuse, whoever writes it" do
    assert_raise Postgrex.Error, ~r/eh_os_contract_subscriptions_status/, fn ->
      Repo.query!(
        "INSERT INTO eh_os_contract_subscriptions (name, kind, mode, version, status) " <>
          "VALUES ('MigrationsTest', 'read_model', 'ordered', 'v', 'skipped')"
      )
    end

    assert_raise Postgrex.Error, ~r/eh_os_contract_subscriptions_resume_status/, fn ->
      Repo.query!(
        "INSERT INTO eh_os_contract_subscriptions " <>
          "(name, kind, mode, version, status, resume_status) " <>
          "VALUES ('MigrationsTest', 'read_model', 'ordered', 'v', 'failing', 'failing')"
      )
    end

    assert_raise Postgrex.Error, ~r/eh_os_contract_subject_keys_version/, fn ->
      Repo.query!(
        "INSERT INTO eh_os_contract_subject_keys " <>
          "(subject_type, subject_id, key_version, kek_id, wrapped_key) " <>
          "VALUES ('patient', 'patient-anna', 0, 'kek-1', '\\x00')"
      )
    end

    assert_raise Postgrex.Error, ~r/eh_os_contract_commands_outcome/, fn ->
      Repo.query!(
        "INSERT INTO eh_os_contract_commands (id, contract, type, issued_by, correlation_id, outcome) " <>
          "VALUES ($1, 'C', 't', 'actor:a', $2, 'skipped')",
        [Ecto.UUID.bingenerate(), Ecto.UUID.bingenerate()]
      )
    end
  end
end
