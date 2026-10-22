defmodule EhOsContract.GraphRenderer.SchemaTest do
  # #400: the schema this package carries is the engine's, byte for byte, so a host that reads it
  # here reads the format the engine writes. In this repository the engine is beside it.
  use ExUnit.Case, async: true

  alias EhOsContract.GraphRenderer

  @engine Path.expand("../../eh_os_contract/priv/schema/graph.v1.json", __DIR__)

  test "the schema it carries is the engine's graph.v1" do
    assert File.read!(GraphRenderer.schema_path()) == File.read!(@engine),
           "priv/schema/graph.v1.json differs from the engine's; copy it again from #{@engine}"
  end

  test "the schema names the version it describes" do
    schema = GraphRenderer.schema_path() |> File.read!() |> JSON.decode!()

    assert schema["$id"] == "urn:eh-os-contract:schema:graph.v1"
  end
end
