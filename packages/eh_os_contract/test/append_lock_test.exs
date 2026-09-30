defmodule EhOsContract.AppendLockTest.Host do
  @moduledoc "A host's migration, as the moduledoc of `EhOsContract.Migrations` tells one to write."

  use Ecto.Migration

  def up, do: EhOsContract.Migrations.up()
  def down, do: EhOsContract.Migrations.down()
end

defmodule EhOsContract.AppendLockTest.HostCreatingSchema do
  @moduledoc """
  A host's migration that creates its schema itself, queued before the engine's: the
  first schema of the repo's `search_path`, which does not exist until it runs.
  """

  use Ecto.Migration

  def up do
    [[path]] = repo().query!("SHOW search_path").rows
    [schema | _] = String.split(path, ", ")
    execute "CREATE SCHEMA #{schema}"
    EhOsContract.Migrations.up()
  end

  def down, do: EhOsContract.Migrations.down()
end

defmodule EhOsContract.AppendLockTest do
  @moduledoc """
  **One append lock per log, not per database** (v2 §10.2, its note of 30 September
  2026). EHOS keeps every application of an instance in one database, each in a
  schema of its own (`eh-os` D-54), and an advisory lock belongs to the whole
  database: with one fixed key, every application there appended one after another.

  Two schemas in `EhOsContract.CommitRepo`'s database, each migrated as a host does.
  While a transaction in the first holds the lock, an append to the second goes
  through, and one to the first waits — through the store's function and through the
  trigger alike. Waiting is observed with `lock_timeout`, which a waiting advisory
  lock obeys.
  """

  use ExUnit.Case, async: false

  alias EhOsContract.{CommitRepo, SchemaRepo}
  alias EhOsContract.AppendLockTest.{Host, HostCreatingSchema}
  alias EhOsContract.Migrations.V01

  setup do
    suffix = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    first = "eh_os_contract_lock_a_" <> suffix
    second = "eh_os_contract_lock_b_" <> suffix
    third = "eh_os_contract_lock_c_" <> suffix

    on_exit(fn ->
      for schema <- [first, second, third],
          do: CommitRepo.query!("DROP SCHEMA IF EXISTS #{schema} CASCADE", [], log: false)
    end)

    for schema <- [first, second] do
      CommitRepo.query!("CREATE SCHEMA #{schema}", [], log: false)
      migrate!(schema)
    end

    %{first: first, second: second, third: third}
  end

  defp config(schema) do
    Keyword.take(CommitRepo.config(), [:hostname, :port, :database, :username, :password]) ++
      [parameters: [search_path: schema]]
  end

  defp migrate!(path, host \\ Host, version \\ 1) do
    Application.put_env(:eh_os_contract, SchemaRepo, config(path) ++ [pool_size: 2])
    on_exit(fn -> Application.delete_env(:eh_os_contract, SchemaRepo) end)
    start_supervised!(SchemaRepo, id: path)
    Ecto.Migrator.run(SchemaRepo, [{version, host}], :up, all: true, log: false)
    stop_supervised!(path)
  end

  defp lock_sql(schema, function) do
    [[definition]] =
      CommitRepo.query!("SELECT pg_get_functiondef(to_regproc($1))", ["#{schema}.#{function}"]).rows

    [call] = Regex.run(~r/pg_catalog\.pg_advisory_xact_lock\([^)]*\)/, definition)
    call
  end

  defp locks(schema) do
    for function <- ["eh_os_contract_append_lock", "eh_os_contract_events_take_append_lock"],
        do: lock_sql(schema, function)
  end

  defp lock_call(schema) do
    {class, log} = V01.lock_key(schema)
    "pg_catalog.pg_advisory_xact_lock(#{class}, #{log})"
  end

  defp connect(schema), do: start_supervised!({Postgrex, config(schema)}, id: make_ref())

  # Holds the lock of `schema`'s log in an open transaction until told to let go.
  defp hold(schema) do
    conn = connect(schema)
    test = self()

    holder =
      spawn_link(fn ->
        Postgrex.transaction(conn, fn conn ->
          Postgrex.query!(conn, "SELECT eh_os_contract_append_lock()", [])
          send(test, :held)

          receive do
            :release -> :ok
          end
        end)

        send(test, :released)
      end)

    assert_receive :held
    holder
  end

  defp release(holder) do
    send(holder, :release)
    assert_receive :released, 1_000
  end

  # The statement, in a transaction of its own, given 200 ms to get its lock.
  defp within_timeout(schema, sql) do
    conn = connect(schema)

    result =
      Postgrex.transaction(conn, fn conn ->
        Postgrex.query!(conn, "SET LOCAL lock_timeout = '200ms'", [])

        case Postgrex.query(conn, sql, []) do
          {:ok, _} ->
            :went_through

          # The failed statement aborts the transaction, which cannot commit after it.
          {:error, %Postgrex.Error{postgres: %{code: :lock_not_available}}} ->
            Postgrex.rollback(conn, :waited)
        end
      end)

    case result do
      {:ok, :went_through} -> :went_through
      {:error, :waited} -> :waited
    end
  end

  @insert """
  INSERT INTO eh_os_contract_events
    (id, type, contract, contract_version, correlation_id, actor, occurred_at)
  VALUES (gen_random_uuid(), 'lock.tested', 'AppendLockTest', 'v', gen_random_uuid(), 'system:test', now())
  """

  test "each log has a key of its own, and both of its functions take it",
       %{first: first, second: second} do
    assert V01.lock_key(first) != V01.lock_key(second)
    assert locks(first) == [lock_call(first), lock_call(first)]
    assert locks(second) == [lock_call(second), lock_call(second)]
  end

  test "an append to another schema's log does not wait for this one's",
       %{first: first, second: second} do
    holder = hold(first)

    assert within_timeout(second, "SELECT eh_os_contract_append_lock()") == :went_through
    assert within_timeout(second, @insert) == :went_through

    release(holder)
  end

  test "an append to the same log still waits, through the store and through the trigger",
       %{first: first} do
    holder = hold(first)

    assert within_timeout(first, "SELECT eh_os_contract_append_lock()") == :waited
    assert within_timeout(first, @insert) == :waited

    release(holder)
    assert within_timeout(first, @insert) == :went_through
  end

  test "the trigger takes its own log's lock, whatever the inserting session's path",
       %{first: first, second: second} do
    holder = hold(first)

    qualified =
      String.replace(@insert, "INTO eh_os_contract_events", "INTO #{first}.eh_os_contract_events")

    assert within_timeout(second, qualified) == :waited

    release(holder)
  end

  # `public` is on the path, and holds the engine's log at "1". Ecto records the
  # migration in `public.schema_migrations`, since it reads its table before the
  # schema exists, so the version is one of the test's own and its row goes after it.
  test "a schema the host's own migration creates gets the log and its key", %{third: third} do
    version = 900_000_000 + :rand.uniform(99_999_999)

    on_exit(fn ->
      CommitRepo.query!("DELETE FROM public.schema_migrations WHERE version = $1", [version])
    end)

    migrate!(third <> ", public", HostCreatingSchema, version)

    assert locks(third) == [lock_call(third), lock_call(third)]
  end
end
