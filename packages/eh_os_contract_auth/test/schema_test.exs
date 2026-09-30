defmodule EhOsContract.Auth.SchemaTest.Host do
  @moduledoc "A host's migration, as the moduledoc of `EhOsContract.Auth.Migrations` tells one to write."

  use Ecto.Migration

  def up, do: EhOsContract.Auth.Migrations.up()
  def down, do: EhOsContract.Auth.Migrations.down()
end

defmodule EhOsContract.Auth.SchemaTest do
  @moduledoc """
  Issue #51: **the package's tables in a schema other than `public`**, as EHOS gives
  an application one (`eh-os` D-54, D-56). The schema belongs to an owner role that
  runs the migrations and has no `CREATE` on `public`. The application runs as a
  second role with `SELECT`, `INSERT`, `UPDATE` and `DELETE` on the schema's tables
  and `USAGE` on its sequences, by default privileges, and nothing else. Both reach
  the schema only through the connection's `search_path`.

  `public` of this database already holds the package's tables at version 2, and
  that is what the defect hid behind: the version was read from `public` by name.

  Migrations commit, so the setup runs on a connection of its own as the database's
  superuser, outside the sandbox. Roles belong to the whole cluster, so each test's
  are named at random and dropped with its schema.
  """

  use EhOsContract.Auth.KeyCase, async: false

  alias EhOsContract.{Actor, Auth, Authorizer}
  alias EhOsContract.Auth.{Keys, SchemaRepo, SchemaTest.Host, TestRepo}

  @password "eh_os_contract_auth_schema"
  @tables ["eh_os_contract_auth_decisions", "eh_os_contract_auth_keys", "schema_migrations"]

  setup do
    schema =
      "eh_os_contract_auth_schema_" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)

    owner = schema <> "_owner"
    app = schema <> "_app"

    admin!([
      "CREATE ROLE #{owner} LOGIN PASSWORD '#{@password}'",
      "CREATE ROLE #{app} LOGIN PASSWORD '#{@password}'"
    ])

    on_exit(fn ->
      admin!([
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity " <>
          "WHERE usename IN ('#{owner}', '#{app}')",
        "DROP SCHEMA IF EXISTS #{schema} CASCADE",
        # Revokes the grants and default privileges, which the roles' drop would
        # otherwise refuse over.
        "DROP OWNED BY #{owner}, #{app}",
        "DROP ROLE #{app}",
        "DROP ROLE #{owner}"
      ])
    end)

    # What EHOS's operator and its grants Job do (D-54).
    admin!([
      "CREATE SCHEMA #{schema} AUTHORIZATION #{owner}",
      "GRANT USAGE ON SCHEMA #{schema} TO #{app}",
      "ALTER DEFAULT PRIVILEGES FOR ROLE #{owner} IN SCHEMA #{schema} " <>
        "GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO #{app}",
      "ALTER DEFAULT PRIVILEGES FOR ROLE #{owner} IN SCHEMA #{schema} " <>
        "GRANT USAGE, SELECT ON SEQUENCES TO #{app}"
    ])

    # Not assumed: a database that let either create elsewhere would prove nothing.
    assert admin!([
             "SELECT has_schema_privilege('#{owner}', 'public', 'CREATE'), " <>
               "has_database_privilege('#{owner}', current_database(), 'CREATE'), " <>
               "has_schema_privilege('#{app}', '#{schema}', 'CREATE')"
           ]) == [[false, false, false]]

    %{schema: schema, owner: owner, app: app}
  end

  # Each statement on a connection of its own, which a test's end does not take down;
  # the rows of the last.
  defp admin!(statements) do
    config = Keyword.take(TestRepo.config(), [:hostname, :port, :username, :password, :database])
    {:ok, conn} = Postgrex.start_link(config)

    try do
      statements |> Enum.map(&Postgrex.query!(conn, &1, [])) |> List.last() |> Map.fetch!(:rows)
    after
      GenServer.stop(conn)
    end
  end

  defp connect(role, schema) do
    config =
      Keyword.take(TestRepo.config(), [:hostname, :port, :database]) ++
        [username: role, password: @password, pool_size: 2, parameters: [search_path: schema]]

    start_supervised!({SchemaRepo, config}, id: role)
  end

  defp migrate(direction),
    do: Ecto.Migrator.run(SchemaRepo, [{1, Host}], direction, all: true, log: false)

  defp tables(schema) do
    admin!([
      "SELECT table_name FROM information_schema.tables " <>
        "WHERE table_schema = '#{schema}' ORDER BY 1"
    ])
    |> List.flatten()
  end

  defp version(schema) do
    [[version]] =
      admin!([
        "SELECT obj_description('#{schema}.eh_os_contract_auth_keys'::regclass, 'pg_class')"
      ])

    version
  end

  defp owned(role),
    do: admin!(["SELECT count(*) FROM pg_class WHERE relowner = '#{role}'::regrole"])

  test "an owner that cannot create in public migrates the schema up, down and up again",
       %{schema: schema, owner: owner} do
    public = tables("public")
    connect(owner, schema)

    migrate(:up)
    assert tables(schema) == @tables
    assert version(schema) == "2"

    # A host's second call reads the schema's "2", and creates nothing twice.
    assert Ecto.Migrator.up(SchemaRepo, 2, Host, log: false) == :ok
    admin!(["DELETE FROM #{schema}.schema_migrations WHERE version = 2"])

    migrate(:down)
    assert tables(schema) == ["schema_migrations"]

    migrate(:up)
    assert tables(schema) == @tables
    assert version(schema) == "2"
    assert tables("public") == public
  end

  test "the role the application runs as keeps the keys and records the decisions",
       %{schema: schema, owner: owner, app: app} do
    connect(owner, schema)
    migrate(:up)
    stop_supervised!(owner)
    connect(app, schema)
    assert owned(app) == [[0]]

    # Loaded from the table, fetched, stored; refreshed, stored again.
    first = key_pair()
    second = key_pair()
    ehos = ehos({:keys, [first]})
    keys = start_keys(ehos, repo: SchemaRepo)
    assert {:ok, _} = Auth.verify(credential(first), keys: keys)

    answer(ehos, {:keys, [second]})
    :ok = Keys.refresh(keys)
    assert SchemaRepo.query!("SELECT kid FROM eh_os_contract_auth_keys").rows == [[second.kid]]

    # A failed write is only logged, so this is what shows the table was written:
    # a restart without EHOS verifies with what it holds.
    stop_supervised!(keys)
    answer(ehos, :down)
    keys = start_keys(ehos, repo: SchemaRepo, name: keys)
    assert {:ok, _} = Auth.verify(credential(second), keys: keys)

    previous = Application.fetch_env!(:eh_os_contract, :repo)
    Application.put_env(:eh_os_contract, :repo, SchemaRepo)
    on_exit(fn -> Application.put_env(:eh_os_contract, :repo, previous) end)

    request = %Authorizer.Request{
      kind: :command,
      capability: "rehmed.record_payment",
      contract: Rehmed.Contracts.VisitSettlement,
      version: "3f2a",
      scope: nil
    }

    assert Auth.authorize(Actor.credential("u-anna", ["rehmed.record_payment"]), request) == :ok

    assert Auth.authorize(Actor.credential("u-bartek", []), request) ==
             {:error, :missing_capability}

    assert SchemaRepo.query!(
             "SELECT subject, outcome FROM eh_os_contract_auth_decisions ORDER BY id"
           ).rows == [["u-anna", "allowed"], ["u-bartek", "refused"]]

    # Nothing ran as this role created anything, not even a temporary table.
    assert owned(app) == [[0]]
  end
end
