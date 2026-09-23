defmodule EhOsContract.Web.TestHost.Repo.Migrations.AddEhOsContract do
  use Ecto.Migration

  @moduledoc """
  This package's own test database, migrated the way any consumer of
  `packages/eh_os_contract` migrates — byte for byte what `EhOsContract.Migrations`'
  moduledoc tells a host to write, Oban's tables included.
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
