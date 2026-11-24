defmodule EhosContract.Web.TestHost.Repo.Migrations.AddEhosContract do
  use Ecto.Migration

  @moduledoc """
  This package's own test database, migrated the way any consumer of
  `packages/ehos_contract` migrates — byte for byte what `EhosContract.Migrations`'
  moduledoc tells a host to write, Oban's tables included.
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
