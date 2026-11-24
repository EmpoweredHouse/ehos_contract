defmodule EhosContract.SchemaTest.Host do
  @moduledoc """
  A host's migration in a schema of its own, as EHOS's application template writes it:
  Oban's tables there by its `prefix:`, without creating the schema it is given, and
  the engine's through the search path, with nothing to say.
  """

  use Ecto.Migration

  def up do
    Oban.Migration.up(prefix: oban_prefix(), create_schema: false)
    EhosContract.Migrations.up()
  end

  def down do
    EhosContract.Migrations.down()
    Oban.Migration.down(prefix: oban_prefix(), version: 1)
  end

  def oban_prefix, do: current_schema()

  def current_schema, do: repo().query!("SELECT current_schema()").rows |> hd() |> hd()
end

defmodule EhosContract.SchemaTest.HostWithObanApart do
  @moduledoc """
  The same, with Oban's tables in a schema of their own, `<schema>_jobs`, which is
  not on the connection's `search_path`: the engine has to read them where Oban's
  `prefix:` says.
  """

  use Ecto.Migration

  alias EhosContract.SchemaTest.Host

  def up do
    Oban.Migration.up(prefix: oban_prefix(), create_schema: false)
    EhosContract.Migrations.up()
  end

  def down do
    EhosContract.Migrations.down()
    Oban.Migration.down(prefix: oban_prefix(), version: 1)
  end

  def oban_prefix, do: Host.current_schema() <> "_jobs"
end

