defmodule EhOsContract.TestRepo.Migrations.AddEhOsContract do
  use Ecto.Migration

  @moduledoc """
  The package's own test database, migrated the way a consumer migrates.

  Byte for byte the file `docs` tells a consumer to write, including the part
  where Oban's tables are Oban's: `EhOsContract.Migrations.up/1` does not wrap them, so the
  call sits here where it can be seen. If the instruction in the moduledoc of
  `EhOsContract.Migrations` is ever wrong, this suite stops running.
  """

  def up do
    Oban.Migration.up()
    EhOsContract.Migrations.up()
  end

  def down do
    EhOsContract.Migrations.down()
    Oban.Migration.down(version: 1)
  end
end
