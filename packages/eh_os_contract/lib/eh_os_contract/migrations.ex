defmodule EhOsContract.Migrations do
  @moduledoc """
  The tables the engine owns, as a migration a consumer calls.

  Until 2026-08-21 the tables lived in the host application's
  `priv/repo/migrations/`, interleaved with the client tree's own. That made the
  storage the host's to maintain, which is exactly backwards: the schemas are in
  this package, the queries are in this package, and a host that fell a column
  behind found out from a crash. A library that owns storage ships the migration
  for it — the precedent is Oban, and this follows its shape deliberately rather
  than inventing one.

  ## Usage

      mix ecto.gen.migration add_eh_os_contract

  and call into here:

      defmodule MyApp.Repo.Migrations.AddEhOsContract do
        use Ecto.Migration

        def up, do: EhOsContract.Migrations.up()
        def down, do: EhOsContract.Migrations.down()
      end

  When a later release raises `current_version/0`, the upgrade is another
  generated migration and not a rewrite of the one above:

      defmodule MyApp.Repo.Migrations.UpgradeEhOsContractToV2 do
        use Ecto.Migration

        def up, do: EhOsContract.Migrations.up(version: 2)
        def down, do: EhOsContract.Migrations.down(version: 2)
      end

  **The mechanism exists at version 1, when there is nothing to upgrade from.**
  That is the point of building it now: the first schema change is the moment it
  is too late to add, because by then every consumer is already on an unversioned
  create and there is no recorded state to migrate from.

  ## Oban's tables are not ours

  The engine runs effects and timers through Oban, so a consumer needs
  Oban's tables too. Those are Oban's to create, and `up/1` deliberately does not
  wrap `Oban.Migration.up/1`: wrapping it would tie the engine's version to
  Oban's, hide an upgrade the consumer must decide about, and break the moment a
  consumer already runs Oban for its own work. Call it yourself, alongside this:

      def up do
        Oban.Migration.up()
        EhOsContract.Migrations.up()
      end

  ## Where the version is recorded

  In a comment on `eh_os_contract_events`, read back by `migrated_version/0`. This is Oban's
  trick and it is used here for Oban's reason: `up/1` has to know what the
  database already has, and the alternative — a table of our own to hold one
  integer — is a second thing to migrate before you can migrate anything.

  ## In a schema other than `public`

  Nothing here names a schema. The tables, the functions and the triggers are
  created unqualified, so they land in the first schema of the connection's
  `search_path`; the version is read with `to_regclass/1` and written with an
  unqualified `COMMENT ON TABLE`, which resolve `eh_os_contract_events` through the
  same path; and every query at run time is unqualified too. So an application
  whose tables live in their own schema sets it on the repo and nothing else:

      config :my_app, MyApp.Repo, parameters: [search_path: "ledger_production"]

  The role that migrates needs to create in that schema and nowhere else, and the
  role the application runs as needs only `SELECT`, `INSERT`, `UPDATE` and `DELETE`
  on the tables and `USAGE` on the sequences: nothing at run time creates, alters or
  drops anything. Oban's tables go where its `prefix:` says, and the engine reads
  them there.

  Until 2026-09-30 the version was read from and written to `public` by name,
  whatever the path said, and in any other schema the first `up/0` failed on a
  `public.eh_os_contract_events` that did not exist (issue #51).
  """

  use Ecto.Migration

  @initial_version 1
  @current_version 1

  @doc "The oldest version this module can create."
  @spec initial_version() :: pos_integer()
  def initial_version, do: @initial_version

  @doc "The version `up/1` migrates to when no version is given."
  @spec current_version() :: pos_integer()
  def current_version, do: @current_version

  @doc """
  Runs every version between what the database has and `:version`.

  Defaults to `current_version/0`. Idempotent: a database already at the target,
  or beyond it within the versions this release knows, is left alone, so re-running
  a consumer's migration is safe.

  Raises on a target this release does not have, and on a database that records a
  version it does not know: one migrated by a newer release, or before 0.3.0, whose
  versions 2–5 are gone (plan E11c). Left alone, such a database would pass as
  current, and a later version of this module would skip what it adds.
  """
  @spec up(keyword()) :: :ok
  def up(opts \\ []) when is_list(opts) do
    target = target!(Keyword.get(opts, :version, @current_version))
    recorded = known!(migrated_version())

    cond do
      recorded == 0 -> change(@initial_version..target, :up)
      recorded < target -> change((recorded + 1)..target, :up)
      true -> :ok
    end
  end

  @doc """
  Rolls back from what the database has down to and including `:version`.

  Defaults to `initial_version/0`, which drops the engine's storage entirely. Raises,
  as `up/1` does, on a version this release does not know.
  """
  @spec down(keyword()) :: :ok
  def down(opts \\ []) when is_list(opts) do
    target = target!(Keyword.get(opts, :version, @initial_version))
    recorded = max(known!(migrated_version()), @initial_version)

    if recorded >= target, do: change(recorded..target//-1, :down), else: :ok
  end

  @doc """
  The version the database is at, or `0` when the engine's storage is absent.

  Reading it costs a query rather than a guess on purpose: "the table exists, so
  it must be current" is the assumption that makes the second version unshippable.
  """
  @spec migrated_version() :: non_neg_integer()
  def migrated_version do
    query = "SELECT pg_catalog.obj_description(to_regclass('eh_os_contract_events'), 'pg_class')"

    case repo().query(query, [], log: false) do
      {:ok, %{rows: [[version]]}} when is_binary(version) -> String.to_integer(version)
      _ -> 0
    end
  end

  defp known!(recorded) when recorded > @current_version do
    raise ArgumentError,
          "eh_os_contract_events records version #{recorded}, and this release of " <>
            "eh_os_contract knows versions up to #{@current_version}. If a newer release " <>
            "migrated it, use that release. If it was migrated before 0.3.0, it cannot be " <>
            "upgraded, since 0.3.0 has a single version 1: drop the database and create it " <>
            "again, or keep it on 0.2."
  end

  defp known!(recorded), do: recorded

  defp target!(version) when version in @initial_version..@current_version//1, do: version

  defp target!(version) do
    raise ArgumentError,
          "eh_os_contract has migration versions #{@initial_version} to #{@current_version}, " <>
            "and #{inspect(version)} is not one of them. A host migration calling " <>
            "`up(version: 2..5)` is from before 0.3.0: delete it."
  end

  defp change(range, direction) do
    for index <- range do
      [__MODULE__, "V" <> String.pad_leading(to_string(index), 2, "0")]
      |> Module.concat()
      |> apply(direction, [])
    end

    case direction do
      :up -> record_version(Enum.max(range))
      :down -> record_version(Enum.min(range) - 1)
    end
  end

  # Version 0 is the absence of the tables, and the comment goes with them.
  defp record_version(0), do: :ok

  defp record_version(version) do
    execute("COMMENT ON TABLE eh_os_contract_events IS '#{version}'")
  end
end
