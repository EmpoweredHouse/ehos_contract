defmodule EhOsContract.Graph.Contract do
  @moduledoc """
  A v2 contract's full graph (plan EG1): the steps of `EhOsContract.Paths` —
  commands, the events they emit, the policies, process managers and effects that
  react, and timers — and around them who acts and who reads. The actors issuing
  its commands, recording its events and asking its queries; its read models, with
  the events they project and the queries over them; and the domain's external
  systems it touches: an effect's `calls`, an event's `depends_on`, a system actor's
  `backed_by`, a field an external `issued_by`. Each unit's commands and events sit
  in a group of the unit's own.

  `overlay: true` lays the log over the steps, as the graph of steps did (plan
  E7c-2): on each event how often it occurred, on each step how often it was taken,
  and what waits or fails there. Occurrences, not runs, since plan DD, P1a (#183): a
  step is the contract's, whether or not it has a process.
  The counts sit on the edge that is the step's own — the emit, or the consumer's
  command — since an event may reach one consumer that issues two commands.
  `since:` and `until:` bound the log, as in the report. Actors, read models,
  queries and externals carry no counts: nothing in the log is theirs.

  It is one contract's, whether or not it has a process: navigation is per contract
  (ADR §9, amended by plan DD, P1b, #186).
  """

  alias EhOsContract.{Model, Paths}
  alias EhOsContract.Graph.{Document, Mermaid}

  @doc """
  The full graph of `contract` as data: `EhOsContract.Graph.Document.graph()`. Its
  own declarations are scoped to the contract, the actors and externals to the
  domain it names.
  """
  @spec build(module() | map(), keyword()) :: Document.graph()
  def build(contract, opts \\ []) do
    model = Model.fetch(contract)
    domain = domain(model.domain)
    overlay? = Keyword.get(opts, :overlay, false)
    scope = %{contract: model.module, domain: model.domain}

    steps = if overlay?, do: Paths.observe(model, opts), else: Paths.declared(model)

    counts =
      if overlay?,
        do: Map.new(Paths.occurrences(model, opts), fn {name, n} -> {{:event, name}, n} end),
        else: %{}

    actors = Map.new(domain.actors, &{&1.name, &1})
    externals = Map.new(domain.externals, &{&1.name, &1})

    units =
      for unit <- model.units do
        commands =
          for c <- model.commands, c.unit == unit.name, do: graph_node(scope, :command, c)

        events = for e <- model.events, e.unit == unit.name, do: graph_node(scope, :event, e)
        {unit, commands ++ events}
      end

    reactions =
      for step <- steps,
          ref <- [step.from, step.via, step.to],
          ref != nil,
          do: graph_node(scope, ref.kind, ref)

    included =
      for %{included: true} = e <- Model.process_events(model),
          do: graph_node(scope, :event, %{e.declaration | name: e.name})

    {read_nodes, read_edges} = read_side(model, scope)
    {actor_nodes, actor_edges} = actors(model, scope, actors)
    {external_nodes, external_edges} = externals(model, scope, domain, actors, externals)

    nodes =
      (Enum.flat_map(units, &elem(&1, 1)) ++
         reactions ++ included ++ read_nodes ++ actor_nodes ++ external_nodes)
      |> Enum.uniq_by(& &1.id)
      |> Enum.map(&with_counts(&1, Map.get(counts, {&1.kind, &1.name})))

    edges =
      (Enum.flat_map(steps, &step_edges(&1, scope, overlay?)) ++
         actor_edges ++ read_edges ++ external_edges)
      |> Enum.uniq()

    groups =
      for {unit, members} <- units, members != [] do
        %{
          id: Document.id([:unit, model.module, unit.name]),
          kind: :unit,
          name: unit.name,
          label: unit.label,
          unit_kind: unit.kind,
          nodes: Enum.map(members, & &1.id)
        }
      end

    %{nodes: nodes, edges: edges, groups: groups}
  end

  @doc "The full graph of `contract` as a Mermaid flowchart; `opts` as `build/2`."
  @spec to_mermaid(module() | map(), keyword()) :: String.t()
  def to_mermaid(contract, opts \\ []), do: contract |> build(opts) |> Mermaid.render("LR")

  # A contract may name a domain that does not exist (v2 §8): its actors and externals
  # are then drawn by name, with nothing to label them.
  defp domain(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__eh_os_contract_model__, 0),
      do: Model.fetch(module),
      else: %{actors: [], externals: [], entities: []}
  end

  # --- nodes ---------------------------------------------------------------------------

  defp graph_node(scope, kind, %{name: name, label: label}),
    do: Document.graph_node(kind, scope_of(scope, kind), name, label)

  defp graph_node(scope, kind, name, label),
    do: Document.graph_node(kind, scope_of(scope, kind), name, label)

  defp with_counts(node, nil), do: node
  defp with_counts(node, counts), do: Map.put(node, :counts, counts)

  # An actor and an external system are the domain's; everything else on this graph is
  # the contract's, an event it consumes included, under the name it has here.
  defp scope_of(scope, kind) when kind in [:actor, :external], do: scope.domain
  defp scope_of(scope, _kind), do: scope.contract

  defp id(scope, kind, name), do: Document.id([kind, scope_of(scope, kind), name])

  # An event of this contract or of the one it consumes it from, with its label.
  defp event_node(model, scope, name) do
    label =
      case Model.declaring(model, name) do
        {_contract, e} -> e.label
        nil -> nil
      end

    graph_node(scope, :event, name, label)
  end

  # --- the steps -----------------------------------------------------------------------

  # A step's own edge carries its counts; an event reaching its consumer is drawn
  # once, however many commands the consumer issues.
  defp step_edges(%{via: nil} = step, scope, overlay?),
    do: [step_edge(scope, step.from, step.to, :emits, step.mode, overlay(step, overlay?))]

  # A timer is the process manager's: it sets it, and the timer issues the command, so
  # the timer's counts do not share an edge with the manager's other reactions.
  # Setting is ownership, not a delivery.
  defp step_edges(%{from: %{kind: :timer}} = step, scope, overlay?) do
    [
      Document.edge(ref_id(scope, step.via), ref_id(scope, step.from), :sets_timer),
      step_edge(scope, step.from, step.to, :fires, :async, overlay(step, overlay?))
    ]
  end

  defp step_edges(%{to: nil} = step, scope, overlay?),
    do: [
      step_edge(scope, step.from, step.via, :handled_by, step.mode, overlay(step, overlay?))
    ]

  defp step_edges(step, scope, overlay?) do
    [
      step_edge(scope, step.from, step.via, :handled_by, step.mode, nil),
      step_edge(scope, step.via, step.to, :issues, step.mode, overlay(step, overlay?))
    ]
  end

  defp ref_id(scope, ref), do: id(scope, ref.kind, ref.name)

  defp step_edge(scope, from, to, relation, mode, overlay) do
    Document.edge(ref_id(scope, from), ref_id(scope, to), relation,
      delivery: mode,
      overlay: overlay
    )
  end

  # The log over a step: how often it was taken, what waits there, and whether
  # anything fails.
  defp overlay(_step, false), do: nil

  defp overlay(step, true) do
    f = step.failing

    %{
      taken: step.taken,
      waiting: Enum.sum(Map.values(step.in_flight)),
      failing: f.commands > 0 or f.effects > 0 or f.subscription != nil
    }
  end

  # --- who acts ------------------------------------------------------------------------

  # The actors that issue a command, record an event or ask a query, and those edges.
  defp actors(model, scope, actors) do
    issue =
      for command <- model.commands, actor <- command.by do
        {actor,
         Document.edge(id(scope, :actor, actor), id(scope, :command, command.name), :issues)}
      end

    record =
      for event <- model.events, actor <- event.recorded_by do
        {actor, Document.edge(id(scope, :actor, actor), id(scope, :event, event.name), :records)}
      end

    ask =
      for query <- model.queries, actor <- List.wrap(query.by) do
        {actor, Document.edge(id(scope, :actor, actor), id(scope, :query, query.name), :asks)}
      end

    pairs = issue ++ record ++ ask

    nodes =
      for name <- pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq(),
          do: graph_node(scope, :actor, name, actors[name] && actors[name].label)

    {nodes, Enum.map(pairs, &elem(&1, 1))}
  end

  # --- who reads -----------------------------------------------------------------------

  # Each read model with the events it projects, in the transaction or after it, and
  # each query with what it reads.
  defp read_side(model, scope) do
    projected =
      for rm <- model.read_models, event <- List.wrap(rm.projects) do
        {event_node(model, scope, event),
         Document.edge(id(scope, :event, event), id(scope, :read_model, rm.name), :projected_into,
           delivery: if(rm.delivery == :in_transaction, do: :inline, else: :async)
         )}
      end

    queries =
      for q <- model.queries do
        {graph_node(scope, :query, q),
         Document.edge(id(scope, :query, q.name), id(scope, :read_model, q.reads), :reads)}
      end

    nodes =
      Enum.map(projected, &elem(&1, 0)) ++
        Enum.map(model.read_models, &graph_node(scope, :read_model, &1)) ++
        Enum.map(queries, &elem(&1, 0))

    {nodes, Enum.map(projected ++ queries, &elem(&1, 1))}
  end

  # --- the outside world ---------------------------------------------------------------

  # The domain's externals this contract touches: what an effect calls, what an event
  # rests on, what backs a system actor, and what gives a field its value.
  defp externals(model, scope, domain, actors, externals) do
    calls =
      for effect <- model.effects, external <- List.wrap(effect.calls) do
        {external,
         Document.edge(id(scope, :effect, effect.name), id(scope, :external, external), :calls)}
      end

    depends =
      for event <- model.events, event.depends_on do
        {event.depends_on,
         Document.edge(
           id(scope, :event, event.name),
           id(scope, :external, event.depends_on),
           :depends_on
         )}
      end

    acting =
      model.commands
      |> Enum.flat_map(& &1.by)
      |> Enum.concat(Enum.flat_map(model.events, & &1.recorded_by))
      |> Enum.concat(Enum.flat_map(model.queries, &List.wrap(&1.by)))
      |> Enum.uniq()

    backed =
      for name <- acting,
          actor = actors[name],
          actor && actor.backed_by do
        {actor.backed_by,
         Document.edge(
           id(scope, :actor, name),
           id(scope, :external, actor.backed_by),
           :backed_by
         )}
      end

    issued =
      for {kind, declarations} <- [command: model.commands, event: model.events],
          declaration <- declarations,
          field <- declaration.fields,
          external = issued_by(domain, field),
          external != nil do
        {external,
         Document.edge(id(scope, :external, external), id(scope, kind, declaration.name), :gives,
           field: field.name
         )}
      end

    pairs = calls ++ depends ++ backed ++ issued

    nodes =
      for name <- pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq(),
          do: graph_node(scope, :external, name, externals[name] && externals[name].label)

    {nodes, Enum.map(pairs, &elem(&1, 1))}
  end

  # The external a field names, or the one that issues the identifier of the entity it
  # refers to.
  defp issued_by(domain, field) do
    Map.get(field, :issued_by) ||
      Enum.find_value(domain.entities, fn entity ->
        entity.name == Map.get(field, :refers_to) &&
          Enum.find_value(
            entity.fields,
            &(&1.name == entity.identity && Map.get(&1, :issued_by))
          )
      end)
  end
end
