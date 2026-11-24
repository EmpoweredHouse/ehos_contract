defmodule EhosContract.Web.TestHost.Repo.Migrations.UpgradeEhosContractToV7 do
  use Ecto.Migration

  @moduledoc """
  The engine's storage raised to version 7, as `EhosContract.Migrations`' moduledoc
  tells a host to raise it: a migration of its own.
  """

  def up, do: EhosContract.Migrations.up(version: 7)
  def down, do: EhosContract.Migrations.down(version: 7)
end
