defmodule EhOsContract.GraphDocumentTest do
  @moduledoc """
  Plan E13a: the `graph.v1` document of every contract and every domain of the client
  trees — TaxVision, Rehmed, AppUnite's equipment — holds to the schema the engine
  ships, and each edge ends where it says. The engine's own suite checks its
  fixtures; these are the documents a renderer will actually be given.
  """

  use ExUnit.Case, async: true

  alias EhOsContract.Graph.Document
  alias EhOsContract.Registry

  @schema Document.schema_path() |> File.read!() |> Jason.decode!() |> JSV.build!()

  defp documents do
    contracts = Registry.contracts()

    for(c <- contracts, do: {c, Document.contract(c)}) ++
      for d <- Registry.domains(), do: {d, Document.domain(d, contracts)}
  end

  test "every contract and every domain gives a document, all of them" do
    names = documents() |> Enum.map(&elem(&1, 0)) |> Enum.map(&inspect/1)

    for prefix <- ~w(Taxvision. Rehmed. AppuniteEquipment.) do
      assert Enum.count(names, &String.starts_with?(&1, prefix)) >= 2, prefix
    end
  end

  test "every document holds to the schema" do
    for {module, document} <- documents() do
      case JSV.validate(document, @schema) do
        {:ok, _} -> :ok
        {:error, error} -> flunk("#{inspect(module)}: #{inspect(JSV.normalize_error(error))}")
      end
    end
  end

  test "every edge has an id of its own and ends at a node, only precedes at a group" do
    for {module, document} <- documents(), graph <- graphs(document) do
      nodes = MapSet.new(graph["nodes"], & &1["id"])
      groups = MapSet.new(graph["groups"], & &1["id"])
      edges = Enum.map(graph["edges"], & &1["id"])

      assert edges == Enum.uniq(edges),
             "#{inspect(module)}: #{inspect(edges -- Enum.uniq(edges))}"

      for %{"from" => from, "to" => to, "relation" => relation} <- graph["edges"],
          id <- [from, to] do
        ends = if relation == "precedes", do: groups, else: nodes
        assert MapSet.member?(ends, id), "#{inspect(module)}: #{relation} #{from} -> #{to}"
      end
    end
  end

  test "a domain's document does not depend on the order its contracts are given in" do
    contracts = Registry.contracts()

    for domain <- Registry.domains() do
      assert Document.domain(domain, Enum.reverse(contracts)) ==
               Document.domain(domain, contracts)
    end
  end

  defp graphs(%{"kind" => "contract", "graphs" => g}),
    do:
      [g["contract"]] ++
        List.wrap(g["process"]) ++ Map.values(g["units"]) ++ Map.values(g["lifecycles"])

  defp graphs(%{"kind" => "domain", "graphs" => g}), do: [g["context_map"], g["system"]]
end
