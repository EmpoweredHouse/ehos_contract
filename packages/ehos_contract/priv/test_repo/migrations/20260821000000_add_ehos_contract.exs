defmodule EhosContract.TestRepo.Migrations.AddEhosContract do
  use Ecto.Migration

  @moduledoc """
  The package's own test database, migrated the way a consumer migrates.

  Byte for byte the file `docs` tells a consumer to write, including the part
  where Oban's tables are Oban's: `EhosContract.Migrations.up/1` does not wrap them, so the
  call sits here where it can be seen. If the instruction in the moduledoc of
  `EhosContract.Migrations` is ever wrong, this suite stops running.
  """

  def up do
    Oban.Migration.up()
    EhosContract.Migrations.up()
  end

  def down do
    EhosContract.Migrations.down()
    Oban.Migration.down(version: 1)
  end
end
