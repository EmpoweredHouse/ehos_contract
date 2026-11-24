defmodule EhosContract.TestRepo.Migrations.UpgradeEhosContractToV3 do
  use Ecto.Migration

  @moduledoc """
  The engine's storage raised to version 3, byte for byte as the moduledoc of
  `EhosContract.Migrations` tells a consumer to write it.
  """

  def up, do: EhosContract.Migrations.up(version: 3)
  def down, do: EhosContract.Migrations.down(version: 3)
end
