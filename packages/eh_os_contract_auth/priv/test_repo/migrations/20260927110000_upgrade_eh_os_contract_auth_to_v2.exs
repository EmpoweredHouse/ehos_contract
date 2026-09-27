defmodule EhOsContract.Auth.TestRepo.Migrations.UpgradeEhOsContractAuthToV2 do
  @moduledoc """
  V02, the decisions table, as a separate migration — the upgrade shape
  `EhOsContract.Auth.Migrations` prescribes, followed here first.
  """

  use Ecto.Migration

  def up, do: EhOsContract.Auth.Migrations.up(version: 2)
  def down, do: EhOsContract.Auth.Migrations.down(version: 2)
end
