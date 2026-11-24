defmodule EhosContract.Auth.TestRepo.Migrations.UpgradeEhosContractAuthToV4 do
  @moduledoc """
  V04, the tables renamed from `eh_os_contract_auth_*`, as a separate migration — the
  upgrade shape `EhosContract.Auth.Migrations` prescribes.
  """

  use Ecto.Migration

  def up, do: EhosContract.Auth.Migrations.up(version: 4)
  def down, do: EhosContract.Auth.Migrations.down(version: 4)
end
