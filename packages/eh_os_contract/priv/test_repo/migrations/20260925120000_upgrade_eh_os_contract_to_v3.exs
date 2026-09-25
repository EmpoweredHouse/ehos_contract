defmodule EhOsContract.TestRepo.Migrations.UpgradeEhOsContractToV3 do
  @moduledoc """
  The engine's v03: the log becomes a store (positions, streams, tags, the append
  lock, append-only triggers, the commands table). A separate migration, as
  `EhOsContract.Migrations` prescribes for an upgrade.
  """

  use Ecto.Migration

  # `down(version: 3)`, not `version: 2`: `down/1` walks *down to* the target, so
  # asking for 2 would run V03.down and then V02.down.
  def up, do: EhOsContract.Migrations.up(version: 3)
  def down, do: EhOsContract.Migrations.down(version: 3)
end
