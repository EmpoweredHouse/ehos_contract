defmodule EhOsContract.MigrationsTest do
  @moduledoc """
  v2 plan, E2: **V02 ↔ V03 both ways, on a log that already holds rows** — and each
  later version's tables, both ways.

  V03 changes the log in place, and the log is the one table whose rows cannot be
  recreated. So the migration is tested the way it will run at a consumer: rows
  written in V02's shape, the upgrade, the downgrade, and the upgrade again. It runs
  against `EhOsContract.CommitRepo`, because migrations commit and the sandbox would
  roll them back.
  """

  use ExUnit.Case, async: false

  alias EhOsContract.CommitRepo, as: Repo

  @v03 20_260_925_120_000
  @v04 20_260_926_120_000
  @v05 20_260_927_130_000

  setup do
    # Whatever happens in the test, the database is back at the newest version for
    # the tests that run after it.
    on_exit(fn -> migrate(:up, all: true) end)
    %{contract: "MigrationsTest-#{System.unique_integer([:positive])}"}
  end

  defp migrate(direction, opts), do: Repo.migrate(direction, opts)

  defp one(sql, params \\ []), do: Repo.query!(sql, params).rows |> List.first() |> List.first()

  # What `up all` reaches: the newest version, whichever that is by now.
  defp newest, do: Integer.to_string(EhOsContract.Migrations.current_version())

  defp version do
    one("SELECT obj_description('public.eh_os_contract_events'::regclass, 'pg_class')")
  end

  defp columns do
    Repo.query!(
      "SELECT column_name FROM information_schema.columns WHERE table_name = 'eh_os_contract_events'"
    ).rows
    |> List.flatten()
    |> MapSet.new()
  end

  defp primary_key do
    one("""
    SELECT string_agg(a.attname, ',')
    FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
    WHERE i.indrelid = 'eh_os_contract_events'::regclass AND i.indisprimary
    """)
  end

  defp triggers do
    Repo.query!(
      "SELECT tgname FROM pg_trigger WHERE tgrelid = 'eh_os_contract_events'::regclass AND NOT tgisinternal"
    ).rows
    |> List.flatten()
    |> Enum.sort()
  end

  # Three rows in V02's shape, inserted in an order that is not the order they
  # happened in, and one of them without an actor.
  defp insert_v02_rows(contract) do
    for {type, at, actor} <- [
          {"second", ~U[2026-07-02 09:00:00.000000Z], "someone"},
          {"first", ~U[2026-07-01 09:00:00.000000Z], nil},
          {"third", ~U[2026-07-03 09:00:00.000000Z], "someone"}
        ] do
      Repo.query!(
        """
        INSERT INTO eh_os_contract_events
          (id, type, contract, contract_version, correlation_id, payload, actor, occurred_at)
        VALUES ($1, $2, $3, 'v', $4, '{}', $5, $6)
        """,
        [Ecto.UUID.bingenerate(), type, contract, Ecto.UUID.bingenerate(), actor, at]
      )
    end
  end

  defp rows(contract) do
    Repo.query!(
      """
      SELECT type, position, actor, recorded_at = occurred_at
      FROM eh_os_contract_events WHERE contract = $1 ORDER BY position
      """,
      [contract]
    ).rows
  end

  test "V03 upgrades a V02 log in place, and its down gives V02 back", %{contract: contract} do
    migrate(:down, to: @v03)

    assert version() == "2"
    refute MapSet.member?(columns(), "position")
    assert primary_key() == "id"
    assert triggers() == []

    insert_v02_rows(contract)
    migrate(:up, all: true)

    assert version() == newest()
    assert primary_key() == "position"

    assert triggers() == [
             "eh_os_contract_events_append_lock",
             "eh_os_contract_events_append_only",
             "eh_os_contract_events_no_truncate"
           ]

    # Positions follow occurred_at, not insertion order. The missing actor became the
    # system actor, and recorded_at is occurred_at rather than the migration's clock.
    assert [
             ["first", p1, "system", true],
             ["second", p2, "someone", true],
             ["third", p3, "someone", true]
           ] = rows(contract)

    assert p1 < p2 and p2 < p3

    # The identity continues after the highest position, whatever else is in the log.
    highest = one("SELECT max(position) FROM eh_os_contract_events")

    next =
      one(
        """
        INSERT INTO eh_os_contract_events
          (id, type, contract, contract_version, correlation_id, actor, occurred_at)
        VALUES ($1, 'fourth', $2, 'v', $3, 'system', now()) RETURNING position
        """,
        [Ecto.UUID.bingenerate(), contract, Ecto.UUID.bingenerate()]
      )

    assert next == highest + 1

    migrate(:down, to: @v03)

    assert version() == "2"
    assert primary_key() == "id"
    assert triggers() == []

    for column <-
          ~w(position stream_id stream_version tags schema_version command_id metadata recorded_at) do
      refute MapSet.member?(columns(), column), "#{column} survived V03's down"
    end

    refute one("SELECT to_regclass('public.eh_os_contract_commands')::text")

    # Every row survives the round trip, and the actor it was given stays.
    assert Repo.query!(
             "SELECT type, actor FROM eh_os_contract_events WHERE contract = $1 ORDER BY occurred_at",
             [contract]
           ).rows == [
             ["first", "system"],
             ["second", "someone"],
             ["third", "someone"],
             ["fourth", "system"]
           ]

    migrate(:up, all: true)
    assert version() == newest()
    assert length(rows(contract)) == 4
  end

  defp table?(name), do: one("SELECT to_regclass($1)::text", ["public." <> name]) != nil

  test "V04 adds the tables of the consumers outside the dispatch transaction, and its down drops them" do
    tables =
      ~w(eh_os_contract_subscriptions eh_os_contract_process_managers eh_os_contract_event_runs)

    assert Enum.all?(tables, &table?/1)

    migrate(:down, to: @v04)
    assert version() == "3"
    refute Enum.any?(tables, &table?/1)

    migrate(:up, all: true)
    assert version() == newest()
    assert Enum.all?(tables, &table?/1)

    # A status outside the four is refused by the table, whoever writes it.
    assert_raise Postgrex.Error, ~r/eh_os_contract_subscriptions_status/, fn ->
      Repo.query!(
        "INSERT INTO eh_os_contract_subscriptions (name, kind, mode, version, status) " <>
          "VALUES ('MigrationsTest', 'read_model', 'ordered', 'v', 'skipped')"
      )
    end
  end

  test "V05 adds the tables of crypto-shredding, and its down drops them" do
    tables = ~w(eh_os_contract_subject_keys eh_os_contract_erasures)
    assert Enum.all?(tables, &table?/1)

    migrate(:down, to: @v05)
    assert version() == "4"
    refute Enum.any?(tables, &table?/1)

    migrate(:up, all: true)
    assert version() == newest()
    assert Enum.all?(tables, &table?/1)

    # A key version starts at 1, whoever writes it.
    assert_raise Postgrex.Error, ~r/eh_os_contract_subject_keys_version/, fn ->
      Repo.query!(
        "INSERT INTO eh_os_contract_subject_keys " <>
          "(subject_type, subject_id, key_version, kek_id, wrapped_key) " <>
          "VALUES ('patient', 'patient-anna', 0, 'kek-1', '\\x00')"
      )
    end
  end
end
