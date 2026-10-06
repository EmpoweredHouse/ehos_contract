defmodule EhOsContract.GraphDocumentTest do
  @moduledoc """
  Plan E13a, batch 2: the `graph.v1` documents — a contract's and a domain's — and the
  declared shape of a process as data. Every document of every fixture holds to the
  schema that ships in `priv/schema`, is JSON as it stands, says nothing from the log,
  and is the same document, digest included, however many times it is built.
  """

  use ExUnit.Case, async: true

  alias EhOsContract.Graph.{Contract, Declared, Document}
  alias EhOsContract.{Model, Registry}

  @schema Document.schema_path() |> File.read!() |> Jason.decode!() |> JSV.build!()

  defp documents do
    contracts = Registry.contracts()

    for(c <- contracts, do: {c, Document.contract(c)}) ++
      for d <- Registry.domains(), do: {d, Document.domain(d, contracts)}
  end

  defp graphs(%{"kind" => "contract", "graphs" => g}),
    do:
      [g["contract"]] ++
        List.wrap(g["process"]) ++ Map.values(g["units"]) ++ Map.values(g["lifecycles"])

  defp graphs(%{"kind" => "domain", "graphs" => g}), do: [g["context_map"], g["system"]]

  test "every document of every fixture holds to the schema" do
    for {module, document} <- documents() do
      case JSV.validate(document, @schema) do
        {:ok, _} -> :ok
        {:error, error} -> flunk("#{inspect(module)}: #{inspect(JSV.normalize_error(error))}")
      end
    end
  end

  test "the schema refuses the log, a look, an unknown relation and a key out of its kind" do
    document = Document.contract(ProcessShapes.Promised)
    valid? = &match?({:ok, _}, JSV.validate(&1, @schema))

    edit =
      &update_in(document, ["graphs", "contract", &1], fn [first | rest] ->
        [&2.(first) | rest]
      end)

    assert valid?.(document)
    refute valid?.(edit.("nodes", &Map.put(&1, "counts", [2, 1])))
    refute valid?.(edit.("edges", &Map.put(&1, "line", "dotted")))
    refute valid?.(edit.("edges", &Map.put(&1, "relation", "leads_to")))
    refute valid?.(Map.delete(document, "digest"))
    refute valid?.(edit.("nodes", &Map.put(&1, "name", nil)))
    refute valid?.(edit.("nodes", &Map.merge(&1, %{"kind" => "command", "terminal" => true})))
    refute valid?.(edit.("edges", &Map.delete(&1, "id")))
  end

  test "a document is JSON as it stands, and its digest is of the rest of it" do
    for {module, document} <- documents() do
      assert document |> Jason.encode!() |> Jason.decode!() == document, inspect(module)
      assert document["digest"] == Document.digest(document), inspect(module)
    end
  end

  test "the same declarations give the same documents, digests included" do
    assert documents() == documents()
  end

  test "an edge ends at a node of its graph, and only precedes at a group" do
    for {module, document} <- documents(), graph <- graphs(document) do
      nodes = MapSet.new(graph["nodes"], & &1["id"])
      groups = MapSet.new(graph["groups"], & &1["id"])
      ids = Enum.map(graph["nodes"], & &1["id"]) ++ Enum.map(graph["groups"], & &1["id"])

      assert ids == Enum.uniq(ids), "#{inspect(module)}: #{inspect(ids -- Enum.uniq(ids))}"

      # What the log says of an edge joins on its id, so two edges never share one.
      edges = Enum.map(graph["edges"], & &1["id"])

      assert edges == Enum.uniq(edges),
             "#{inspect(module)}: #{inspect(edges -- Enum.uniq(edges))}"

      for %{"from" => from, "to" => to, "relation" => relation} <- graph["edges"],
          id <- [from, to] do
        ends = if relation == "precedes", do: groups, else: nodes
        assert MapSet.member?(ends, id), "#{inspect(module)}: #{relation} #{from} -> #{to}"
      end

      for group <- graph["groups"], id <- group["nodes"] do
        assert MapSet.member?(nodes, id), "#{inspect(module)}: group #{group["id"]} holds #{id}"
      end
    end
  end

  test "the log is not in a document, even where the contract has run" do
    # The schema closes every object, so a key of the overlay would fail it; this says
    # why, where it is read.
    for {_module, document} <- documents(), graph <- graphs(document) do
      for item <- graph["nodes"] ++ graph["edges"] do
        refute Enum.any?(~w(overlay counts runs), &Map.has_key?(item, &1))
      end
    end
  end

  test "a unit's pictures are keyed by the id of its group on the full graph" do
    for contract <- Registry.contracts() do
      %{"graphs" => g} = Document.contract(contract)
      groups = for %{"kind" => "unit", "id" => id} <- g["contract"]["groups"], do: id
      units = Map.keys(g["units"])

      # A unit with neither commands nor events has no group, and still its picture.
      assert groups -- units == [], inspect(contract)

      assert Map.keys(g["lifecycles"]) -- units == [], inspect(contract)
    end
  end

  test "the digest moves with what is drawn, and not with the order contracts are given in" do
    document = Document.contract(ProcessShapes.Promised)

    relabelled =
      update_in(document, ["graphs", "contract", "nodes"], fn [node | rest] ->
        [%{node | "label" => node["label"] <> "!"} | rest]
      end)

    refute Document.digest(relabelled) == document["digest"]

    contracts = Registry.contracts()

    for domain <- Registry.domains() do
      assert Document.domain(domain, Enum.reverse(contracts)) ==
               Document.domain(domain, contracts)
    end
  end

  describe "the declared shape of a process" do
    test "its stages are groups in their order, the order an edge between them" do
      graph = Declared.build(ProcessShapes.Promised, :handling)
      stage = &Document.id([:stage, ProcessShapes.Promised, :handling, &1])
      model = Model.fetch(ProcessShapes.Promised)

      assert Enum.map(graph.groups, & &1.name) == Enum.map(model.process.stages, & &1.name)

      assert %{from: from, to: to, relation: :precedes} =
               Enum.find(graph.edges, &(&1.relation == :precedes))

      assert {from, to} == {stage.(:intake), stage.(:decision)}

      intake = Enum.find(graph.groups, &(&1.name == :intake))
      assert Document.id([:event, ProcessShapes.Promised, :request_received]) in intake.nodes
    end

    test "a promise is an edge with its window, and its or_else another" do
      graph = Declared.build(ProcessShapes.Promised, :handling)
      event = &Document.id([:event, ProcessShapes.Promised, &1])

      assert %{within: %{amount: 2, unit: :day}, promise: promise} =
               Enum.find(graph.edges, &(&1.relation == :eventually))

      assert Enum.find(graph.edges, &(&1.relation == :eventually)).to ==
               event.(:request_completed)

      assert %{from: from, to: to, promise: ^promise} =
               Enum.find(graph.edges, &(&1.relation == :or_else))

      assert {from, to} == {event.(:request_received), event.(:refusal_notified)}

      terminal = for %{kind: :event, terminal: true} = e <- graph.nodes, do: e.name
      assert Enum.sort(terminal) == [:refusal_notified, :request_completed]
    end

    test "an included event has the id it has on the contract's full graph" do
      declared = Declared.build(DispatchRig.Branch, :branch)
      full = Contract.build(DispatchRig.Branch)
      id = Document.id([:event, DispatchRig.Branch, :account_opened])

      assert Enum.any?(declared.nodes, &(&1.id == id))
      assert Enum.any?(full.nodes, &(&1.id == id))
    end

    test "an event's dependency is an edge to the domain's external" do
      graph = Declared.build(UniversalityGate.TreatmentEpisode, :treatment_episode)
      model = Model.fetch(UniversalityGate.TreatmentEpisode)
      external = Document.id([:external, model.domain, :payer_registry])

      assert %{label: "Payer registry: confirmation of eligibility for treatment"} =
               Enum.find(graph.nodes, &(&1.id == external))

      assert Enum.any?(graph.edges, &(&1.relation == :depends_on and &1.to == external))
    end

    test "a process the contract does not declare is refused" do
      assert_raise ArgumentError, ~r/declares no process :nope/, fn ->
        Declared.build(ProcessShapes.Promised, :nope)
      end
    end
  end
end
