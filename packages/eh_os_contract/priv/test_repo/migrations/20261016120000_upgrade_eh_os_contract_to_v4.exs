defmodule EhOsContract.TestRepo.Migrations.UpgradeEhOsContractToV4 do
  use Ecto.Migration

  @moduledoc """
  The engine's storage raised to version 4, byte for byte as the moduledoc of
  `EhOsContract.Migrations` tells a consumer to write it.
  """

  def up, do: EhOsContract.Migrations.up(version: 4)
  def down, do: EhOsContract.Migrations.down(version: 4)
end
