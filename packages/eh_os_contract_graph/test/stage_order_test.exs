defmodule EhOsContract.GraphRenderer.StageOrderTest do
  # Plan DD, O2 (#319): a process's stages runs entered the wrong way round, from the
  # overlay's `observed.relations.out_of_order`, drawn as an arrow from the later stage
  # back to the earlier one, with its runs and the error look, and a panel that says it.
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias EhOsContract.GraphRenderer.{Canvas, Fixtures, Lookup, Panel, View}

  @closing "stage:rehmed.clinical_visit:closing"
  @reporting "stage:rehmed.clinical_visit:reporting"
  @id "out_of_order:#{@reporting}:#{@closing}"

  defp overlay do
    Fixtures.overlay("process.rehmed.clinical_visit")
    |> put_in(["observed", "relations", "out_of_order"], [
      %{"id" => @id, "from" => @reporting, "to" => @closing, "runs" => 3}
    ])
  end

  defp document, do: Fixtures.document("process.rehmed.clinical_visit")

  test "draws an arrow from the later stage back to the earlier one" do
    view = View.build(document(), :process, overlay())

    assert [%{id: @id, from: @reporting, to: @closing, words: "entered first", line: "dotted"}] =
             Enum.filter(view.relations, &(&1.type == "out_of_order"))
  end

  test "draws none without an overlay, or with one where every run kept the order" do
    for o <- [nil, Fixtures.overlay("process.rehmed.clinical_visit")] do
      refute Enum.any?(
               View.build(document(), :process, o).relations,
               &(&1.type == "out_of_order")
             )
    end
  end

  test "the canvas gives it the runs and the look of a move the process does not declare" do
    html =
      render_component(Canvas,
        id: "graph",
        document: document(),
        overlay: overlay(),
        view: :process
      )
      |> LazyHTML.from_fragment()

    label = LazyHTML.query(html, ~s(button.ehg-relation[data-ehg-relation="#{@id}"]))
    assert Enum.count(label) == 1
    assert label |> LazyHTML.query(".ehg-count") |> LazyHTML.text() == "×3"

    assert "is-undeclared" in (label
                               |> LazyHTML.attribute("class")
                               |> Enum.flat_map(&String.split/1))
  end

  test "its panel names the two stages and how many runs" do
    view = View.build(document(), :process, overlay())
    relation = Enum.find(view.relations, &(&1.id == @id))

    text =
      render_component(&Panel.panel/1,
        picked: {:relation, relation},
        lookup: Lookup.new(document()),
        target: "#graph"
      )
      |> String.replace(~r/<[^>]*>/, " ")
      |> String.split()
      |> Enum.join(" ")

    assert text =~ "3 runs entered reporting"
    assert text =~ "before closing"
  end
end
