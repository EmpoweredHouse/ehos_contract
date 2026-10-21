defmodule EhOsContractHost.Repo.Migrations.UpgradeEhOsContractToV4 do
  use Ecto.Migration

  @moduledoc """
  The engine's storage, raised to version 4 as a host raises it: a migration of its own,
  not an edit of the one that created it.
  """

  def up, do: EhOsContract.Migrations.up(version: 4)

  def down, do: EhOsContract.Migrations.down(version: 4)
end
