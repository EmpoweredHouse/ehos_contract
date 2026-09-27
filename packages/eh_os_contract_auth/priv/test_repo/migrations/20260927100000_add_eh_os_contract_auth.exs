defmodule EhOsContract.Auth.TestRepo.Migrations.AddEhOsContractAuth do
  @moduledoc """
  The package's own test database, migrated with the file its moduledoc tells a
  consumer to write. If that instruction is ever wrong, this suite stops running.
  """

  use Ecto.Migration

  def up, do: EhOsContract.Auth.Migrations.up()
  def down, do: EhOsContract.Auth.Migrations.down()
end
