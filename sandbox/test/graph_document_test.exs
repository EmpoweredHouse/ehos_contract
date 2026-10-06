defmodule EhOsContract.GraphDocumentTest do
  @moduledoc """
  Plan E13a: the `graph.v1` document of every contract and every domain of the client
  trees — TaxVision, Rehmed, AppUnite's equipment — holds to the schema the engine
  ships, and every id in it resolves. The engine's own suite checks its
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

  test "ids are unique in a document, and every relation and owner resolves in it" do
    owners = ~w(unit stage process process_manager of context subdomain contract)

    for {module, document} <- documents() do
      nodes = for {_kind, ns} <- document["nodes"], n <- ns, do: n
      relations = for {_type, rs} <- document["relations"], r <- rs, do: r
      ids = Enum.map(nodes, & &1["id"]) ++ Enum.map(relations, & &1["id"])

      assert ids == Enum.uniq(ids), "#{inspect(module)}: #{inspect(ids -- Enum.uniq(ids))}"

      here = MapSet.new(nodes, & &1["id"])

      for r <- relations, id <- [r["from"], r["to"]] do
        assert MapSet.member?(here, id), "#{inspect(module)}: #{r["id"]} ends at #{id}"
      end

      for n <- nodes, key <- owners, id = n[key], id != nil do
        assert MapSet.member?(here, id), "#{inspect(module)}: #{n["id"]}'s #{key} is #{id}"
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
end
