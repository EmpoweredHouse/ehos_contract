defmodule EhosContractHost.Repo.Migrations.AddEhosContractAuth do
  @moduledoc """
  The credential verifier's tables (v2 stage EA): the last key set seen from EHOS,
  and one row per authorization decision. Its own migration module, as
  `EhosContract.Auth.Migrations` prescribes.
  """

  use Ecto.Migration

  def up, do: EhosContract.Auth.Migrations.up()
  def down, do: EhosContract.Auth.Migrations.down()
end
