defmodule EhosContract.TestRepo.Migrations.UpgradeEhosContractToV2 do
  use Ecto.Migration

  @moduledoc """
  The engine's storage raised to version 2, byte for byte as the moduledoc of
  `EhosContract.Migrations` tells a consumer to write it.
  """

  def up, do: EhosContract.Migrations.up(version: 2)
  def down, do: EhosContract.Migrations.down(version: 2)
end
