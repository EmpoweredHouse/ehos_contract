defmodule EhOsContractHost.Repo.Migrations.UpgradeEhOsContractToV2 do
  use Ecto.Migration

  @moduledoc """
  The engine's storage, raised to version 2 as a host raises it: a migration of its own,
  not an edit of the one that created it.
  """

  def up, do: EhOsContract.Migrations.up(version: 2)

  def down, do: EhOsContract.Migrations.down(version: 2)
end
