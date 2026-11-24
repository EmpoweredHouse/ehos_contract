defmodule EhosContract.Auth.TestRepo.Migrations.UpgradeEhosContractAuthToV2 do
  @moduledoc """
  V02, the decisions table, as a separate migration — the upgrade shape
  `EhosContract.Auth.Migrations` prescribes, followed here first.
  """

  use Ecto.Migration

  def up, do: EhosContract.Auth.Migrations.up(version: 2)
  def down, do: EhosContract.Auth.Migrations.down(version: 2)
end
