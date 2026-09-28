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
  E7c-2): on each event the occurrences and the runs it happened in, on each step
  the runs that took it out of the process's runs, and what waits or fails there.
  The counts sit on the edge that is the step's own — the emit, or the consumer's
  command — since an event may reach one consumer that issues two commands.
  `since:` and `until:` bound the log, as in the report. Actors, read models,
  queries and externals carry no counts: nothing in the log is theirs.

  It is one contract's, which is one process's: navigation stays per process (ADR
  §9).
  """

  import Ecto.Query

  alias EhOsContract.{Event, EventRun, Model, Paths}
  alias EhOsContract.Graph.Mermaid

  @doc "The full graph of `contract` as data: `EhOsContract.Graph.Mermaid.graph()`."
  @spec build(module() | map(), keyword()) :: Mermaid.graph()
  def build(contract, opts \\ []) do
    model = Model.fetch(contract)
    domain = domain(model.domain)
    overlay? = Keyword.get(opts, :overlay, false)

    steps = if overlay?, do: Paths.observe(model, opts), else: Paths.declared(model)
    counts = if overlay?, do: event_counts(model, opts), else: %{}

    actors = Map.new(domain.actors, &{&1.name, &1})
    externals = Map.new(domain.externals, &{&1.name, &1})

    units =
      for unit <- model.units do
        commands = for c <- model.commands, c.unit == unit.name, do: graph_node(:command, c)
        events = for e <- model.events, e.unit == unit.name, do: graph_node(:event, e)
        {unit, commands ++ events}
      end

    reactions =
      for step <- steps, ref <- [step.from, step.via, step.to], ref != nil, do: graph_node(ref)

    included =
      for include <- (model.process && model.process.includes) || [],
          {_contract, e} <- [Model.declaring(model, include.event)],
          do: graph_node(:event, %{e | name: include.event})

    {read_nodes, read_edges} = read_side(model)
    {actor_nodes, actor_edges} = actors(model, actors)
    {external_nodes, external_edges} = externals(model, domain, actors, externals)

    nodes =
      (Enum.flat_map(units, &elem(&1, 1)) ++
         reactions ++ included ++ read_nodes ++ actor_nodes ++ external_nodes)
      |> Enum.uniq_by(& &1.id)
      |> Enum.map(&Map.put(&1, :counts, Map.get(counts, {&1.kind, &1.name})))

    edges =
      (Enum.flat_map(steps, &step_edges(&1, overlay?)) ++
         actor_edges ++ read_edges ++ external_edges)
      |> Enum.uniq()

    groups =
      for {unit, members} <- units, members != [] do
        %{id: "unit_#{unit.name}", label: "#{unit.label} · #{unit.kind}", nodes: ids(members)}
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

  defp graph_node(%{kind: kind, name: name, label: label}), do: graph_node(kind, name, label)
  defp graph_node(kind, %{name: name, label: label}), do: graph_node(kind, name, label)
  defp graph_node(kind, name, label), do: Mermaid.graph_node(kind, name, label)

  defp id(kind, name), do: Mermaid.id(kind, name)
  defp ids(nodes), do: Enum.map(nodes, & &1.id)

  # An event of this contract or of the one it consumes it from, with its label.
  defp event_node(model, name) do
    label =
      case Model.declaring(model, name) do
        {_contract, e} -> e.label
        nil -> nil
      end

    graph_node(:event, name, label)
  end

  # --- the steps -----------------------------------------------------------------------

  # A step's own edge carries its counts; an event reaching its consumer is drawn
  # once, however many commands the consumer issues.
  defp step_edges(%{via: nil} = step, overlay?),
    do: [edge(step.from, step.to, :inline, label(step, overlay?))]

  # A timer is the process manager's: it sets it, and the timer issues the command, so
  # the timer's counts do not share an edge with the manager's other reactions.
  # Setting is ownership, not a delivery, so it is a plain line saying so.
  defp step_edges(%{from: %{kind: :timer}} = step, overlay?) do
    [
      Mermaid.edge(ref_id(step.via), ref_id(step.from),
        line: :dotted,
        head: false,
        label: "sets"
      ),
      edge(step.from, step.to, :async, label(step, overlay?))
    ]
  end

  defp step_edges(%{to: nil} = step, overlay?),
    do: [edge(step.from, step.via, step.mode, label(step, overlay?))]

  defp step_edges(step, overlay?) do
    [
      edge(step.from, step.via, step.mode, nil),
      edge(step.via, step.to, step.mode, label(step, overlay?))
    ]
  end

  defp ref_id(ref), do: id(ref.kind, ref.name)

  defp edge(from, to, mode, label) do
    label =
      if mode == :async,
        do: Enum.join(Enum.reject(["async", label], &is_nil/1), " · "),
        else: label

    Mermaid.edge(ref_id(from), ref_id(to),
      line: if(mode == :async, do: :dotted, else: :solid),
      label: label
    )
  end

  defp label(_step, false), do: nil

  defp label(step, true) do
    taken = if step.runs, do: "#{step.runs}/#{step.of_runs} runs", else: "runs unknown"
    waiting = Enum.sum(Map.values(step.in_flight))
    f = step.failing
    failing? = f.commands > 0 or f.effects > 0 or f.subscription != nil

    [taken, waiting > 0 && "#{waiting} waiting", failing? && "failing"]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  # --- who acts ------------------------------------------------------------------------

  # The actors that issue a command, record an event or ask a query, and those edges.
  defp actors(model, actors) do
    issue =
      for command <- model.commands, actor <- command.by do
        {actor, Mermaid.edge(id(:actor, actor), id(:command, command.name))}
      end

    record =
      for event <- model.events, actor <- event.recorded_by do
        {actor, Mermaid.edge(id(:actor, actor), id(:event, event.name), label: "records")}
      end

    ask =
      for query <- model.queries, actor <- List.wrap(query.by) do
        {actor, Mermaid.edge(id(:actor, actor), id(:query, query.name))}
      end

    pairs = issue ++ record ++ ask

    nodes =
      for name <- pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq(),
          do: graph_node(:actor, name, actors[name] && actors[name].label)

    {nodes, Enum.map(pairs, &elem(&1, 1))}
  end

  # --- who reads -----------------------------------------------------------------------

  # Each read model with the events it projects, and each query with what it reads. A
  # read model projected after the transaction is drawn as an asynchronous delivery.
  defp read_side(model) do
    projected =
      for rm <- model.read_models, event <- List.wrap(rm.projects) do
        {event_node(model, event),
         edge(
           %{kind: :event, name: event},
           %{kind: :read_model, name: rm.name},
           if(rm.delivery == :in_transaction, do: :inline, else: :async),
           nil
         )}
      end

    queries =
      for q <- model.queries do
        {graph_node(:query, q),
         Mermaid.edge(id(:query, q.name), id(:read_model, q.reads), label: "reads")}
      end

    nodes =
      Enum.map(projected, &elem(&1, 0)) ++
        Enum.map(model.read_models, &graph_node(:read_model, &1)) ++
        Enum.map(queries, &elem(&1, 0))

    {nodes, Enum.map(projected ++ queries, &elem(&1, 1))}
  end

  # --- the outside world ---------------------------------------------------------------

  # The domain's externals this contract touches. A dependency and an actor backing
  # are relations, not deliveries, so they have no arrowhead, as the declared shape
  # draws a dependency.
  defp externals(model, domain, actors, externals) do
    calls =
      for effect <- model.effects, external <- List.wrap(effect.calls) do
        {external,
         Mermaid.edge(id(:effect, effect.name), id(:external, external),
           line: :dotted,
           label: "calls"
         )}
      end

    depends =
      for event <- model.events, event.depends_on do
        {event.depends_on,
         Mermaid.edge(id(:event, event.name), id(:external, event.depends_on),
           line: :dotted,
           head: false
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
         Mermaid.edge(id(:actor, name), id(:external, actor.backed_by),
           line: :dotted,
           head: false,
           label: "backed by"
         )}
      end

    issued =
      for {kind, declarations} <- [command: model.commands, event: model.events],
          declaration <- declarations,
          field <- declaration.fields,
          external = issued_by(domain, field),
          external != nil do
        {external,
         Mermaid.edge(id(:external, external), id(kind, declaration.name),
           line: :dotted,
           label: "gives #{field.name}"
         )}
      end

    pairs = calls ++ depends ++ backed ++ issued

    nodes =
      for name <- pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq(),
          do: graph_node(:external, name, externals[name] && externals[name].label)

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
            &(&1.name == entity.identified_by && Map.get(&1, :issued_by))
          )
      end)
  end

  # --- the log -------------------------------------------------------------------------

  # Occurrences and runs of each event in the contract's process.
  defp event_counts(%{process: nil}, _opts), do: %{}

  defp event_counts(model, opts) do
    names =
      Enum.map(model.events, & &1.name) ++ Enum.map(model.process.includes, & &1.event)

    by_type =
      Map.new(names, fn name ->
        {_contract, e} = Model.declaring(model, name)
        {e.type, name}
      end)

    types = Map.keys(by_type)

    from(r in EventRun,
      join: e in Event,
      as: :event,
      on: e.position == r.position,
      where: r.process == ^Atom.to_string(model.process.name) and e.type in ^types,
      group_by: e.type,
      select: {e.type, count(e.id), count(r.instance_id, :distinct)}
    )
    |> bounded(opts)
    |> repo().all()
    |> Map.new(fn {type, count, runs} -> {{:event, Map.fetch!(by_type, type)}, {count, runs}} end)
  end

  defp bounded(query, opts) do
    query
    |> then(&if s = opts[:since], do: where(&1, [event: e], e.occurred_at >= ^s), else: &1)
    |> then(&if u = opts[:until], do: where(&1, [event: e], e.occurred_at <= ^u), else: &1)
  end

  defp repo, do: Application.fetch_env!(:eh_os_contract, :repo)
end
