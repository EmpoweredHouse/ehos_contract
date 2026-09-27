defmodule EhOsContractHost.Repo.Migrations.UpgradeEhOsContractToV5 do
  @moduledoc """
  The engine's v05: the tables of crypto-shredding — the subjects' data keys and
  the erasures. A separate migration, as `EhOsContract.Migrations` prescribes for an
  upgrade.
  """

  use Ecto.Migration

  def up, do: EhOsContract.Migrations.up(version: 5)
  def down, do: EhOsContract.Migrations.down(version: 5)
end