defmodule EhosContract.SchemaTest do
  @moduledoc """
  Issue #51: **the engine's storage in a schema other than `public`**, as EHOS gives
  an application one. The schema belongs to an owner role that
  runs the migrations and has no `CREATE` on `public`. The application runs as a
  second role with `SELECT`, `INSERT`, `UPDATE` and `DELETE` on the schema's tables
  and `USAGE` on its sequences, by default privileges, and nothing else. Both reach
  the schema only through the connection's `search_path`.

  `public` of this database already holds the engine's tables at the current version, and that
  is what the defect hid behind: the version was read from `public` by name, so a
  migration in the schema read "1" and created nothing.

  Runs in `EhosContract.CommitRepo`'s database, because migrations and dispatch here
  commit, and as its superuser for what EHOS's operator does. Roles belong to the
  whole cluster, so each test's are named at random and dropped with its schema.
  """

  use ExUnit.Case, async: false

  alias EhosContract.{Actor, CommitRepo, Conformance, Paths, SchemaRepo, Subscription, Testing}
  alias DispatchRig.Ledger
  alias DispatchRig.Ledger.Commands.{Deposit, OpenAccount}
  alias DispatchRig.Ledger.Queries.BalanceOf
  alias ShreddingRig.Members
  alias ShreddingRig.Members.Commands.Join

  alias EhosContract.SchemaTest.{Host, HostWithObanApart}

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

  setup do
    schema = "ehos_contract_schema_" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    owner = schema <> "_owner"
    app = schema <> "_app"
    password = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

    # Before anything is created, so a failure halfway leaves nothing behind.
    on_exit(fn -> drop!([schema, schema <> "_jobs"], [owner, app]) end)
    admin!("CREATE ROLE #{owner} LOGIN PASSWORD '#{password}'")
    admin!("CREATE ROLE #{app} LOGIN PASSWORD '#{password}'")

    # What EHOS's operator and its grants Job do, and the same for the schema
    # `HostWithObanApart` puts Oban in, which EHOS does not give.
    for granted <- [schema, schema <> "_jobs"] do
      admin!("CREATE SCHEMA #{granted} AUTHORIZATION #{owner}")
      admin!("GRANT USAGE ON SCHEMA #{granted} TO #{app}")

      admin!(
        "ALTER DEFAULT PRIVILEGES FOR ROLE #{owner} IN SCHEMA #{granted} " <>
          "GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO #{app}"
      )

      admin!(
        "ALTER DEFAULT PRIVILEGES FOR ROLE #{owner} IN SCHEMA #{granted} " <>
          "GRANT USAGE, SELECT ON SEQUENCES TO #{app}"
      )
    end

    # Not assumed: a database that let either create elsewhere would prove nothing.
    refute privilege?("has_schema_privilege($1, 'public', 'CREATE')", [owner])
    refute privilege?("has_schema_privilege($1, 'public', 'CREATE')", [app])
    refute privilege?("has_database_privilege($1, current_database(), 'CREATE')", [owner])
    refute privilege?("has_schema_privilege($1, $2, 'CREATE')", [app, schema])

    %{schema: schema, owner: owner, app: app, password: password}
  end

  defp admin!(sql, params \\ []), do: CommitRepo.query!(sql, params, log: false)

  defp privilege?(sql, params), do: admin!("SELECT " <> sql, params).rows == [[true]]

  defp drop!(schemas, roles) do
    admin!("SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename = ANY($1)", [
      roles
    ])

    for schema <- schemas, do: admin!("DROP SCHEMA IF EXISTS #{schema} CASCADE")

    for role <- roles, admin!("SELECT 1 FROM pg_roles WHERE rolname = $1", [role]).rows != [] do
      # Revokes the grants and default privileges in this database, which the drop
      # would otherwise refuse over.
      admin!("DROP OWNED BY #{role}")
      admin!("DROP ROLE #{role}")
    end
  end

  # In the application's environment, as a host configures its repo: Oban's
  # notifier opens a connection of its own from it.
  defp connect(%{password: password}, role, path) do
    config =
      Keyword.take(CommitRepo.config(), [:hostname, :port, :database]) ++
        [username: role, password: password, pool_size: 2, parameters: [search_path: path]]

    Application.put_env(:ehos_contract, SchemaRepo, config)
    on_exit(fn -> Application.delete_env(:ehos_contract, SchemaRepo) end)
    start_supervised!(SchemaRepo, id: role)
  end

  # The rigs' migrations are loaded by `CommitRepo.reset!/0` in `test_helper.exs`.
  defp migrate(direction, host \\ Host) do
    migrations = [
      {1, host},
      {2, EhosContract.TestRepo.Migrations.CreateDispatchRig},
      {3, EhosContract.TestRepo.Migrations.CreateShreddingRig}
    ]

    Ecto.Migrator.run(SchemaRepo, migrations, direction, all: true, log: false)
  end

  defp owned(role),
    do: admin!("SELECT count(*) FROM pg_class WHERE relowner = $1::text::regrole", [role]).rows

  defp tables(schema) do
    admin!(
      "SELECT table_name FROM information_schema.tables WHERE table_schema = $1 ORDER BY 1",
      [schema]
    ).rows
    |> List.flatten()
  end

  defp engine_tables(schema) do
    for table <- tables(schema),
        String.starts_with?(table, "ehos_contract_"),
        not String.starts_with?(table, "ehos_contract_auth_"),
        do: table
  end

  defp functions(schema) do
    admin!(
      """
      SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = $1 ORDER BY 1
      """,
      [schema]
    ).rows
    |> List.flatten()
  end

  defp version(schema) do
    admin!("SELECT obj_description(to_regclass($1), 'pg_class')", [
      schema <> ".ehos_contract_events"
    ]).rows
    |> hd()
    |> hd()
  end

  test "an owner that cannot create in public migrates the schema up, down and up again",
       %{schema: schema, owner: owner} = context do
    public = tables("public")
    connect(context, owner, schema)

    migrate(:up)

    assert engine_tables(schema) == @tables
    assert "oban_jobs" in tables(schema)
    assert version(schema) == "6"

    assert functions(schema) -- ["oban_jobs_notify"] == [
             "ehos_contract_append_lock",
             "ehos_contract_events_notify",
             "ehos_contract_events_refuse_change",
             "ehos_contract_events_take_append_lock"
           ]

    assert tables("public") == public

    # A host's second call reads the schema's "6", and creates nothing twice.
    assert Ecto.Migrator.up(SchemaRepo, 4, Host, log: false) == :ok
    admin!("DELETE FROM #{schema}.schema_migrations WHERE version = 4")
    assert engine_tables(schema) == @tables

    migrate(:down)

    assert tables(schema) == ["schema_migrations"]
    assert functions(schema) == []

    migrate(:up)

    assert engine_tables(schema) == @tables
    assert version(schema) == "6"
    assert tables("public") == public
  end

  # `public` holds the engine's tables at "6" here, and the owner may read them.
  test "with public on the path too, the version is the schema's, and public is left alone",
       %{schema: schema, owner: owner} = context do
    public = tables("public")
    connect(context, owner, schema <> ", public")

    migrate(:up)
    assert engine_tables(schema) == @tables
    assert version(schema) == "6"

    migrate(:down)
    assert tables(schema) == ["schema_migrations"]

    # A rollback of a schema that records nothing, which the unqualified drops would
    # have taken to `public`'s tables.
    admin!("INSERT INTO #{schema}.schema_migrations (version, inserted_at) VALUES (1, now())")
    migrate(:down)

    assert tables("public") == public
    assert version("public") == "6"
  end

  # Migrated by the owner, run by the role the application runs as, with Oban where
  # `host` puts it.
  defp boot_as_app!(%{schema: schema, owner: owner, app: app} = context, host) do
    connect(context, owner, schema)
    migrate(:up, host)
    oban_prefix = if host == Host, do: schema, else: schema <> "_jobs"
    stop_supervised!(owner)
    connect(context, app, schema)

    previous = Application.fetch_env!(:ehos_contract, :repo)
    Application.put_env(:ehos_contract, :repo, SchemaRepo)
    on_exit(fn -> Application.put_env(:ehos_contract, :repo, previous) end)

    # The engine's Oban is the one named `Oban`. The suite's runs on `TestRepo` in
    # `public`, so for the test it is replaced by one on this repo, and started again
    # afterwards outside any test's process, which would take it down on exit.
    :ok = Supervisor.stop(Oban.whereis(Oban))

    on_exit(fn ->
      {:ok, pid} = Oban.start_link(Application.fetch_env!(:ehos_contract, Oban))
      Process.unlink(pid)
    end)

    # A node that runs no Oban still reports, looking for its jobs on the path.
    if host == Host, do: assert(is_list(Paths.observe(Ledger)))

    start_supervised!(
      {Oban, repo: SchemaRepo, prefix: oban_prefix, queues: [events: 10], testing: :manual}
    )

    assert owned(app) == [[0]]
    oban_prefix
  end

  @clerk Actor.credential("u-1", ["dispatch_rig.open_account", "dispatch_rig.deposit"])
  @member_clerk Actor.credential("u-2", ["shredding_rig.join"])

  defp in_flight(what),
    do: Paths.observe(Ledger) |> Enum.map(& &1.in_flight[what]) |> Enum.sum()

  for {place, host} <- [
        {"in the schema, as the template puts it", Host},
        {"off the search path", HostWithObanApart}
      ] do
    @tag :capture_log
    test "the role the application runs as boots, dispatches, reacts, reads, erases and " <>
           "reports, with Oban #{place}",
         %{schema: schema, app: app} = context do
      oban_prefix = boot_as_app!(context, unquote(host))

      # What a host does at boot.
      :ok = EhosContract.Deployment.record!()
      assert %{applied: 0} = Testing.drain()

      {:ok, _} =
        EhosContract.dispatch(Ledger, %OpenAccount{account_id: "a-1", branch_id: "b-7"},
          actor: @clerk
        )

      # 1000 sets off the policy that flags the account in the transaction, and the
      # flag an effect, whose job is inserted in the same transaction.
      {:ok, _} =
        EhosContract.dispatch(Ledger, %Deposit{account_id: "a-1", amount: 1000}, actor: @clerk)

      {:ok, _} =
        EhosContract.dispatch(
          Members,
          %Join{
            membership_id: "membership-anna",
            member_id: "member-anna",
            name: "Anna Nowak",
            contacts: [
              %ShreddingRig.Domain.Values.Contact{
                member_id: "member-anna",
                phone: "+48 600 100 200"
              }
            ],
            plan: :basic
          },
          actor: @member_clerk
        )

      # The report counts the effect's job, read where Oban's prefix puts it.
      assert in_flight(:effects) == 1

      # The ordered read models, the process manager and its timers, and the effects.
      drained = Testing.drain()
      assert drained.failing == []
      assert drained.applied > 0
      assert drained.effects > 0

      assert SchemaRepo.query!("SELECT account_id FROM dispatch_rig_notices").rows == [["a-1"]]
      assert in_flight(:effects) == 0
      assert in_flight(:timers) > 0

      assert admin!("SELECT count(*) FROM #{oban_prefix}.oban_jobs WHERE worker = $1", [
               "EhosContract.TimerJob"
             ]).rows == [[2]]

      assert {:ok, %{account_id: "a-1", balance: 1000}} =
               EhosContract.query(Ledger, %BalanceOf{account_id: "a-1"},
                 actor: Actor.credential("u-3", ["dispatch_rig.balance_of"])
               )

      assert EhosContract.erase(:member, "member-anna", actor: @member_clerk) == {:ok, :erased}
      assert Testing.drain().failing == []
      assert %{} = Conformance.report(Ledger)

      assert admin!("SELECT count(*) FROM #{schema}.ehos_contract_events").rows == [[5]]

      # A second account, never deposited to: its run waits on its first deposit's
      # timer, a day away.
      {:ok, _} =
        EhosContract.dispatch(Ledger, %OpenAccount{account_id: "a-2", branch_id: "b-7"},
          actor: @clerk
        )

      assert Testing.drain().failing == []

      # What `mix ehos_contract.subscriptions --rebuild` does, two days on: the read
      # models are emptied and replayed, and the process manager keeps its overdue
      # timer only because it finds the timer's job queued, where Oban's prefix says.
      EhosContract.Clock.at(DateTime.add(DateTime.utc_now(), 2, :day), fn ->
        for kind <- [
              "read_model:balances",
              "read_model:ledger_lines",
              "process_manager:first_deposit_chase"
            ] do
          assert Subscription.rebuild(SchemaRepo, "dispatch_rig.ledger:" <> kind) == :ok
        end

        assert Testing.drain().failing == []
      end)

      assert SchemaRepo.query!("SELECT account_id FROM dispatch_rig_notices ORDER BY 1").rows ==
               [["a-1"], ["a-2"]]

      # Nothing ran as this role created anything, not even a temporary table.
      assert owned(app) == [[0]]
    end
  end
end
