defmodule EhOsContract.Auth.Migrations.V03 do
  @moduledoc false

  # A person signed in through EHOS (`eh-os` D-64, docs/adr/browser-session.md): one row per
  # sign-in, and one per application the pages hold a credential for.
  #
  # The browser holds a random token; the row holds its SHA-256, so the table names no live
  # session (S2). The refresh token, the ID token and every credential are ciphertexts, each bound
  # to its row and column (S3): a reader of the database alone gets nothing it can present. What
  # the package selects, locks and expires by stays plain.

  use Ecto.Migration

  @doc false
  @spec up() :: :ok
  def up do
    create table(:eh_os_contract_auth_sessions) do
      # SHA-256 of the token in the browser's cookie session.
      add :token_hash, :binary, null: false
      # The ID token's `sub`, `sid` and `auth_time`: who, which sign-in at EHOS, and since when.
      add :subject, :text, null: false
      add :sid, :text, null: false
      add :auth_time, :utc_datetime, null: false
      add :refresh_token, :text, null: false
      add :id_token, :text, null: false
      # One renewal at a time (S4): who holds the lease, and until when by the database's clock.
      add :lease_holder, :text
      add :lease_until, :utc_datetime_usec

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("clock_timestamp()")
    end

    create unique_index(:eh_os_contract_auth_sessions, [:token_hash])
    # The next sign-in deletes rows past the absolute limit (S11).
    create index(:eh_os_contract_auth_sessions, [:auth_time])

    create table(:eh_os_contract_auth_session_credentials, primary_key: false) do
      add :session_id, references(:eh_os_contract_auth_sessions, on_delete: :delete_all),
        primary_key: true

      # The application's address, as EHOS takes it in `resource` (D-68); the client's own too.
      add :resource, :text, primary_key: true
      add :token, :text
      add :expires_at, :utc_datetime_usec

      # A refusal remembered, so a person without a role there is not asked about on every page (S5).
      add :refused_until, :utc_datetime_usec
    end

    create constraint(:eh_os_contract_auth_session_credentials, :token_expires,
             check: "(token IS NULL) = (expires_at IS NULL)"
           )

    :ok
  end

  @doc false
  @spec down() :: :ok
  def down do
    drop table(:eh_os_contract_auth_session_credentials)
    drop table(:eh_os_contract_auth_sessions)
    :ok
  end
end
