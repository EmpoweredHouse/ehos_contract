defmodule PNS.TestRepo.Migrations.AddPns do
  use Ecto.Migration

  @moduledoc """
  The package's own test database, migrated the way a consumer migrates.

  Byte for byte the file `docs` tells a consumer to write, including the part
  where Oban's tables are Oban's: `PNS.Migrations.up/1` does not wrap them, so the
  call sits here where it can be seen. If the instruction in the moduledoc of
  `PNS.Migrations` is ever wrong, this suite stops running.
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
