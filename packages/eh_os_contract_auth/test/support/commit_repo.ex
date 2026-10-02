defmodule EhOsContract.Auth.CommitRepo do
  @moduledoc """
  The repo for tests that need real commits (EB3, S4 in docs/adr/browser-session.md):
  two processes renewing one session on connections of their own, and a renewal
  that must hold no transaction while it calls EHOS. The sandbox wraps each test in
  a transaction that rolls back, which is exactly what these tests cannot have.

  It has a database of its own, `eh_os_contract_auth_test_commits`, emptied by
  migrating it down and up before each run (`test_helper.exs`), as the engine's
  `EhOsContract.CommitRepo` is. Tests using it are `async: false` and delete their
  own rows.
  """

  use Ecto.Repo, otp_app: :eh_os_contract_auth, adapter: Ecto.Adapters.Postgres

  @doc "Migrates the database down to nothing and back up to the newest migration."
  @spec reset!() :: :ok
  def reset! do
    previous = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      path = Ecto.Migrator.migrations_path(__MODULE__)
      Ecto.Migrator.run(__MODULE__, path, :down, all: true, log: false)
      Ecto.Migrator.run(__MODULE__, path, :up, all: true, log: false)
      :ok
    after
      Code.put_compiler_option(:ignore_module_conflict, previous)
    end
  end
end
