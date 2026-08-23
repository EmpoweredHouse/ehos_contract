defmodule PNS.Web.TestHost.Repo.Migrations.AddPns do
  use Ecto.Migration

  @moduledoc """
  This package's own test database, migrated the way any consumer of
  `packages/pns_core` migrates — byte for byte what `PNS.Migrations`'
  moduledoc tells a host to write, Oban's tables included.
  """

  def up do
    Oban.Migration.up()
    PNS.Migrations.up()
  end

  def down do
    PNS.Migrations.down()
    Oban.Migration.down(version: 1)
  end
end
