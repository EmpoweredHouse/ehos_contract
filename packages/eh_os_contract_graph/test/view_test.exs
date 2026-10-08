defmodule EhOsContract.GraphRenderer.ViewTest do
  use ExUnit.Case, async: true

  alias EhOsContract.GraphRenderer.{Fixtures, View}

  test "all/1 keeps every node of every fixture, each with the kind of its group" do
    for name <- Fixtures.names() do
      document = Fixtures.document(name)
      view = View.all(document)

      assert Enum.map(view.nodes, & &1.id) |> Enum.sort() ==
               Fixtures.nodes(document) |> Enum.map(& &1["id"]) |> Enum.sort(),
             name

      for node <- view.nodes,
          do: assert(node.facts in document["nodes"][node.kind], "#{name}: #{node.id}")
    end
  end

  test "all/1 keeps every relation whose two ends are nodes, and only those" do
    for name <- Fixtures.names() do
      document = Fixtures.document(name)
      ids = MapSet.new(Fixtures.nodes(document), & &1["id"])
      view = View.all(document)

      expected =
        for r <- Fixtures.relations(document),
            r["from"] in ids and r["to"] in ids,
            do: r["id"]

      assert Enum.sort(Enum.map(view.relations, & &1.id)) == Enum.sort(expected), name
    end

    relations = View.all(Fixtures.document("edge_cases")).relations
    refute Enum.any?(relations, &(&1.id == "handled_by:dangling"))
  end

  test "all/1 takes kinds and types in name order, whatever order the map holds them in" do
    # A map of more than 32 keys is a hash map, whose order is not its keys': forty kinds of
    # one node each, and as many types of one relation, make the document's maps that large.
    many = for i <- 1..40, do: "kind_#{String.pad_leading("#{i}", 2, "0")}"
    nodes = Map.new(many, &{&1, [%{"id" => &1, "name" => &1, "label" => nil}]})

    relations =
      Map.new(many, &{"type_" <> &1, [%{"id" => "r_" <> &1, "from" => &1, "to" => "kind_01"}]})

    refute Map.keys(nodes) == Enum.sort(Map.keys(nodes))

    view = View.all(%{"nodes" => nodes, "relations" => relations})
    assert Enum.map(view.nodes, & &1.kind) == Enum.sort(many)
    assert Enum.map(view.relations, & &1.type) == Enum.sort(Map.keys(relations))
  end

  test "all/1 keeps each group in the document's order" do
    document = Fixtures.document("rehmed.settlement")
    commands = for %{kind: "command"} = node <- View.all(document).nodes, do: node.id

    assert commands == Enum.map(document["nodes"]["command"], & &1["id"])
  end

  test "with_observed/2 adds the moves the overlay saw and the document does not declare" do
    document = Fixtures.document("edge_cases")

    overlay = %{
      "observed" => %{
        "relations" => %{
          "undeclared" => [
            %{
              "id" => "undeclared:closed:open",
              "from" => "status:edge_cases:1st:closed",
              "to" => "status:edge_cases:1st:open",
              "event" => "event:edge_cases:zażółć gęślą jaźń"
            },
            %{
              "id" => "undeclared:nowhere",
              "from" => "status:gone",
              "to" => "status:edge_cases:1st:open"
            }
          ]
        }
      }
    }

    view = document |> View.all() |> View.with_observed(overlay)
    added = Enum.filter(view.relations, &(&1.type == "undeclared"))

    assert Enum.map(added, & &1.id) == ["undeclared:closed:open"]
    assert View.with_observed(View.all(document), nil) == View.all(document)
  end
end
