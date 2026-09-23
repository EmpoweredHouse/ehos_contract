defmodule EhOsContract.PackageTest do
  @moduledoc """
  Stage 5.7: **the package can actually be published.**

  Stage 3 was called "the package as a package" and closed in August, and until
  today `mix hex.build` refused this project outright: no `package/0`, no licence
  metadata, no licence file, no README. The seam was real — this package builds and
  tests standing alone — but the artifact at the end of it did not exist.

  Pinned by a test rather than trusted to a CI step, and the difference is
  asymmetric on purpose: deleting `licenses:` fails both this test and
  `mix hex.build`, while deleting the `LICENSE` file fails only this test. That is
  why this is the primary pin.
  """

  use ExUnit.Case, async: true

  setup do
    {:ok, config: Mix.Project.config()}
  end

  test "the metadata Hex requires is present", %{config: config} do
    package = config[:package]

    assert package[:name] == "pns"
    assert package[:licenses] == ["Apache-2.0"]
    assert is_binary(config[:description]) and config[:description] != ""
    assert package[:links]["GitHub"]
  end

  test "the licence travels with the package, not only as metadata", %{config: _} do
    # A package published from a subdirectory does not pick up the repository's
    # licence file. `licenses: ["Apache-2.0"]` is a claim; this is the text.
    assert File.exists?("LICENSE")
    assert File.exists?("README.md")
    assert File.exists?("CHANGELOG.md")
  end

  test "nothing under priv/ ships", %{config: config} do
    # The only thing there is this package's own test migration — an artifact of
    # testing `EhOsContract.Migrations` against itself, and nothing a consumer should get.
    # Hex's default `files:` would include it.
    refute Enum.any?(config[:package][:files], &String.starts_with?(&1, "priv"))
    refute Enum.any?(config[:package][:files], &String.starts_with?(&1, "test"))
  end

  test "the formatter export ships, so a consumer's contracts keep their shape", %{config: config} do
    # Without this file in the tarball, `mix format` in a consuming project rewrites
    # every contract as `event(:x, label: "...")`. The list here is the reason the
    # DSL reads like `Ecto.Schema` rather than like a pile of function calls.
    assert ".formatter.exs" in config[:package][:files]

    {formatter, _} = Code.eval_file(".formatter.exs")
    exported = formatter[:export][:locals_without_parens]

    for declaration <- [:event, :process, :external, :rule, :example, :command, :trace] do
      assert Enum.any?(exported, fn {name, _arity} -> name == declaration end),
             "#{declaration} is a declaration macro and is not exported to consumers' formatters"
    end
  end
end
