defmodule EhosContractHost.Repo.Migrations.UpgradeEhosContractToV6 do
  use Ecto.Migration

  @moduledoc """
  The engine's storage, raised to version 6 as a host raises it: a migration of its own,
  not an edit of the one that created it.
  """

  def up, do: EhosContract.Migrations.up(version: 6)

  def down, do: EhosContract.Migrations.down(version: 6)
end
