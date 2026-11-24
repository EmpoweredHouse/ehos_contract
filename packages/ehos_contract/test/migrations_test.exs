defmodule EhosContract.MigrationsTest.Host do
  @moduledoc "A host's migration, as the moduledoc of `EhosContract.Migrations` tells one to write."

  use Ecto.Migration

  def up, do: EhosContract.Migrations.up()
  def down, do: EhosContract.Migrations.down()
end

defmodule EhosContract.MigrationsTest do
  @moduledoc """
  v2 plan, E11c: **the engine's storage is V01, in its final shape** — created from
  nothing, dropped to nothing, and created again — and since plan DD, T2a (#240), a
  second version, V02, which a host runs as a migration of its own; since plan DD, P2h
  (#221), a third, V03, the first that removes columns.

  Runs against `EhosContract.CommitRepo`, because migrations commit and the sandbox
  would roll them back. Rolling back the package's first migration rolls back every
  later one of the test database too, so every test leaves it migrated in full.
  """

  use ExUnit.Case, async: false

  alias EhosContract.CommitRepo, as: Repo

  @add_ehos_contract 20_260_821_000_000

  @tables ~w(
    ehos_contract_commands
    ehos_contract_dependency_observations
    ehos_contract_deployments
    ehos_contract_erasures
    ehos_contract_event_runs
    ehos_contract_events
    ehos_contract_inbox
    ehos_contract_process_managers
    ehos_contract_subject_keys
    ehos_contract_subscriptions
  )

  @functions ~w(
    ehos_contract_append_lock
    ehos_contract_events_notify
    ehos_contract_events_refuse_change
    ehos_contract_events_take_append_lock
  )

  setup do
    on_exit(fn -> migrate(:up, all: true) end)
    :ok
  end

  defp migrate(direction, opts), do: Repo.migrate(direction, opts)

  defp one(sql, params \\ []), do: Repo.query!(sql, params).rows |> List.first() |> List.first()

  defp column(sql, params \\ []),
    do: Repo.query!(sql, params).rows |> List.flatten() |> Enum.sort()

  # The storage's prefix at the version the database is at: `eh_os_contract` until V07
  # renames it (#428).
  defp p do
    if one("SELECT to_regclass('public.ehos_contract_events') IS NOT NULL"),
      do: "ehos_contract",
      else: "eh_os_contract"
  end

  defp version do
    one("SELECT obj_description('public.#{p()}_events'::regclass, 'pg_class')")
  end

  # Names under the prefix V07 gives them, whichever the database has.
  defp renamed(names),
    do: Enum.map(names, &String.replace_prefix(&1, "eh_os_contract_", "ehos_contract_"))

  # The engine's own tables, which the auth package's (`ehos_contract_auth_*`) are not.
  defp tables do
    column("""
    SELECT table_name FROM information_schema.tables
    WHERE table_schema = 'public'
      AND (table_name LIKE 'ehos\\_contract\\_%' OR table_name LIKE 'eh\\_os\\_contract\\_%')
      AND table_name NOT LIKE '%contract\\_auth\\_%'
    """)
    |> renamed()
    |> Enum.sort()
  end

  defp functions do
    column("""
    SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND (p.proname LIKE 'ehos\\_contract\\_%' OR p.proname LIKE 'eh\\_os\\_contract\\_%')
    ORDER BY p.proname
    """)
    |> renamed()
    |> Enum.sort()
  end

  defp triggers do
    column(
      "SELECT tgname FROM pg_trigger WHERE tgrelid = '#{p()}_events'::regclass " <>
        "AND NOT tgisinternal ORDER BY tgname"
    )
    |> renamed()
  end

  test "V01 creates the whole store, V02 adds what a decision read, V03 drops a contract's run, V04 adds the words' digest, V05 the status a subscription failed in, V06 the wake at commit, V07 the name" do
    assert EhosContract.Migrations.initial_version() == 1
    assert EhosContract.Migrations.current_version() == 7
    assert version() == "7"

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
           WHERE table_name = '#{p()}_event_runs'
           """) == ["instance_id", "position", "process"]

    # Plan DD, T2a (#240).
    assert one("""
           SELECT data_type FROM information_schema.columns
           WHERE table_name = '#{p()}_commands' AND column_name = 'inputs'
           """) == "jsonb"

    assert tables() == @tables
    assert functions() == @functions

    assert triggers() == [
             "ehos_contract_events_append_lock",
             "ehos_contract_events_append_only",
             "ehos_contract_events_no_truncate",
             "ehos_contract_events_notify"
           ]

    assert one("""
           SELECT string_agg(a.attname, ',')
           FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
           WHERE i.indrelid = '#{p()}_events'::regclass AND i.indisprimary
           """) == "position"

    # The database hands out positions, and nothing may choose one: `a` is ALWAYS.
    assert one("""
           SELECT attidentity FROM pg_attribute
           WHERE attrelid = '#{p()}_events'::regclass AND attname = 'position'
           """) == "a"

    # `id` is not the primary key any more, and still unique.
    assert one("""
           SELECT pg_get_constraintdef(oid) FROM pg_constraint
           WHERE conname = '#{p()}_events_id_key'
           """) == "UNIQUE (id)"

    # The conformance queries find one contract's commands by outcome and time (#185).
    assert one("""
           SELECT pg_get_indexdef(indexrelid) FROM pg_index
           WHERE indexrelid = '#{p()}_commands_contract_outcome_recorded_at_index'::regclass
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
    migrate(:down, to: @add_ehos_contract)

    assert tables() == []
    assert functions() == []

    migrate(:up, all: true)

    assert version() == "7"
    assert tables() == @tables
    assert functions() == @functions
  end

  # The host's second migration, `up(version: 2)` (plan DD, T2a, #240), and its third,
  # `up(version: 3)` (plan DD, P2h, #221).
  @upgrade_to_v2 20_261_007_120_000
  @upgrade_to_v3 20_261_013_120_000
  @upgrade_to_v4 20_261_016_120_000
  @upgrade_to_v5 20_261_102_120_000
  @upgrade_to_v6 20_261_119_120_000
  @upgrade_to_v7 20_261_124_120_000

  defp resume_status? do
    one("""
    SELECT count(*) FROM information_schema.columns
    WHERE table_name = '#{p()}_subscriptions' AND column_name = 'resume_status'
    """) == 1
  end

  defp words_columns do
    column("""
    SELECT column_name FROM information_schema.columns
    WHERE table_name = '#{p()}_deployments' AND column_name LIKE 'text\\_%'
    """)
  end

  defp versions_index do
    one("""
    SELECT pg_get_indexdef('#{p()}_deployments_versions_index'::regclass)
    """)
  end

  defp deployment!(text_digest, at) do
    Repo.query!(
      """
      INSERT INTO #{p()}_deployments
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
         ["#{p()}_#{table}"]
       )}
    end
  end

  defp inputs? do
    one("""
    SELECT count(*) FROM information_schema.columns
    WHERE table_name = '#{p()}_commands' AND column_name = 'inputs'
    """) == 1
  end

  test "a host's upgrades roll back one at a time, and run again" do
    # Two deployments that differ only in their words: the index of three columns that
    # V04 gives back holds one, the first, which says since when the version ran.
    deployment!("t1", ~U[2026-10-01 00:00:00.000000Z])
    deployment!("t2", ~U[2026-10-02 00:00:00.000000Z])

    on_exit(fn ->
      Repo.query!("DELETE FROM #{p()}_deployments WHERE contract = 'MigrationsTest'")
    end)

    # Issue #428: V07 gives the storage its old name back.
    migrate(:down, to: @upgrade_to_v7)

    assert version() == "6"
    assert p() == "eh_os_contract"
    assert tables() == @tables
    assert functions() == @functions

    # Issue #635: V06 takes its trigger and its function back, and nothing else.
    migrate(:down, to: @upgrade_to_v6)

    assert version() == "5"
    refute "ehos_contract_events_notify" in triggers()
    refute "ehos_contract_events_notify" in functions()
    assert resume_status?()

    migrate(:down, to: @upgrade_to_v5)

    assert version() == "4"
    refute resume_status?()

    # Issue #550: before V05, dispatch went on projecting an inline read model that
    # failed while it was rebuilt, so V05 has it rebuilt from the start.
    Repo.query!(
      "INSERT INTO #{p()}_subscriptions " <>
        "(name, kind, mode, version, status, failed_position, failure, attempts) " <>
        "VALUES ('MigrationsTest', 'read_model', 'inline', 'v', 'failing', 7, 'RuntimeError', 3), " <>
        "('MigrationsTest:ordered', 'read_model', 'ordered', 'v', 'failing', 7, 'RuntimeError', 3)"
    )

    on_exit(fn ->
      Repo.query!("DELETE FROM #{p()}_subscriptions WHERE name LIKE 'MigrationsTest%'")
    end)

    migrate(:up, all: true)

    assert column("""
           SELECT concat_ws(' ', name, status, coalesce(resume_status, '-'),
                            coalesce(failed_position::text, '-'), attempts)
           FROM #{p()}_subscriptions WHERE name LIKE 'MigrationsTest%' ORDER BY name
           """) == ["MigrationsTest stale - - 0", "MigrationsTest:ordered failing - 7 3"]

    migrate(:down, to: @upgrade_to_v5)

    migrate(:down, to: @upgrade_to_v4)

    assert version() == "3"
    assert words_columns() == []
    assert versions_index() =~ "(contract, contract_version, wiring_version)"

    assert one("""
           SELECT min(first_seen_at)::text FROM #{p()}_deployments
           WHERE contract = 'MigrationsTest'
           """) =~ "2026-10-01"

    assert one("SELECT count(*) FROM #{p()}_deployments WHERE contract = 'MigrationsTest'") == 1

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

    assert version() == "7"
    assert inputs?()
    assert runs_columns() == %{events: [], commands: []}
    assert words_columns() == ["text_digest", "text_digests"]
    assert resume_status?()
  end

  defp event!(type, contract) do
    Repo.query!(
      """
      INSERT INTO #{p()}_events (id, type, contract, contract_version, correlation_id, actor, occurred_at)
      VALUES (gen_random_uuid(), $1, $2, 'v', gen_random_uuid(), 'MigrationsTest', now())
      """,
      [type, contract]
    )
  end

  defp events do
    column("SELECT type || ' ' || contract FROM #{p()}_events WHERE actor = 'MigrationsTest'")
  end

  defp workers,
    do: column("SELECT worker FROM oban_jobs WHERE args = '{\"MigrationsTest\": true}'")

  # Issue #428: the library was `eh_os_contract`, and a database at V06 holds the name in
  # its storage, in the engine's own rows of the log and in Oban's jobs of its workers.
  test "V07 renames the storage and the engine's rows, and its down gives the old ones back" do
    on_exit(fn ->
      Repo.query!("DELETE FROM oban_jobs WHERE args = '{\"MigrationsTest\": true}'")
      Repo.query!("ALTER TABLE #{p()}_events DISABLE TRIGGER USER")
      Repo.query!("DELETE FROM #{p()}_events WHERE actor = 'MigrationsTest'")
      Repo.query!("ALTER TABLE #{p()}_events ENABLE TRIGGER USER")
    end)

    migrate(:down, to: @upgrade_to_v7)
    assert version() == "6"

    event!("eh_os_contract.subject_erased", "eh_os_contract")
    event!("eh_os_contract.timer_elapsed", "Clinic.Visits")
    # An application's own event, whose names merely contain the old one.
    event!("clinic.eh_os_contract.subject_erased", "Clinic.eh_os_contract")

    Repo.query!(
      "INSERT INTO oban_jobs (worker, args) SELECT w, '{\"MigrationsTest\": true}' FROM " <>
        "unnest(ARRAY['EhOsContract.TimerJob', 'EhOsContract.EffectJob', " <>
        "'Clinic.EhOsContract.TimerJob']) AS w"
    )

    migrate(:up, all: true)

    assert version() == "7"
    assert tables() == @tables
    assert functions() == @functions

    assert events() == [
             "clinic.eh_os_contract.subject_erased Clinic.eh_os_contract",
             "ehos_contract.subject_erased ehos_contract",
             "ehos_contract.timer_elapsed Clinic.Visits"
           ]

    assert workers() ==
             ["Clinic.EhOsContract.TimerJob", "EhosContract.EffectJob", "EhosContract.TimerJob"]

    # The log refuses a change again once V07 has made its own.
    assert_raise Postgrex.Error, ~r/ehos_contract_events is append-only: UPDATE is refused/, fn ->
      Repo.query!("UPDATE ehos_contract_events SET actor = actor")
    end

    # The trigger wakes the runners on the channel they listen on under the new name.
    assert one("SELECT prosrc FROM pg_proc WHERE proname = 'ehos_contract_events_notify'") =~
             ".oban_ehos_contract'"

    migrate(:down, to: @upgrade_to_v7)

    assert p() == "eh_os_contract"

    assert events() == [
             "clinic.eh_os_contract.subject_erased Clinic.eh_os_contract",
             "eh_os_contract.subject_erased eh_os_contract",
             "eh_os_contract.timer_elapsed Clinic.Visits"
           ]

    assert workers() ==
             ["Clinic.EhOsContract.TimerJob", "EhOsContract.EffectJob", "EhOsContract.TimerJob"]

    assert one("SELECT prosrc FROM pg_proc WHERE proname = 'eh_os_contract_events_notify'") =~
             ".oban_eh_os_contract'"
  end

  # A version no migration file in the test database has, so running it touches
  # nothing but this test's row in `schema_migrations`.
  @host_version 99_990_101_000_000

  test "a database recording a version this release does not know is refused, both ways" do
    Repo.query!("COMMENT ON TABLE #{p()}_events IS '8'")

    Repo.query!(
      "INSERT INTO schema_migrations (version, inserted_at) VALUES ($1, now())",
      [@host_version]
    )

    on_exit(fn ->
      Repo.query!("DELETE FROM schema_migrations WHERE version = $1", [@host_version])
      current = EhosContract.Migrations.current_version()
      Repo.query!("COMMENT ON TABLE #{p()}_events IS '#{current}'")
    end)

    refused = ~r/records version 8, and this release of ehos_contract knows versions up to/

    assert_raise ArgumentError, refused, fn ->
      Ecto.Migrator.down(Repo, @host_version, EhosContract.MigrationsTest.Host, log: false)
    end

    Repo.query!("DELETE FROM schema_migrations WHERE version = $1", [@host_version])

    assert_raise ArgumentError, refused, fn ->
      Ecto.Migrator.up(Repo, @host_version, EhosContract.MigrationsTest.Host, log: false)
    end

    # Nothing ran: the tables are there, and the database still says what it said.
    assert tables() == @tables
    assert version() == "8"
  end

  test "a database migrated before 0.3.0 is refused by its column, whatever it records" do
    Repo.query!("ALTER TABLE #{p()}_events ADD COLUMN instance_id text")
    on_exit(fn -> Repo.query!("ALTER TABLE #{p()}_events DROP COLUMN instance_id") end)

    assert_raise ArgumentError, ~r/records version 7, and it was migrated before 0\.3\.0/, fn ->
      Ecto.Migrator.up(Repo, @host_version, EhosContract.MigrationsTest.Host, log: false)
    end

    assert version() == "7"
  end

  test "a version this release does not have is refused as a target" do
    assert_raise ArgumentError, ~r/and 8 is not one of them/, fn ->
      EhosContract.Migrations.up(version: 8)
    end

    assert_raise ArgumentError, ~r/and 0 is not one of them/, fn ->
      EhosContract.Migrations.down(version: 0)
    end
  end

  test "the tables refuse what their checks refuse, whoever writes it" do
    assert_raise Postgrex.Error, ~r/ehos_contract_subscriptions_status/, fn ->
      Repo.query!(
        "INSERT INTO #{p()}_subscriptions (name, kind, mode, version, status) " <>
          "VALUES ('MigrationsTest', 'read_model', 'ordered', 'v', 'skipped')"
      )
    end

    assert_raise Postgrex.Error, ~r/ehos_contract_subscriptions_resume_status/, fn ->
      Repo.query!(
        "INSERT INTO #{p()}_subscriptions " <>
          "(name, kind, mode, version, status, resume_status) " <>
          "VALUES ('MigrationsTest', 'read_model', 'ordered', 'v', 'failing', 'failing')"
      )
    end

    assert_raise Postgrex.Error, ~r/ehos_contract_subject_keys_version/, fn ->
      Repo.query!(
        "INSERT INTO #{p()}_subject_keys " <>
          "(subject_type, subject_id, key_version, kek_id, wrapped_key) " <>
          "VALUES ('patient', 'patient-anna', 0, 'kek-1', '\\x00')"
      )
    end

    assert_raise Postgrex.Error, ~r/ehos_contract_commands_outcome/, fn ->
      Repo.query!(
        "INSERT INTO #{p()}_commands (id, contract, type, issued_by, correlation_id, outcome) " <>
          "VALUES ($1, 'C', 't', 'actor:a', $2, 'skipped')",
        [Ecto.UUID.bingenerate(), Ecto.UUID.bingenerate()]
      )
    end
  end
end
