defmodule PNS.Web.PackageTest do
  @moduledoc """
  What a package declares about itself.

  The Jason assertion is the awkward one and is the only mechanical pin available:
  removing `{:jason, ...}` from `deps/0` leaves the build green, because the
  dependency still arrives transitively through `{:pns, path: ...}`. "Declared, not
  inherited" is a rule this repository states three times and that nothing else can
  check.
  """

  use ExUnit.Case, async: true

  test "Jason is a direct dependency, not one inherited from a neighbour" do
    declared = Mix.Project.config()[:deps] |> Enum.map(&elem(&1, 0))

    assert :jason in declared,
           "this package calls Jason directly. Phoenix and LiveView both list it " <>
             "`optional: true`, so without this line it arrives only because `pns` happens " <>
             "to need it — and breaks the day `pns` stops"
  end

  test "the metadata Hex would need is present, even though publication is held" do
    package = Mix.Project.config()[:package]

    assert package[:licenses] == ["Apache-2.0"]
    assert File.exists?("LICENSE")
    assert File.exists?("NOTICE"), "a vendored third-party build needs its attribution in a file"
    assert File.exists?("README.md")
  end
end
