defmodule EhOsContract.TestRepo.Migrations.UpgradeEhOsContractToV2 do
  use Ecto.Migration

  @moduledoc """
  The engine's storage raised to version 2, byte for byte as the moduledoc of
  `EhOsContract.Migrations` tells a consumer to write it.
  """

  def up, do: EhOsContract.Migrations.up(version: 2)
  def down, do: EhOsContract.Migrations.down(version: 2)
end
