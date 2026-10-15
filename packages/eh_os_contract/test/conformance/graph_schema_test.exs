defmodule EhOsContract.GraphSchemaTest do
  @moduledoc """
  Plan DD, G1 (#297), the user's decision of 15 October: a `graph.v1` document and its
  overlay change only by addition, so a reader on an older version of the library — the
  EHOS Console reading applications on several — keeps reading what it knows. Each
  shipped schema is held to its baseline under `test/fixtures/schema/`: every definition,
  every key it describes, every key it requires, every alternative of a `oneOf` and
  every fixed value is still there. A description may be reworded. A change that removes
  or renames anything is breaking: it gets a `**Breaking:**` line in the changelog and
  replaces the baseline with the schema it ships.
  """

  use ExUnit.Case, async: true

  @schemas Path.expand("../../priv/schema", __DIR__)
  @baselines Path.expand("../fixtures/schema", __DIR__)

  # What words may change without a reader noticing.
  @prose ~w(description title $comment)

  for name <- ["graph.v1", "graph_overlay.v1"] do
    test "#{name} only adds to its baseline" do
      baseline = read(Path.join(@baselines, "#{unquote(name)}.baseline.json"))
      current = read(Path.join(@schemas, "#{unquote(name)}.json"))

      assert removed(baseline, current, []) == []
    end
  end

  test "a schema that drops a key, a required key or an alternative fails it" do
    baseline = %{
      "$defs" => %{
        "node" => %{
          "required" => ["id"],
          "properties" => %{"id" => %{"type" => "string"}, "label" => %{"type" => "string"}},
          "oneOf" => [%{"$ref" => "#/$defs/a"}, %{"$ref" => "#/$defs/b"}]
        }
      }
    }

    dropped = update_in(baseline, ["$defs", "node", "properties"], &Map.delete(&1, "label"))
    unrequired = put_in(baseline, ["$defs", "node", "required"], [])
    narrowed = put_in(baseline, ["$defs", "node", "oneOf"], [%{"$ref" => "#/$defs/a"}])
    retyped = put_in(baseline, ["$defs", "node", "properties", "id", "type"], "integer")
    reworded = put_in(baseline, ["$defs", "node", "description"], "A node, said otherwise.")

    added =
      put_in(baseline, ["$defs", "node", "properties", "declared_in"], %{"type" => "string"})

    for changed <- [dropped, unrequired, narrowed, retyped],
        do: refute(removed(baseline, changed, []) == [])

    assert removed(baseline, reworded, []) == []
    assert removed(baseline, added, []) == []
  end

  test "a property named like prose is a property, an alternative may grow, a type list may not" do
    baseline = %{
      "$defs" => %{
        "scenario" => %{
          "properties" => %{"description" => %{"type" => "string"}},
          "oneOf" => [%{"properties" => %{"a" => %{"type" => ["integer"]}}}]
        }
      }
    }

    no_description =
      update_in(baseline, ["$defs", "scenario", "properties"], &Map.delete(&1, "description"))

    grown =
      put_in(baseline, ["$defs", "scenario", "oneOf"], [
        %{"properties" => %{"a" => %{"type" => ["integer"]}, "b" => %{"type" => "string"}}}
      ])

    widened =
      put_in(baseline, ["$defs", "scenario", "oneOf"], [
        %{"properties" => %{"a" => %{"type" => ["integer", "null"]}}}
      ])

    refute removed(baseline, no_description, []) == []
    assert removed(baseline, grown, []) == []
    refute removed(baseline, widened, []) == []
  end

  defp read(path), do: path |> File.read!() |> JSON.decode!()

  # The paths at which `old` has something `new` lacks. Under `properties` a key is a
  # property's name, so `description` there is a property, not prose.
  defp removed(old, new, at) when is_map(old) and is_map(new) do
    prose = if List.last(at) == "properties", do: [], else: @prose

    for {key, value} <- old, key not in prose, reduce: [] do
      acc ->
        case Map.fetch(new, key) do
          {:ok, now} -> acc ++ removed(value, now, at ++ [key])
          :error -> acc ++ [at ++ [key]]
        end
    end
  end

  # A `type` list is what a reader may meet, so it stays as it was: a widened one hands an
  # older reader a value it never expected.
  defp removed(old, new, at) when is_list(old) and is_list(new) do
    case List.last(at) do
      "type" -> if Enum.sort(old) == Enum.sort(new), do: [], else: [at]
      _names_or_alternatives -> kept(old, new, at)
    end
  end

  defp removed(same, same, _at), do: []
  defp removed(_old, _new, at), do: [at]

  # A list of names (`required`, `enum`) keeps every name; a list of alternatives (`oneOf`,
  # `anyOf`) keeps every alternative, though one may grow as any schema may.
  defp kept(old, new, at) do
    for item <- old,
        not Enum.any?(new, &(removed(item, &1, at) == [])),
        do: at ++ [inspect(item)]
  end
end
