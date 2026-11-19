defmodule EhOsContract.TestRepo.Migrations.UpgradeEhOsContractToV6 do
  use Ecto.Migration

  @moduledoc """
  The engine's storage raised to version 6, byte for byte as the moduledoc of
  `EhOsContract.Migrations` tells a consumer to write it.
  """

  def up, do: EhOsContract.Migrations.up(version: 6)
  def down, do: EhOsContract.Migrations.down(version: 6)
end
