defmodule EhosContract.Auth.SchemaTest.Host do
  @moduledoc "A host's migration, as the moduledoc of `EhosContract.Auth.Migrations` tells one to write."

  use Ecto.Migration

  def up, do: EhosContract.Auth.Migrations.up()
  def down, do: EhosContract.Auth.Migrations.down()
end

defmodule EhosContract.Auth.SchemaTest.HostCreatingSchema do
  @moduledoc """
  A host's migration that creates its schema itself, queued before the package's: the
  first schema of the repo's `search_path`, which does not exist until it runs.
  """

  use Ecto.Migration

  def up do
    [[path]] = repo().query!("SHOW search_path").rows
    [schema | _] = String.split(path, ", ")
    execute "CREATE SCHEMA #{schema}"
    EhosContract.Auth.Migrations.up()
  end

  def down, do: EhosContract.Auth.Migrations.down()
end

defmodule EhosContract.Auth.SchemaTest do
  @moduledoc """
  Issue #51: **the package's tables in a schema other than `public`**, as EHOS gives
  an application one. The schema belongs to an owner role that
  runs the migrations and has no `CREATE` on `public`. The application runs as a
  second role with `SELECT`, `INSERT`, `UPDATE` and `DELETE` on the schema's tables
  and `USAGE` on its sequences, by default privileges, and nothing else. Both reach
  the schema only through the connection's `search_path`.

  `public` of this database already holds the package's tables at their current version, and
  that is what the defect hid behind: the version was read from `public` by name.

  Migrations commit, so the setup runs on a connection of its own as the database's
  superuser, outside the sandbox. Roles belong to the whole cluster, so each test's
  are named at random and dropped with its schema.
  """

  use EhosContract.Auth.KeyCase, async: false

  alias EhosContract.{Actor, Auth, Authorizer}
  alias EhosContract.Auth.{Keys, SchemaRepo, TestRepo}
  alias EhosContract.Auth.SchemaTest.{Host, HostCreatingSchema}

  @tables [
    "ehos_contract_auth_decisions",
    "ehos_contract_auth_keys",
    "ehos_contract_auth_session_credentials",
    "ehos_contract_auth_sessions",
    "schema_migrations"
  ]

  setup do
    schema =
      "ehos_contract_auth_schema_" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)

    owner = schema <> "_owner"
    app = schema <> "_app"
    password = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

    # Before anything is created, so a failure halfway leaves nothing behind.
    on_exit(fn -> drop!(schema, [owner, app]) end)

    admin!([
      "CREATE ROLE #{owner} LOGIN PASSWORD '#{password}'",
      "CREATE ROLE #{app} LOGIN PASSWORD '#{password}'"
    ])

    # What EHOS's operator and its grants Job do.
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
             {"SELECT has_schema_privilege($1, 'public', 'CREATE'), " <>
                "has_database_privilege($1, current_database(), 'CREATE'), " <>
                "has_schema_privilege($2, $3, 'CREATE')", [owner, app, schema]}
           ]) == [[false, false, false]]

    %{schema: schema, owner: owner, app: app, password: password}
  end

  # Each call on a connection of its own, which a test's end does not take down; the
  # rows of the last statement. A statement is SQL, or SQL with its parameters.
  defp admin!(statements) do
    config = Keyword.take(TestRepo.config(), [:hostname, :port, :username, :password, :database])
    {:ok, conn} = Postgrex.start_link(config)

    try do
      statements
      |> Enum.map(fn
        {sql, params} -> Postgrex.query!(conn, sql, params)
        sql -> Postgrex.query!(conn, sql, [])
      end)
      |> List.last()
      |> Map.fetch!(:rows)
    after
      GenServer.stop(conn)
    end
  end

  defp drop!(schema, roles) do
    admin!([
      {"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename = ANY($1)", [roles]},
      "DROP SCHEMA IF EXISTS #{schema} CASCADE"
    ])

    for role <- roles, admin!([{"SELECT 1 FROM pg_roles WHERE rolname = $1", [role]}]) != [] do
      # Revokes the grants and default privileges, which the drop would otherwise
      # refuse over.
      admin!(["DROP OWNED BY #{role}", "DROP ROLE #{role}"])
    end
  end

  defp connect(%{password: password}, role, path) do
    config =
      Keyword.take(TestRepo.config(), [:hostname, :port, :database]) ++
        [username: role, password: password, pool_size: 2, parameters: [search_path: path]]

    start_supervised!({SchemaRepo, config}, id: role)
  end

  defp migrate(direction),
    do: Ecto.Migrator.run(SchemaRepo, [{1, Host}], direction, all: true, log: false)

  defp tables(schema) do
    admin!([
      {"SELECT table_name FROM information_schema.tables WHERE table_schema = $1 ORDER BY 1",
       [schema]}
    ])
    |> List.flatten()
  end

  defp version(schema) do
    [[version]] =
      admin!([
        {"SELECT obj_description(to_regclass($1), 'pg_class')",
         [schema <> ".ehos_contract_auth_keys"]}
      ])

    version
  end

  defp owned(role),
    do: admin!([{"SELECT count(*) FROM pg_class WHERE relowner = $1::text::regrole", [role]}])

  test "an owner that cannot create in public migrates the schema up, down and up again",
       %{schema: schema, owner: owner} = context do
    public = tables("public")
    connect(context, owner, schema)

    migrate(:up)
    assert tables(schema) == @tables
    assert version(schema) == "3"

    # A host's second call reads the schema's "3", and creates nothing twice.
    assert Ecto.Migrator.up(SchemaRepo, 2, Host, log: false) == :ok
    admin!(["DELETE FROM #{schema}.schema_migrations WHERE version = 2"])

    migrate(:down)
    assert tables(schema) == ["schema_migrations"]

    migrate(:up)
    assert tables(schema) == @tables
    assert version(schema) == "3"
    assert tables("public") == public
  end

  # `public` holds the package's tables at "3" here, and the owner may read them.
  test "with public on the path too, the version is the schema's, and public is left alone",
       %{schema: schema, owner: owner} = context do
    public = tables("public")
    connect(context, owner, schema <> ", public")

    migrate(:up)
    assert tables(schema) == @tables
    assert version(schema) == "3"

    migrate(:down)
    assert tables(schema) == ["schema_migrations"]
    assert tables("public") == public
    assert version("public") == "3"
  end

  # As the database's superuser, since the owner may not create a schema. `public` is
  # on the path and holds the tables at "3". Ecto records the migration in
  # `public.schema_migrations`, since it reads its table before the schema exists, so
  # the version is one of the test's own and its row goes after it.
  test "a schema the host's own migration creates gets the tables" do
    new =
      "ehos_contract_auth_created_" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)

    version = 900_000_000 + :rand.uniform(99_999_999)

    on_exit(fn ->
      admin!([
        "DROP SCHEMA IF EXISTS #{new} CASCADE",
        {"DELETE FROM public.schema_migrations WHERE version = $1", [version]}
      ])
    end)

    superuser = %{password: TestRepo.config()[:password]}
    connect(superuser, TestRepo.config()[:username], new <> ", public")
    Ecto.Migrator.run(SchemaRepo, [{version, HostCreatingSchema}], :up, all: true, log: false)

    assert tables(new) == @tables -- ["schema_migrations"]
    assert version(new) == "3"
  end

  test "the role the application runs as keeps the keys and records the decisions",
       %{schema: schema, owner: owner, app: app} = context do
    connect(context, owner, schema)
    migrate(:up)
    stop_supervised!(owner)
    connect(context, app, schema)
    assert owned(app) == [[0]]

    # Loaded from the table, fetched, stored; refreshed, stored again.
    first = key_pair()
    second = key_pair()
    ehos = ehos({:keys, [first]})
    keys = start_keys(ehos, repo: SchemaRepo)
    assert {:ok, _} = Auth.verify(credential(first), keys: keys)

    answer(ehos, {:keys, [second]})
    :ok = Keys.refresh(keys)
    assert SchemaRepo.query!("SELECT kid FROM ehos_contract_auth_keys").rows == [[second.kid]]

    # A failed write is only logged, so this is what shows the table was written:
    # a restart without EHOS verifies with what it holds.
    stop_supervised!(keys)
    answer(ehos, :down)
    keys = start_keys(ehos, repo: SchemaRepo, name: keys)
    assert {:ok, _} = Auth.verify(credential(second), keys: keys)

    previous = Application.fetch_env!(:ehos_contract, :repo)
    Application.put_env(:ehos_contract, :repo, SchemaRepo)
    on_exit(fn -> Application.put_env(:ehos_contract, :repo, previous) end)

    request = %Authorizer.Request{
      kind: :command,
      capability: "clinic.record_payment",
      contract: Clinic.Contracts.VisitSettlement,
      contract_id: "clinic.visit_settlement",
      version: "3f2a",
      scope: nil
    }

    assert Auth.authorize(Actor.credential("u-anna", ["clinic.record_payment"]), request) == :ok

    assert Auth.authorize(Actor.credential("u-bartek", []), request) ==
             {:error, :missing_capability}

    assert SchemaRepo.query!(
             "SELECT subject, outcome FROM ehos_contract_auth_decisions ORDER BY id"
           ).rows == [["u-anna", "allowed"], ["u-bartek", "refused"]]

    # Nothing ran as this role created anything, not even a temporary table.
    assert owned(app) == [[0]]
  end
end
