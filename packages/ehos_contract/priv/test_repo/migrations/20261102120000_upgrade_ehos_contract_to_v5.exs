defmodule EhosContract.TestRepo.Migrations.UpgradeEhosContractToV5 do
  use Ecto.Migration

  @moduledoc """
  The engine's storage raised to version 5, byte for byte as the moduledoc of
  `EhosContract.Migrations` tells a consumer to write it.
  """

  def up, do: EhosContract.Migrations.up(version: 5)
  def down, do: EhosContract.Migrations.down(version: 5)
end
