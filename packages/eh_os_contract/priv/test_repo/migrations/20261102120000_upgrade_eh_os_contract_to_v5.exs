defmodule EhOsContract.TestRepo.Migrations.UpgradeEhOsContractToV5 do
  use Ecto.Migration

  @moduledoc """
  The engine's storage raised to version 5, byte for byte as the moduledoc of
  `EhOsContract.Migrations` tells a consumer to write it.
  """

  def up, do: EhOsContract.Migrations.up(version: 5)
  def down, do: EhOsContract.Migrations.down(version: 5)
end
