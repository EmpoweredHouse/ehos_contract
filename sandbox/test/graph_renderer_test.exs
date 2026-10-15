defmodule EhOsContract.GraphRendererTest do
  @moduledoc """
  Plan E13b, batch 1: the renderer of `eh_os_contract_graph` draws every document of
  the client trees as the engine gives it today, with the overlay the engine reads from
  the log over it. The renderer's own suite runs on fixtures taken once, which do not
  follow these trees as they change; this does, and holds the fixtures to today's schema.
  """

  use Taxvision.DataCase, async: false

  import Phoenix.LiveViewTest

  alias EhOsContract.Graph.{Document, Overlay}
  alias EhOsContract.GraphRenderer.{Canvas, Lookup, Panel, View}
  alias EhOsContract.Registry

  @schema Document.schema_path() |> File.read!() |> Jason.decode!() |> JSV.build!()
  @fixtures Path.expand("../../packages/eh_os_contract_graph/test/fixtures", __DIR__)

  # Every contract's, every process module's (plan DD, P2e, #220) and every domain's, with
  # its process modules, as the dashboard draws them.
  defp documents do
    contracts = Registry.contracts()
    processes = Registry.processes()

    for(c <- contracts, do: {inspect(c), Document.contract(c)}) ++
      for(p <- processes, do: {inspect(p), Document.process(p)}) ++
      for d <- Registry.domains(), do: {inspect(d), Document.domain(d, contracts ++ processes)}
  end

  defp overlays do
    contracts = Registry.contracts()
    processes = Registry.processes()
    modules = contracts ++ processes

    for(c <- contracts, do: {inspect(c), Document.contract(c), Overlay.contract(c)}) ++
      for(p <- processes, do: {inspect(p), Document.process(p), Overlay.process(p)}) ++
      for d <- Registry.domains(),
          do: {inspect(d), Document.domain(d, modules), Overlay.domain(d, modules)}
  end

  defp draw(document, overlay \\ nil),
    do: render_component(Canvas, id: "graph", document: document, overlay: overlay)

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

  test "the overlay is drawn over every document: a count on each step the log has numbers for" do
    numbered =
      for {name, document, overlay} <- overlays() do
        html = document |> draw(overlay) |> LazyHTML.from_fragment()
        assert Enum.count(LazyHTML.query(html, ".ehg-note")) == 0, name

        # What the overlay gives a number for, by its schema: every entry but a relation
        # several steps end at (`by_trigger`) and an effect's step, whose `taken` is null.
        counted =
          for {id, entry} <- overlay["relations"],
              not Map.has_key?(entry, "by_trigger"),
              not (Map.has_key?(entry, "taken") and entry["taken"] == nil),
              do: id

        drawn =
          html
          |> LazyHTML.query("[data-ehg-relation]:has(.ehg-count)")
          |> LazyHTML.attribute("data-ehg-relation")

        assert Enum.sort(drawn) == Enum.sort(counted), name
        length(counted)
      end

    assert Enum.sum(numbered) > 0
  end

  # Plan E13b, batch 4: the panels read the document by joins alone, so a shape a client
  # wrote and no fixture has shows here first.
  test "every element of every view has a panel, with the log, naming only what can be selected" do
    for {name, document, overlay} <- overlays(),
        lookup = Lookup.new(document),
        {spec, _title} <- [{:all, nil} | View.views(document)],
        view = View.build(document, spec, overlay),
        picked <-
          Enum.map(view.nodes, &{:node, &1}) ++
            Enum.map(view.groups, &{:group, &1}) ++ Enum.map(view.relations, &{:relation, &1}) do
      where = "#{name} #{inspect(spec)} #{elem(picked, 1).id}"

      html =
        render_component(&Panel.panel/1,
          picked: picked,
          lookup: lookup,
          overlay: overlay,
          target: "#graph"
        )
        |> LazyHTML.from_fragment()

      assert Enum.count(LazyHTML.query(html, "aside.ehg-panel")) == 1, where

      # A name the document does not hold is shown as text, not as a button.
      assert Enum.empty?(LazyHTML.query(html, "span.ehg-ref")),
             "#{where} names #{html |> LazyHTML.query("span.ehg-ref") |> LazyHTML.text()}"

      for id <- html |> LazyHTML.query("button.ehg-ref") |> LazyHTML.attribute("phx-value-id"),
          do: assert(Lookup.kind(lookup, id), "#{where} names #{id}")
    end
  end

  test "the renderer's fixtures taken from the client trees still hold to the schema" do
    # edge_cases.json and messaging.json are made by hand for what no client wrote, and are not
    # whole documents. domain.ledger.json is made by hand too, for joining applications, but is
    # whole, so it holds to the schema as the taken ones do.
    names = @fixtures |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".json"))
    taken = names -- ["edge_cases.json", "messaging.json"]
    assert length(taken) == 9

    for name <- taken do
      document = @fixtures |> Path.join(name) |> File.read!() |> Jason.decode!()
      assert {:ok, _} = JSV.validate(document, @schema), name
    end
  end
end
