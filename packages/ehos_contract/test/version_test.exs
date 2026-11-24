defmodule EhosContract.VersionTest do
  @moduledoc """
  The engine version is in the report because what counts as drift has moved more
  than once, and a number nobody can attribute to an arithmetic is not evidence.

  This file pins the cheap half. The half that matters — that a verdict-moving
  change actually gets a `CHANGELOG.md` entry — cannot be tested, and says so in
  that file and in the `review-pr` skill.
  """

  use ExUnit.Case, async: true

  test "the version comes from mix.exs, not from a literal somebody will forget" do
    assert EhosContract.version() == Mix.Project.config()[:version]
  end

  test "it is a version, not whatever `Application.spec/2` hands back" do
    # `Application.spec(:ehos_contract, :vsn)` returns a charlist and needs the application
    # loaded. Both would reach a report renderer and a JSON encoder as surprises.
    assert is_binary(EhosContract.version())
    assert EhosContract.version() =~ ~r/^\d+\.\d+\.\d+/
  end
end
