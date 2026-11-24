defmodule EhosContract.Web.TestHost.Repo.Migrations.UpgradeEhosContractToV5 do
  use Ecto.Migration

  @moduledoc """
  The engine's storage raised to version 5, as `EhosContract.Migrations`' moduledoc
  tells a host to raise it: a migration of its own.
  """

  def up, do: EhosContract.Migrations.up(version: 5)
  def down, do: EhosContract.Migrations.down(version: 5)
end
