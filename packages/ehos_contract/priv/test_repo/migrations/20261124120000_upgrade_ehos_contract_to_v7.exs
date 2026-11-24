defmodule EhosContract.TestRepo.Migrations.UpgradeEhosContractToV7 do
  use Ecto.Migration

  @moduledoc """
  The engine's storage raised to version 7, byte for byte as the moduledoc of
  `EhosContract.Migrations` tells a consumer to write it.
  """

  def up, do: EhosContract.Migrations.up(version: 7)
  def down, do: EhosContract.Migrations.down(version: 7)
end
