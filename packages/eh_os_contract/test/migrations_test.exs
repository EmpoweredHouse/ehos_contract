defmodule EhOsContract.MigrationsTest do
  @moduledoc """
  v2 plan, E11c: **the engine's storage is one version, V01, in its final shape** —
  created from nothing, dropped to nothing, and created again.

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

  test "V01 is the only version, and it creates the whole store" do
    assert EhOsContract.Migrations.initial_version() == 1
    assert EhOsContract.Migrations.current_version() == 1
    assert version() == "1"
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

    assert version() == "1"
    assert tables() == @tables
    assert functions() == @functions
  end

  test "the tables refuse what their checks refuse, whoever writes it" do
    assert_raise Postgrex.Error, ~r/eh_os_contract_subscriptions_status/, fn ->
      Repo.query!(
        "INSERT INTO eh_os_contract_subscriptions (name, kind, mode, version, status) " <>
          "VALUES ('MigrationsTest', 'read_model', 'ordered', 'v', 'skipped')"
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
