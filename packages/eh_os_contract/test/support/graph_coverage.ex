defmodule EhOsContract.GraphCoverage do
  @moduledoc """
  Plan E13a, batch 3: is everything today's pictures draw in the graph of facts? Each
  of the six pictures (`EhOsContract.Graph.Contract`, `Declared`, `Unit`, `Lifecycle`,
  `ContextMap`, `System`) is a view the renderer will build from the document in
  E13b; this says, for every node and edge of a picture, which fact it is, and lists
  those the document lacks. What is drawing only — a lifecycle's start — is skipped,
  and so is `gives`, which a field's `issued_by` carries from batch 4 on.

  It goes with the pictures, in E13b.
  """

  alias EhOsContract.Graph.{ContextMap, Contract, Declared, Document, Lifecycle, System, Unit}
  alias EhOsContract.Model

  @doc """
  What every picture of `contract` draws that its document lacks — `document`, or the
  one the engine gives.
  """
  @spec contract(module(), map() | nil) :: [String.t()]
  def contract(contract, document \\ nil) do
    model = Model.fetch(contract)
    facts = facts(document || Document.contract(model))
    c = model.module

    pictures =
      [{Contract.build(model), %{}}] ++
        if(model.process, do: [{Declared.build(model, model.process.name), %{}}], else: []) ++
        for(u <- model.units, do: {Unit.build(model, u.name), %{unit: u.name}}) ++
        for u <- model.units,
            EhOsContract.Lifecycle.of(u),
            do: {Lifecycle.build(model, u.name), %{unit: u.name}}

    Enum.flat_map(pictures, fn {picture, ctx} ->
      missing(picture, Map.merge(ctx, %{contract: c, model: model}), facts)
    end)
  end

  @doc """
  What the context map and the system of `domain` draw that its document lacks —
  `document`, or the one the engine gives.
  """
  @spec domain(module(), [module()], map() | nil) :: [String.t()]
  def domain(domain, contracts, document \\ nil) do
    facts = facts(document || Document.domain(domain, contracts))

    Enum.flat_map([ContextMap.build(domain), System.build(domain, contracts)], fn picture ->
      missing(picture, %{}, facts)
    end)
  end

  defp facts(document) do
    nodes = for {kind, ns} <- document["nodes"], n <- ns, do: {n["id"], Map.put(n, "kind", kind)}

    relations =
      for {type, rs} <- document["relations"], r <- rs, do: Map.put(r, "type", type)

    stages = for n <- get_in(document, ["nodes", "stage"]) || [], do: n["id"]
    %{nodes: Map.new(nodes), relations: relations, stages: stages}
  end

  defp missing(picture, ctx, facts) do
    ids = Map.new(picture.nodes, &{&1.id, fact_id(&1, ctx, facts)})

    nodes =
      for {drawn, id} <- ids,
          id != :drawing,
          not Map.has_key?(facts.nodes, id),
          do: "node #{drawn} (as #{id})"

    # A group is its node, and each of its members names it in the owner field of the
    # group's kind: a unit's commands and events their `unit`, a stage's events their
    # `stage`.
    groups =
      for g <- Map.get(picture, :groups, []),
          problem <-
            if(Map.has_key?(facts.nodes, g.id),
              do:
                for(
                  member <- g.nodes,
                  facts.nodes[ids[member]][to_string(g.kind)] != g.id,
                  do: "#{member} not in #{g.kind} #{g.id}"
                ),
              else: ["group #{g.id}"]
            ),
          do: problem

    edges =
      for e <- picture.edges,
          e.relation not in [:gives, :undeclared],
          not edge?(e, ids, ctx, facts),
          do: "edge #{e.relation} #{e.from} -> #{e.to}"

    nodes ++ groups ++ edges
  end

  # The fact a picture's node is: the same id, but for what batch 3 renamed or what is
  # drawing only.
  defp fact_id(%{kind: :start}, _ctx, _facts), do: :drawing

  defp fact_id(%{kind: :state, name: unit}, ctx, _facts),
    do: Document.id([:unit, ctx.contract, unit])

  defp fact_id(%{kind: :invariant, name: name}, ctx, _facts),
    do: Document.id([:invariant, ctx.contract, :unit, ctx.unit, name])

  defp fact_id(%{kind: :constraint, name: name, command: command}, ctx, _facts),
    do: Document.id([:constraint, ctx.contract, :command, command, name])

  defp fact_id(%{kind: :timer, name: name}, _ctx, facts) do
    Enum.find_value(facts.nodes, "timer #{name} not found", fn {id, n} ->
      n["kind"] == "timer" and n["name"] == to_string(name) and id
    end)
  end

  defp fact_id(node, _ctx, _facts), do: node.id

  # Stages are in the process's order in the document, so one precedes another by place.
  defp edge?(%{relation: :precedes} = e, _ids, _ctx, facts) do
    at = &Enum.find_index(facts.stages, fn id -> id == &1 end)
    at.(e.from) != nil and at.(e.to) != nil and at.(e.from) < at.(e.to)
  end

  defp edge?(%{relation: :transition, from: from} = e, ids, ctx, facts) do
    event = Document.id([:event, ctx.contract, e.event])

    case ids[from] do
      :drawing -> has?(facts, "enters", event, ids[e.to])
      status -> has?(facts, "transition", status, ids[e.to], %{"event" => event})
    end
  end

  defp edge?(%{relation: relation} = e, ids, ctx, facts)
       when relation in [:eventually, :or_else] do
    promise = Document.id([:promise, ctx.contract, ctx.model.process.name, e.promise])
    to = if relation == :eventually, do: "fulfils", else: "or_else"
    has?(facts, "opens", ids[e.from], promise) and has?(facts, to, ids[e.to], promise)
  end

  defp edge?(e, ids, _ctx, facts) do
    from = Map.get(ids, e.from, e.from)
    to = Map.get(ids, e.to, e.to)
    Enum.any?(types(e, facts.nodes[from]), &has?(facts, &1, from, to))
  end

  # The types a picture's relation may be in the facts.
  defp types(%{relation: :handled_by}, _from), do: ~w(handled_by starts ends)
  defp types(%{relation: :issues}, %{"kind" => "actor"}), do: ~w(may_issue)
  defp types(%{relation: :records}, _from), do: ~w(may_record)
  defp types(%{relation: :asks}, _from), do: ~w(may_ask)
  defp types(%{relation: :sets_timer}, _from), do: ~w(sets)
  defp types(%{relation: relation}, _from), do: [to_string(relation)]

  defp has?(facts, type, from, to, attrs \\ %{}) do
    Enum.any?(facts.relations, fn r ->
      r["type"] == type and r["from"] == from and r["to"] == to and
        Enum.all?(attrs, fn {k, v} -> r[k] == v end)
    end)
  end
end
