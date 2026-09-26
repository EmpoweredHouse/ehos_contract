defmodule EhOsContract.Web.TestHost.Repo.Migrations.UpgradeEhOsContractToV4 do
  @moduledoc """
  The engine's v04: the tables of the consumers that run outside the dispatch
  transaction — subscriptions, process managers, the runs an event belongs to. A
  separate migration, as `EhOsContract.Migrations` prescribes for an upgrade.
  """

  use Ecto.Migration

  def up, do: EhOsContract.Migrations.up(version: 4)
  def down, do: EhOsContract.Migrations.down(version: 4)
end
