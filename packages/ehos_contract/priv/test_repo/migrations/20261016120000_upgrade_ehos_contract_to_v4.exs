defmodule EhosContract.TestRepo.Migrations.UpgradeEhosContractToV4 do
  use Ecto.Migration

  @moduledoc """
  The engine's storage raised to version 4, byte for byte as the moduledoc of
  `EhosContract.Migrations` tells a consumer to write it.
  """

  def up, do: EhosContract.Migrations.up(version: 4)
  def down, do: EhosContract.Migrations.down(version: 4)
end
