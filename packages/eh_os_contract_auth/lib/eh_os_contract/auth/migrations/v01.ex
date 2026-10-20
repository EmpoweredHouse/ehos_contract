defmodule EhOsContract.Auth.Migrations.V01 do
  @moduledoc false

  # The last key set this application fetched from EHOS. Public
  # keys, so the table is a freshness concern and not a secrecy one; it exists so a
  # restart while EHOS is down still verifies credentials.

  use Ecto.Migration

  @doc false
  @spec up() :: :ok
  def up do
    create table(:eh_os_contract_auth_keys, primary_key: false) do
      # The key's RFC 7638 thumbprint, which a credential's header names as `kid`.
      add :kid, :text, primary_key: true
      # The public members only: kty, crv, x.
      add :jwk, :map, null: false
      add :fetched_at, :utc_datetime_usec, null: false
    end

    :ok
  end

  @doc false
  @spec down() :: :ok
  def down do
    drop table(:eh_os_contract_auth_keys)
    :ok
  end
end
