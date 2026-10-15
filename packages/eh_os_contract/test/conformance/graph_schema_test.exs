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

  defp read(path), do: path |> File.read!() |> JSON.decode!()

  # The paths at which `old` has something `new` lacks.
  defp removed(old, new, at) when is_map(old) and is_map(new) do
    for {key, value} <- old, key not in @prose, reduce: [] do
      acc ->
        case Map.fetch(new, key) do
          {:ok, now} -> acc ++ removed(value, now, at ++ [key])
          :error -> acc ++ [at ++ [key]]
        end
    end
  end

  # A list of names (`required`, `enum`) keeps every name; a `oneOf` or `anyOf` keeps every
  # alternative, by what it is less its prose.
  defp removed(old, new, at) when is_list(old) and is_list(new) do
    present = MapSet.new(new, &bare/1)
    for item <- old, not MapSet.member?(present, bare(item)), do: at ++ [inspect(bare(item))]
  end

  defp removed(same, same, _at), do: []
  defp removed(_old, _new, at), do: [at]

  defp bare(%{} = map), do: map |> Map.drop(@prose) |> Map.new(fn {k, v} -> {k, bare(v)} end)
  defp bare(other), do: other
end
