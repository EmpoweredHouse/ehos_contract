defmodule EhOsContract.Web.TestHost.Repo.Migrations.UpgradeEhOsContractToV3 do
  use Ecto.Migration

  @moduledoc """
  The engine's storage raised to version 3, as `EhOsContract.Migrations`' moduledoc
  tells a host to raise it: a migration of its own.
  """

  def up, do: EhOsContract.Migrations.up(version: 3)
  def down, do: EhOsContract.Migrations.down(version: 3)
end
