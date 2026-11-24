defmodule EhosContract.Auth.Migrations.V04 do
  @moduledoc false

  # The package was called `eh_os_contract_auth` until 0.8 (#428). V01–V03 created its
  # tables under that name and stay as databases ran them; this version renames them,
  # with their indexes and constraints, by prefix from the catalog, as the engine's
  # V07 renames its own.

  use Ecto.Migration

  @doc false
  @spec up() :: :ok
  def up do
    execute EhosContract.Migrations.rename_prefix("eh_os_contract_auth_", "ehos_contract_auth_")
    :ok
  end

  @doc false
  @spec down() :: :ok
  def down do
    execute EhosContract.Migrations.rename_prefix("ehos_contract_auth_", "eh_os_contract_auth_")
    :ok
  end
end
