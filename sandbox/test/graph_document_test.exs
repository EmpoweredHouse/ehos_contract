defmodule EhOsContract.GraphDocumentTest do
  @moduledoc """
  Plan E13a: the `graph.v1` document of every contract and every domain of the client
  trees — TaxVision, Rehmed, AppUnite's equipment — holds to the schema the engine
  ships, every id in it resolves, and none carries a personal value of Rehmed's. The
  engine's own suite checks its fixtures; these are the documents a renderer will
  actually be given.
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

  # The fields naming an owner, by kind: a value's `unit` is a unit of measure, and a
  # domain's contract's `process` is the process's name and label.
  @owners %{
    "stage" => ~w(process),
    "promise" => ~w(process),
    "status" => ~w(unit),
    "invariant" => ~w(of),
    "constraint" => ~w(of),
    "command" => ~w(unit),
    "event" => ~w(unit stage contract),
    "timer" => ~w(process_manager),
    "actor" => ~w(context),
    "value" => ~w(context),
    "entity" => ~w(context),
    "context" => ~w(subdomain),
    "contract" => ~w(context)
  }

  test "ids are unique in a document, and every relation, owner and scenario resolves in it" do
    for {module, document} <- documents() do
      nodes = for {_kind, ns} <- document["nodes"], n <- ns, do: n
      relations = for {_type, rs} <- document["relations"], r <- rs, do: r
      scenarios = for {_kind, ss} <- document["scenarios"] || %{}, s <- ss, do: s

      ids =
        Enum.map(nodes, & &1["id"]) ++
          Enum.map(relations, & &1["id"]) ++ Enum.map(scenarios, & &1["id"])

      assert ids == Enum.uniq(ids), "#{inspect(module)}: #{inspect(ids -- Enum.uniq(ids))}"

      here = MapSet.new(nodes, & &1["id"])

      for r <- relations, id <- [r["from"], r["to"]] do
        assert MapSet.member?(here, id), "#{inspect(module)}: #{r["id"]} ends at #{id}"
      end

      for {kind, ns} <- document["nodes"],
          n <- ns,
          key <- Map.get(@owners, kind, []),
          id = n[key] do
        assert MapSet.member?(here, id), "#{inspect(module)}: #{n["id"]}'s #{key} is #{id}"
      end

      relation_ids = MapSet.new(relations, & &1["id"])

      for s <- scenarios do
        assert MapSet.member?(here, s["target"]), "#{inspect(module)}: #{s["id"]}"

        for id <- s["covers"],
            do: assert(MapSet.member?(relation_ids, id), "#{inspect(module)}: #{s["id"]} #{id}")
      end
    end
  end

  # StatutoryReporting's policy scenarios start from ClinicalDocumentation's closing, a
  # sibling's event, whose personal fields are declared there: the same values the
  # exported model is held to (`E10OutputsTest`), in every graph document.
  test "no document carries Rehmed's personal scenario values" do
    for {module, document} <- documents() do
      encoded = Jason.encode!(document)

      for personal <- ["85010112345", "M54.5", "93.39"] do
        refute encoded =~ personal, "#{inspect(module)} carries #{personal}"
      end
    end

    # And the check is not empty: the scenarios are there, with what is not personal.
    reporting = Document.contract(Rehmed.Contracts.StatutoryReporting)
    assert [%{"event" => %{"data" => data}} | _] = reporting["scenarios"]["policy"]
    assert Map.has_key?(data, "pesel") and data["pesel"] == nil
  end

  test "a domain's document does not depend on the order its contracts are given in" do
    contracts = Registry.contracts()

    for domain <- Registry.domains() do
      assert Document.domain(domain, Enum.reverse(contracts)) ==
               Document.domain(domain, contracts)
    end
  end
end
