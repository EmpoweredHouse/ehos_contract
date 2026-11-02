defmodule EhOsContract.Web.TestHost.Repo.Migrations.UpgradeEhOsContractToV5 do
  use Ecto.Migration

  @moduledoc """
  The engine's storage raised to version 5, as `EhOsContract.Migrations`' moduledoc
  tells a host to raise it: a migration of its own.
  """

  def up, do: EhOsContract.Migrations.up(version: 5)
  def down, do: EhOsContract.Migrations.down(version: 5)
end
