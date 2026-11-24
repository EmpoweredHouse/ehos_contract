defmodule EhosContract.Web.TestHost.Repo.Migrations.UpgradeEhosContractToV3 do
  use Ecto.Migration

  @moduledoc """
  The engine's storage raised to version 3, as `EhosContract.Migrations`' moduledoc
  tells a host to raise it: a migration of its own.
  """

  def up, do: EhosContract.Migrations.up(version: 3)
  def down, do: EhosContract.Migrations.down(version: 3)
end
