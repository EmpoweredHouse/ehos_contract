defmodule PNS.TestRepo.Migrations.UpgradePnsToV2 do
  @moduledoc """
  The engine's v02, as a separate migration rather than an edit to `add_pns`.

  This is the shape `PNS.Migrations`' own moduledoc prescribes for an upgrade,
  and this file is the first time anybody has followed it — the versioning was
  built in August before there was anything to upgrade from. Editing the original
  migration instead would do nothing here, because it has already run, and would
  silently create the wrong schema for a consumer starting from empty.
  """

  use Ecto.Migration

  # `down(version: 2)`, not `version: 1`. `down/1` walks *down to* the target, so
  # asking for 1 would run V02.down and then V01.down and drop every engine table.
  def up, do: PNS.Migrations.up(version: 2)
  def down, do: PNS.Migrations.down(version: 2)
end
