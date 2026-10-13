defmodule Taxvision.Repo.Migrations.UpgradeEhOsContractToV3 do
  use Ecto.Migration

  @moduledoc """
  The engine's storage, raised to version 3 as a host raises it: a migration of its own,
  not an edit of the one that created it.
  """

  def up, do: EhOsContract.Migrations.up(version: 3)

  def down, do: EhOsContract.Migrations.down(version: 3)
end
