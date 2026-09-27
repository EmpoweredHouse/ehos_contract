defmodule EhOsContractHost.Repo.Migrations.AddEhOsContractAuth do
  @moduledoc """
  The credential verifier's tables (v2 stage EA): the last key set seen from EHOS,
  and one row per authorization decision. Its own migration module, as
  `EhOsContract.Auth.Migrations` prescribes.
  """

  use Ecto.Migration

  def up, do: EhOsContract.Auth.Migrations.up()
  def down, do: EhOsContract.Auth.Migrations.down()
end
