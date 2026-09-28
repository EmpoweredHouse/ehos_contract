defmodule Taxvision.CommitRepo do
  @moduledoc """
  The repo for the sandbox's tests that need real commits: concurrent dispatches
  over one consistency boundary (v2 plan, E9b).

  `Taxvision.Repo` runs every test inside a transaction that rolls back, with one
  connection per test, so no two decisions ever read the same boundary at once. A
  committed row in the log can never be deleted, since the log is append-only, so
  these tests get a database of their own, one per checkout, created afresh before each run and
  migrated with the host's own migrations — the engine's `EhOsContract.CommitRepo`,
  on the host's side of the seam.

  Tests using it are `async: false`, and each writes under a payer of its own,
  because rows from earlier tests of the same run are still there.
  """

  use Ecto.Repo, otp_app: :eh_os_contract_host, adapter: Ecto.Adapters.Postgres

  @doc """
  Drops the database, creates it again and starts the repo on it, migrated to the
  newest of `Taxvision.Repo`'s migrations: dropping is the only way the log empties.
  """
  @spec reset!() :: :ok
  def reset! do
    config = config()

    # A drop refused because another run of this checkout holds the database is said
    # as that, not as a mismatch later.
    case Ecto.Adapters.Postgres.storage_down(config) do
      result when result in [:ok, {:error, :already_down}] ->
        :ok

      {:error, reason} ->
        raise "cannot drop #{config[:database]} for a fresh run, most likely because " <>
                "another test run is using it: #{inspect(reason)}"
    end

    :ok = Ecto.Adapters.Postgres.storage_up(config)
    {:ok, _} = start_link()

    # The migrator compiles each migration file again, and the ones `mix test` just
    # ran are loaded already; that it redefines them says nothing about them.
    previous = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      path = Ecto.Migrator.migrations_path(Taxvision.Repo)
      Ecto.Migrator.run(__MODULE__, path, :up, all: true, log: false)
    after
      Code.put_compiler_option(:ignore_module_conflict, previous)
    end

    :ok
  end
end
