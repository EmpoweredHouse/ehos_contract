defmodule EhOsContract.GraphViewsTest do
  @moduledoc """
  Plan E13b, batch 3: the renderer's views are the six pictures the engine drew as
  Mermaid diagrams (the user's decision of 8 October). For every contract and domain of
  the client trees, each view of the renderer, built from the `graph.v1` document, holds
  every card, group and arrow the engine's builder of the same picture gives Mermaid —
  `EhOsContract.Graph.Contract`, `Declared`, `Unit`, `Lifecycle`, `ContextMap` and
  `System` — and nothing more but what the facts are finer in: a process manager's
  start and end, and a timer it cancels, which the picture of the steps left out.

  It also holds what the arrows say where the picture said it with a number: a step
  after the transaction, the scenarios on a unit's arrow, a promise's window.

  It goes with the builders, when Mermaid is cut (batch 5).
  """

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias EhOsContract.Graph.{ContextMap, Contract, Declared, Document, Lifecycle, System, Unit}
  alias EhOsContract.GraphRenderer.View
  alias EhOsContract.{Model, Registry}

  # A picture's relation, under the name the view gives the same fact.
  @same %{
    starts: :handled_by,
    ends: :handled_by,
    may_issue: :issues,
    may_record: :records,
    may_ask: :asks,
    sets: :sets_timer,
    promise: :eventually,
    enters: :transition
  }

  defp pictures do
    contracts = Registry.contracts()

    contract_pictures =
      for c <- contracts do
        model = Model.fetch(c)
        document = Document.contract(c)
        process = Model.process(model)
        unit_id = &Document.id([:unit, model.id, &1.name])

        [
          {"#{model.id} full graph", Contract.build(model), View.contract(document), model,
           document}
        ] ++
          if(process,
            do: [
              {"#{model.id} declared shape", drawn(Declared.build(model, process.name)),
               View.declared(document), model, document}
            ],
            else: []
          ) ++
          for(
            u <- model.units,
            do:
              {"#{model.id} unit #{u.name}", Unit.build(model, u.name),
               View.unit(document, unit_id.(u)), model, document}
          ) ++
          for u <- model.units,
              EhOsContract.Lifecycle.of(u),
              do:
                {"#{model.id} lifecycle #{u.name}", Lifecycle.build(model, u.name),
                 View.lifecycle(document, unit_id.(u)), model, document}
      end

    domain_pictures =
      for d <- Registry.domains() do
        document = Document.domain(d, contracts)

        [
          {"#{inspect(d)} context map", ContextMap.build(d), View.context_map(document), nil,
           document},
          {"#{inspect(d)} system", System.build(d, contracts), View.system(document), nil,
           document}
        ]
      end

    List.flatten(contract_pictures ++ domain_pictures)
  end

  # What Mermaid drew of a declared shape: with stages, only the events in a stage.
  defp drawn(%{groups: []} = shape), do: shape

  defp drawn(shape) do
    staged = MapSet.new(Enum.flat_map(shape.groups, & &1.nodes))
    events = MapSet.new(for %{kind: :event} = n <- shape.nodes, do: n.id)
    gone = MapSet.difference(events, staged)
    keep = &(not MapSet.member?(gone, &1))

    %{
      shape
      | nodes: Enum.filter(shape.nodes, &keep.(&1.id)),
        edges: Enum.filter(shape.edges, &(keep.(&1.from) and keep.(&1.to)))
    }
  end

  # The document's id of each of a picture's nodes: the same, but for the cards batch 3 of
  # E13a renamed, a timer named by its manager, and a lifecycle's start, which the view
  # gives the unit's id.
  defp ids(picture, model, document) do
    timers =
      for t <- get_in(document, ["nodes", "timer"]) || [], into: %{}, do: {t["name"], t["id"]}

    Map.new(picture.nodes, fn node ->
      {node.id,
       case node do
         %{kind: :state, name: unit} ->
           Document.id([:unit, model.id, unit])

         %{kind: :start} ->
           String.replace_prefix(node.id, "start:", "unit:")

         %{kind: :timer, name: name} ->
           timers[to_string(name)]

         %{kind: :invariant} ->
           invariant(node, model, picture)

         %{kind: :constraint, command: command} ->
           Document.id([:constraint, model.id, :command, command, node.name])

         _ ->
           node.id
       end}
    end)
  end

  # An invariant of the unit the picture is of: its id ends in the unit's name and its own.
  defp invariant(node, model, picture) do
    %{name: unit} = Enum.find(picture.nodes, &(&1.kind == :state))
    Document.id([:invariant, model.id, :unit, unit, node.name])
  end

  defp edge(e, ids), do: {e.relation, Map.get(ids, e.from, e.from), Map.get(ids, e.to, e.to)}

  defp arrow(r),
    do: {Map.get(@same, String.to_atom(r.type), String.to_atom(r.type)), r.from, r.to}

  test "every view holds its picture's cards, groups and arrows, and adds only the manager's flow" do
    for {name, picture, view, model, document} <- pictures() do
      ids =
        if model, do: ids(picture, model, document), else: Map.new(picture.nodes, &{&1.id, &1.id})

      drawn_nodes = MapSet.new(Map.values(ids))
      view_nodes = MapSet.new(view.nodes, & &1.id)

      assert MapSet.subset?(drawn_nodes, view_nodes),
             "#{name}: missing cards #{inspect(MapSet.difference(drawn_nodes, view_nodes))}"

      groups =
        for g <- Map.get(picture, :groups, []),
            into: %{},
            do: {g.id, Enum.sort(Enum.map(g.nodes, &ids[&1]))}

      view_groups =
        for g <- view.groups,
            into: %{},
            do: {g.id, Enum.sort(for n <- view.nodes, n.group == g.id, do: n.id)}

      assert view_groups == groups, name

      edges = MapSet.new(picture.edges, &edge(&1, ids))
      arrows = MapSet.new(view.relations, &arrow/1)

      assert MapSet.subset?(edges, arrows),
             "#{name}: missing arrows #{inspect(MapSet.difference(edges, arrows))}"

      # What the view draws beyond the picture: the manager's start, end, a reaction to an
      # event during its run that issues nothing, and a timer it cancels — and the events
      # only those reach.
      extra = for r <- view.relations, arrow(r) not in edges, do: r

      for r <- extra do
        assert (r.type in ~w(starts ends handled_by cancels) and
                  String.starts_with?(r.to, "process_manager:")) or
                 String.starts_with?(r.from, "process_manager:"),
               "#{name}: an arrow the picture does not have: #{r.id}"
      end

      reached = MapSet.new(Enum.flat_map(extra, &[&1.from, &1.to]))

      for id <- MapSet.difference(view_nodes, drawn_nodes) do
        assert MapSet.member?(reached, id), "#{name}: a card the picture does not have: #{id}"
      end
    end
  end

  test "an arrow says what its picture said with a number or a line" do
    for {name, picture, view, model, document} <- pictures() do
      ids =
        if model, do: ids(picture, model, document), else: Map.new(picture.nodes, &{&1.id, &1.id})

      arrows = Enum.group_by(view.relations, &arrow/1)

      for e <- picture.edges, r <- Map.get(arrows, edge(e, ids), []) do
        case e do
          %{delivery: :async} ->
            assert r.line == "dotted" and r.words =~ "async",
                   "#{name}: #{r.id} is after the transaction"

          %{relation: relation, scenarios: n}
          when relation in [:emits, :refused_on] and is_integer(n) ->
            assert r.words =~ if(n == 1, do: "1 scenario", else: "#{n} scenarios"),
                   "#{name}: #{r.id}"

          %{relation: :eventually, within: %{amount: amount, unit: unit}} ->
            assert r.words == "within #{EhOsContract.Duration.humanize({amount, unit})}",
                   "#{name}: #{r.id}"

          %{relation: :transition, label: label} ->
            assert r.words == label, "#{name}: #{r.id}"

          _ ->
            :ok
        end
      end

      for r <- view.relations,
          r.type in ~w(emits refused_on),
          not String.contains?(r.words || "", "scenario") do
        refute Enum.any?(
                 picture.edges,
                 &(edge(&1, ids) == arrow(r) and is_integer(Map.get(&1, :scenarios)))
               ),
               "#{name}: #{r.id} has scenarios"
      end
    end
  end

  test "every view of every document is drawn, a card for each of its nodes and nothing with a style" do
    contracts = Registry.contracts()

    documents =
      Enum.map(contracts, &Document.contract/1) ++
        Enum.map(Registry.domains(), &Document.domain(&1, contracts))

    for document <- documents, {spec, title} <- View.views(document) do
      view = View.build(document, spec)

      html =
        render_component(EhOsContract.GraphRenderer.Canvas,
          id: "graph",
          document: document,
          view: spec
        )
        |> LazyHTML.from_fragment()

      drawn = html |> LazyHTML.query("[data-ehg-node]") |> LazyHTML.attribute("data-ehg-node")
      assert drawn == Enum.map(view.nodes, & &1.id), title
      assert view.nodes != [], title
      assert Enum.count(LazyHTML.query(html, "[style]")) == 0, title
    end
  end
end
