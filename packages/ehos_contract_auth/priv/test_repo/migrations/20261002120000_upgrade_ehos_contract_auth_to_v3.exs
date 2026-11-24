defmodule EhosContract.Auth.TestRepo.Migrations.UpgradeEhosContractAuthToV3 do
  @moduledoc """
  V03, the sessions of people signed in through EHOS, as a separate migration — the
  upgrade shape `EhosContract.Auth.Migrations` prescribes.
  """

  use Ecto.Migration

  def up, do: EhosContract.Auth.Migrations.up(version: 3)
  def down, do: EhosContract.Auth.Migrations.down(version: 3)
end
