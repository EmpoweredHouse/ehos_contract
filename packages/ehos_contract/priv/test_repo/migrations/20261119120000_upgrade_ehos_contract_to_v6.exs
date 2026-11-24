defmodule EhosContract.TestRepo.Migrations.UpgradeEhosContractToV6 do
  use Ecto.Migration

  @moduledoc """
  The engine's storage raised to version 6, byte for byte as the moduledoc of
  `EhosContract.Migrations` tells a consumer to write it.
  """

  def up, do: EhosContract.Migrations.up(version: 6)
  def down, do: EhosContract.Migrations.down(version: 6)
end
