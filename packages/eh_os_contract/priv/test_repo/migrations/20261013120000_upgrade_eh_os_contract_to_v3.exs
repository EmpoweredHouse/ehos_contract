defmodule EhOsContract.TestRepo.Migrations.UpgradeEhOsContractToV3 do
  use Ecto.Migration

  @moduledoc """
  The engine's storage raised to version 3, byte for byte as the moduledoc of
  `EhOsContract.Migrations` tells a consumer to write it.
  """

  def up, do: EhOsContract.Migrations.up(version: 3)
  def down, do: EhOsContract.Migrations.down(version: 3)
end
