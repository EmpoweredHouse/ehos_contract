defmodule EhOsContract.GraphRendererTest do
  @moduledoc """
  Plan E13b, batch 1: the renderer of `eh_os_contract_graph` draws every document of
  the client trees as the engine gives it today. The renderer's own suite runs on
  fixtures taken once and does not follow these trees as they change; this does.
  """

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias EhOsContract.Graph.Document
  alias EhOsContract.GraphRenderer.Canvas
  alias EhOsContract.Registry

  defp documents do
    contracts = Registry.contracts()

    for(c <- contracts, do: {inspect(c), Document.contract(c)}) ++
      for d <- Registry.domains(), do: {inspect(d), Document.domain(d, contracts)}
  end

  defp draw(document), do: render_component(Canvas, id: "graph", document: document)

  defp all(document, group),
    do: for({_kind, list} <- document[group], element <- list, do: element["id"])

  test "a card for every node and a label for every relation, and nothing with a style" do
    for {name, document} <- documents() do
      html = document |> draw() |> LazyHTML.from_fragment()

      drawn = fn selector, attribute ->
        html |> LazyHTML.query(selector) |> LazyHTML.attribute(attribute) |> Enum.sort()
      end

      assert drawn.("[data-ehg-node]", "data-ehg-node") == Enum.sort(all(document, "nodes")), name

      assert drawn.("[data-ehg-relation]", "data-ehg-relation") ==
               Enum.sort(all(document, "relations")),
             name

      assert Enum.count(LazyHTML.query(html, "[style]")) == 0, name
    end
  end

  test "the document decoded from the API's JSON is drawn the same as the function's" do
    for {name, document} <- documents() do
      decoded = document |> Document.encode() |> Jason.decode!()
      assert draw(decoded) == draw(document), name
    end
  end
end
