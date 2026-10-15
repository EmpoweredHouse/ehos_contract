defmodule EhOsContract.GraphRenderer.LandscapeTest do
  # Joining applications by the names on the wire: plan DD, stage G1 (#297). TaxVision's
  # domain publishes the accounting month's opening; domain.ledger.json, hand-made, subscribes
  # to it and to a name nobody in the set publishes.
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias EhOsContract.GraphRenderer.{Canvas, Fixtures, Landscape, Lookup, Panel, View}

  @opened "publication:taxvision.accounting_month.opened.v1"
  @month "taxvision/contract:taxvision.accounting_month"
  @bookkeeping "ledger/contract:ledger.bookkeeping"

  defp landscape,
    do:
      Landscape.join([
        {"taxvision", Fixtures.document("domain.taxvision")},
        {"ledger", Fixtures.document("domain.ledger")}
      ])

  defp ids(list), do: list |> Enum.map(& &1.id) |> Enum.sort()

  test "joins a publication and its subscriber across applications into one card with an arrow on each side" do
    view = View.build(landscape(), :landscape)

    assert [publishes] = Enum.filter(view.relations, &(&1.to == @opened))
    assert publishes.from == @month
    assert publishes.words == "publishes accounting_month_opened"

    assert [subscribed] = Enum.filter(view.relations, &(&1.from == @opened))
    assert subscribed.to == @bookkeeping
    assert subscribed.words == "as month_opened"

    assert [_one] = Enum.filter(view.nodes, &(&1.id == @opened))
  end

  test "draws a box per domain with only the contracts on the wire, and says how many it leaves out" do
    view = View.build(landscape(), :landscape)

    assert ids(view.nodes) ==
             Enum.sort([
               @month,
               @bookkeeping,
               @opened,
               "publication:ledger.month.booked.v1",
               "publication:payroll.run.closed.v1"
             ])

    titles = Map.new(view.groups, &{&1.id, &1.title})

    assert titles["taxvision/domain:Taxvision.Domain"] ==
             "taxvision · taxvision · 2 more contracts"

    assert titles["ledger/domain:Ledger.Domain"] == "ledger · ledger · 1 more contract"

    month = Enum.find(view.nodes, &(&1.id == @month))
    assert {month.group, month.label} == {"taxvision/domain:Taxvision.Domain", "AccountingMonth"}
  end

  test "says a name nobody in the set publishes comes from outside it, and no other" do
    tags = Map.new(View.build(landscape(), :landscape).nodes, &{&1.id, &1.tag})

    assert tags["publication:payroll.run.closed.v1"] == "publication · from outside the set"
    assert tags[@opened] == "publication"
    assert tags["publication:ledger.month.booked.v1"] == "publication"
  end

  test "joins two domains of one application as it joins two applications" do
    joined =
      Landscape.join([
        {"one", Fixtures.document("domain.taxvision")},
        {"one", Fixtures.document("domain.ledger")}
      ])

    view = View.build(joined, :landscape)

    assert [%{from: "one/contract:taxvision.accounting_month"}] =
             Enum.filter(view.relations, &(&1.to == @opened))

    assert length(view.groups) == 2
  end

  test "keeps contracts of the same id in two applications apart" do
    taxvision = Fixtures.document("domain.taxvision")
    view = View.build(Landscape.join([{"a", taxvision}, {"b", taxvision}]), :landscape)

    assert "a/contract:taxvision.accounting_month" in ids(view.nodes)
    assert "b/contract:taxvision.accounting_month" in ids(view.nodes)
    assert length(Enum.filter(view.relations, &(&1.to == @opened))) == 2
  end

  test "a domain on its own is a landscape too, its publication with nobody to take it" do
    view =
      View.build(
        Landscape.join([{"taxvision", Fixtures.document("domain.taxvision")}]),
        :landscape
      )

    assert ids(view.nodes) == Enum.sort([@month, @opened])
    assert [%{type: "publishes"}] = view.relations
  end

  test "refuses a document that is not a domain's" do
    assert_raise ArgumentError, ~r/joins domain documents, got "contract"/, fn ->
      Landscape.join([{"rehmed", Fixtures.document("rehmed.settlement")}])
    end
  end

  test "is the one view of a landscape, which no other view draws" do
    assert View.views(landscape()) == [{:landscape, "Landscape"}]
    assert View.build(Fixtures.document("domain.taxvision"), :landscape).nodes == []
  end

  test "every element has a panel, naming only what the landscape holds" do
    document = landscape()
    lookup = Lookup.new(document)
    view = View.build(document, :landscape)

    for picked <-
          Enum.map(view.nodes, &{:node, &1}) ++
            Enum.map(view.groups, &{:group, &1}) ++ Enum.map(view.relations, &{:relation, &1}) do
      html =
        render_component(&Panel.panel/1, picked: picked, lookup: lookup, target: "#graph")
        |> LazyHTML.from_fragment()

      where = elem(picked, 1).id
      assert Enum.count(LazyHTML.query(html, "aside.ehg-panel")) == 1, where
      assert html |> LazyHTML.query("span.ehg-ref") |> Enum.to_list() == [], where
    end
  end

  test "the canvas draws it, the publication's card between the two boxes" do
    html =
      render_component(Canvas, id: "landscape", document: landscape(), view: :landscape)
      |> LazyHTML.from_fragment()

    assert Enum.count(LazyHTML.query(html, ~s([data-ehg-node="#{@opened}"]))) == 1
    assert Enum.count(LazyHTML.query(html, "[data-ehg-group]")) == 2
    assert Enum.count(LazyHTML.query(html, "[style]")) == 0
  end
end
