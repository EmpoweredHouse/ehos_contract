defmodule EhOsContract.CommitRepo do
  @moduledoc """
  The repo for tests that need real commits: concurrent appenders, transactions that
  commit out of order, migrations run down and up (v2 plan, stage E2).

  `EhOsContract.TestRepo` wraps every test in a transaction that rolls back, and
  that is exactly what these tests cannot have. A committed row in the log can never
  be deleted, because V01 makes the table append-only. So these tests get their own
  database, never the sandbox's, and it is emptied by migrating it down and up
  before each run rather than by deleting anything.

  Tests using it are `async: false`. ExUnit runs those one at a time, after every
  asynchronous test has finished, so nothing else sees these rows while they exist.
  Each test still writes under names of its own, because rows from earlier tests of
  the same run are still there.
  """

  use Ecto.Repo, otp_app: :eh_os_contract, adapter: Ecto.Adapters.Postgres

  @doc """
  Migrates the database down to nothing and back up to the newest migration. Every
  engine table is dropped on the way, the log included, which is the only way the log
  can be emptied.
  """
  @spec reset!() :: :ok
  def reset! do
    migrate(:down, all: true)
    migrate(:up, all: true)
    :ok
  end

  @doc """
  Runs this package's test migrations in `direction` (`Ecto.Migrator.run/4` options).

  The migrator compiles each migration file again on every run, and a module that is
  already loaded makes it warn about redefining it. Those warnings say nothing about
  the migration, so they are switched off for the call and only for the call.
  """
  @spec migrate(:up | :down, keyword()) :: [integer()]
  def migrate(direction, opts) do
    previous = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      path = Ecto.Migrator.migrations_path(__MODULE__)
      Ecto.Migrator.run(__MODULE__, path, direction, [log: false] ++ opts)
    after
      Code.put_compiler_option(:ignore_module_conflict, previous)
    end
  end
end
