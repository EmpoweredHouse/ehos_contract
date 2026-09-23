defmodule EhOsContract.Migrations do
  @moduledoc """
  The tables the engine owns, as a migration a consumer calls.

  Until 2026-08-21 these five tables lived in the host application's
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

  The engine dispatches asynchronous handlers through Oban, so a consumer needs
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
  """

  use Ecto.Migration

  @initial_version 1
  @current_version 2

  @doc "The oldest version this module can create."
  @spec initial_version() :: pos_integer()
  def initial_version, do: @initial_version

  @doc "The version `up/1` migrates to when no version is given."
  @spec current_version() :: pos_integer()
  def current_version, do: @current_version

  @doc """
  Runs every version between what the database has and `:version`.

  Defaults to `current_version/0`. Idempotent: a database already at or beyond
  the target is left alone, so re-running a consumer's migration is safe.
  """
  @spec up(keyword()) :: :ok
  def up(opts \\ []) when is_list(opts) do
    target = Keyword.get(opts, :version, @current_version)
    recorded = migrated_version()

    cond do
      recorded == 0 -> change(@initial_version..target, :up)
      recorded < target -> change((recorded + 1)..target, :up)
      true -> :ok
    end
  end

  @doc """
  Rolls back from what the database has down to and including `:version`.

  Defaults to `initial_version/0`, which drops the engine's storage entirely.
  """
  @spec down(keyword()) :: :ok
  def down(opts \\ []) when is_list(opts) do
    target = Keyword.get(opts, :version, @initial_version)
    recorded = max(migrated_version(), @initial_version)

    if recorded >= target, do: change(recorded..target//-1, :down), else: :ok
  end

  @doc """
  The version the database is at, or `0` when the engine's storage is absent.

  Reading it costs a query rather than a guess on purpose: "the table exists, so
  it must be current" is the assumption that makes the second version unshippable.
  """
  @spec migrated_version() :: non_neg_integer()
  def migrated_version do
    query = """
    SELECT pg_catalog.obj_description(pg_class.oid, 'pg_class')
    FROM pg_class
    LEFT JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
    WHERE pg_class.relname = 'eh_os_contract_events'
    AND pg_namespace.nspname = 'public'
    """

    case repo().query(query, [], log: false) do
      {:ok, %{rows: [[version]]}} when is_binary(version) -> String.to_integer(version)
      _ -> 0
    end
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
    execute("COMMENT ON TABLE \"public\".eh_os_contract_events IS '#{version}'")
  end
end
