defmodule EhOsContract.Web.TestHost.Repo.Migrations.UpgradeEhOsContractToV2 do
  use Ecto.Migration

  @moduledoc """
  The engine's storage raised to version 2, as `EhOsContract.Migrations`' moduledoc
  tells a host to raise it: a migration of its own.
  """

  def up, do: EhOsContract.Migrations.up(version: 2)
  def down, do: EhOsContract.Migrations.down(version: 2)
end
