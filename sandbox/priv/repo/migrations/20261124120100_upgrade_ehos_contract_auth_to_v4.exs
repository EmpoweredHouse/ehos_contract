defmodule EhosContractHost.Repo.Migrations.UpgradeEhosContractAuthToV4 do
  use Ecto.Migration

  @moduledoc """
  The credential package's storage, raised to version 4 as a host raises it.
  """

  def up, do: EhosContract.Auth.Migrations.up(version: 4)

  def down, do: EhosContract.Auth.Migrations.down(version: 4)
end
