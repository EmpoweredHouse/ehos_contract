defmodule EhOsContract.GraphOverlayTest do
  @moduledoc """
  Plan E13a, batch 5: the overlay of every contract and every domain of the client
  trees holds to the schema the engine ships and joins the document it names.
  """

  use Taxvision.DataCase, async: false

  alias EhOsContract.Graph.{Document, Overlay}
  alias EhOsContract.Registry

  @schema Overlay.schema_path() |> File.read!() |> Jason.decode!() |> JSV.build!()

  test "every overlay holds to its schema and names its document's digest" do
    contracts = Registry.contracts()

    overlays =
      for(c <- contracts, do: {Overlay.contract(c), Document.contract(c)}) ++
        for d <- Registry.domains(),
            do: {Overlay.domain(d, contracts), Document.domain(d, contracts)}

    for {overlay, document} <- overlays do
      assert {:ok, _} = JSV.validate(overlay, @schema),
             inspect(overlay["contract"] || overlay["domain"])

      assert overlay["document_digest"] == document["digest"]

      ids = for {_t, xs} <- document["nodes"], x <- xs, into: MapSet.new(), do: x["id"]
      defined = for {_t, xs} <- overlay["observed"]["relations"], x <- xs, do: x["id"]

      relations =
        for {_t, xs} <- document["relations"], x <- xs, into: MapSet.new(defined), do: x["id"]

      for id <- Map.keys(overlay["nodes"]), do: assert(MapSet.member?(ids, id), id)
      for id <- Map.keys(overlay["relations"]), do: assert(MapSet.member?(relations, id), id)
    end
  end
end
