defmodule Taxvision.Repo.Migrations.AddEhOsContract do
  use Ecto.Migration

  @moduledoc """
  The engine's storage, created by the engine.

  This file replaced five hand-written migrations on 2026-08-21. They described
  tables this application does not own, does not query and cannot keep current —
  the schemas and every query against them live in `packages/eh_os_contract`. Oban is
  one line above this one for the same reason.

  Oban's tables stay Oban's: `EhOsContract.Migrations.up/1` does not wrap them, and the
  call sits in its own migration where a consumer can see it.
  """

  def up, do: EhOsContract.Migrations.up()

  def down, do: EhOsContract.Migrations.down()
end
