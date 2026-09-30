defmodule EhOsContract.Auth.Migrations do
  @moduledoc """
  The tables this package owns, as a migration a consumer calls — the shape of
  `EhOsContract.Migrations`, for the reason it gives: a library that owns storage
  ships the migration for it.

      mix ecto.gen.migration add_eh_os_contract_auth

      defmodule MyApp.Repo.Migrations.AddEhOsContractAuth do
        use Ecto.Migration

        def up, do: EhOsContract.Auth.Migrations.up()
        def down, do: EhOsContract.Auth.Migrations.down()
      end

  A later release that raises `current_version/0` is another generated migration
  calling `up(version: n)`, never an edit to the one above.

  The version is recorded in a comment on `eh_os_contract_auth_keys`, as the engine
  records its own on `eh_os_contract_events` — and, like it, through the connection's
  `search_path` rather than in `public` by name, so the tables work in a schema of the
  application's own ("In a schema other than `public`" in `EhOsContract.Migrations`).
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
  Runs every version between what the database has and `:version`, which defaults
  to `current_version/0`. A database already there is left alone.
  """
  @spec up(keyword()) :: :ok
  def up(opts \\ []) when is_list(opts) do
    target = Keyword.get(opts, :version, @current_version)
    recorded = migrated_version()

    if recorded < target, do: change(max(recorded + 1, @initial_version)..target, :up), else: :ok
  end

  @doc """
  Rolls back from what the database has down to and including `:version`, which
  defaults to `initial_version/0`: the package's storage dropped entirely.
  """
  @spec down(keyword()) :: :ok
  def down(opts \\ []) when is_list(opts) do
    target = Keyword.get(opts, :version, @initial_version)
    recorded = migrated_version()

    if recorded >= target, do: change(recorded..target//-1, :down), else: :ok
  end

  @doc "The version the database is at, or `0` when the package's storage is absent."
  @spec migrated_version() :: non_neg_integer()
  def migrated_version do
    query =
      "SELECT pg_catalog.obj_description(to_regclass('eh_os_contract_auth_keys'), 'pg_class')"

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

  defp record_version(0), do: :ok

  defp record_version(version) do
    execute("COMMENT ON TABLE eh_os_contract_auth_keys IS '#{version}'")
  end
end
