defmodule EhosContract.GraphRenderer.PackageTest do
  @moduledoc """
  What the package declares about itself.
  """

  use ExUnit.Case, async: true

  test "the package carries the graph.v1 schema it draws, beside its bundle" do
    files = Mix.Project.config()[:package][:files]

    assert "priv/schema" in files
    assert "priv/static" in files
    refute "priv" in files
    assert File.exists?("priv/schema/graph.v1.json")
  end
end
