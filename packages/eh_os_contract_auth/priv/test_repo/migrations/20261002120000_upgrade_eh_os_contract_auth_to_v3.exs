defmodule EhOsContract.Auth.TestRepo.Migrations.UpgradeEhOsContractAuthToV3 do
  @moduledoc """
  V03, the sessions of people signed in through EHOS, as a separate migration — the
  upgrade shape `EhOsContract.Auth.Migrations` prescribes.
  """

  use Ecto.Migration

  def up, do: EhOsContract.Auth.Migrations.up(version: 3)
  def down, do: EhOsContract.Auth.Migrations.down(version: 3)
end
