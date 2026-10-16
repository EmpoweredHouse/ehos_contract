defmodule EhOsContract.Web.TestHost.Repo.Migrations.UpgradeEhOsContractToV4 do
  use Ecto.Migration

  @moduledoc """
  The engine's storage raised to version 4, as `EhOsContract.Migrations`' moduledoc
  tells a host to raise it: a migration of its own.
  """

  def up, do: EhOsContract.Migrations.up(version: 4)
  def down, do: EhOsContract.Migrations.down(version: 4)
end
