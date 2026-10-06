defmodule EhOsContract.Graph.Facts do
  @moduledoc """
  A contract or a domain as a graph of facts (plan E13a, "the document as a graph of
  facts"): every declaration a relation can end at is a node, every link between two
  of them a relation, each with a stable id. What `EhOsContract.Graph.Document` hands
  a renderer is made of this.

  **Facts, not pictures.** Nothing here chooses what is shown together: the six
  pictures the dashboard draws today (`EhOsContract.Graph.Contract`, `Unit`,
  `Lifecycle`, `Declared`, `ContextMap`, `System`) are views over these facts, and
  views are the renderer's. A fact is what is true of the contract whatever is
  drawn and takes the DSL's meaning to know — that a timer of a process manager
  issues a command, that a consumed event is the sibling's under another name.

  Nodes are grouped by kind and relations by type, each list in declaration order;
  the kind or type is the group's key, not repeated in the element. An element is
  `%{id, name, label, source}` for a node, `%{id, from, to}` for a relation, and adds
  what it alone has. **Ownership is a field naming the owner's id** (`unit`, `stage`,
  `process`, `process_manager`, `of`, `context`, `subdomain`, `contract`): an event
  sits in a unit and in a stage, so it is not one tree, and every other link is a
  relation.

  A relation's id is its type, its two ends and what tells it apart from another of
  that type between them (`@discriminators`), so what the log says of it later joins
  on it.
  """

  alias EhOsContract.{Lifecycle, Model}
  alias EhOsContract.Graph.Document

  @contract_kinds ~w(process stage promise unit status invariant constraint command event policy
                     process_manager timer effect read_model query domain_service publication
                     actor external value entity subject context)a

  @contract_types ~w(emits handled_by starts ends issues sets cancels fires may_issue may_record
                     may_ask accountable_for builds consulted_by projected_into reads refused_on
                     enters transition allowed_in opens fulfils or_else depends_on calls
                     backed_by published_as received_as)a

  @patterns ~w(partnership shared_kernel separate_ways customer_supplier conformist
               anticorruption_layer open_host_service published_language)a

  @domain_kinds ~w(subdomain context contract event publication actor external value entity
                   subject)a

  @domain_types @patterns ++ ~w(consumed_by publishes subscribed_by backed_by accountable_for)a

  # What tells apart two relations of one type between the same two nodes.
  @discriminators [:event, :on, :phase, :operation, :name]

  @doc "The node kinds and relation types of a contract's graph, and of a domain's."
  @spec kinds(:contract | :domain) :: %{nodes: [atom()], relations: [atom()]}
  def kinds(:contract), do: %{nodes: @contract_kinds, relations: @contract_types}
  def kinds(:domain), do: %{nodes: @domain_kinds, relations: @domain_types}

  # --- a contract ----------------------------------------------------------------------

  @doc """
  The facts of `contract`: `%{nodes: %{kind => [node]}, relations: %{type =>
  [relation]}}`, every kind and type present, empty or not. Its own declarations are
  scoped to the contract, the domain's — actors, externals, publications, values,
  entities, subjects, contexts — to the domain, and only those its declarations name
  are in it.
  """
  @spec contract(module() | map()) :: %{nodes: map(), relations: map()}
  def contract(contract) do
    model = Model.fetch(contract)
    domain = domain_model(model.domain)
    c = model.module
    events = events(model)

    {process_nodes, process_relations} = process(model)
    {unit_nodes, unit_relations} = units(model)
    {reaction_nodes, reaction_relations} = reactions(model, events)

    own = %{
      command:
        for(cmd <- model.commands, do: node(:command, c, cmd, unit: id(:unit, c, cmd.unit))),
      event: Enum.map(events, & &1.node),
      read_model: Enum.map(model.read_models, &node(:read_model, c, &1)),
      query: Enum.map(model.queries, &node(:query, c, &1)),
      domain_service: Enum.map(model.domain_services, &node(:domain_service, c, &1))
    }

    nodes = Map.merge(own, process_nodes) |> Map.merge(unit_nodes) |> Map.merge(reaction_nodes)

    relations =
      [
        commands(model),
        access(model),
        read_side(model),
        outside(model, events),
        wire(model),
        process_relations,
        unit_relations,
        reaction_relations
      ]
      |> Enum.reduce(&Map.merge(&2, &1, fn _type, a, b -> a ++ b end))

    {domain_nodes, backed} = domain_nodes(model, domain, events, relations)

    nodes
    |> Map.merge(domain_nodes)
    |> group(@contract_kinds, Map.put(relations, :backed_by, backed), @contract_types)
  end

  # Every event this contract names: its own, those it consumes from a sibling under
  # the name they have here, those it receives from another application — each with
  # where it is declared and whether the process includes it.
  defp events(model) do
    c = model.module
    included = Map.new((model.process && model.process.includes) || [], &{&1.event, &1})

    own =
      for e <- model.events,
          do: %{name: e.name, declared: e, from: nil, received: false}

    consumed =
      for %{kind: :contract, from: from, events: names, renames: renames} <- model.consumes,
          original <- names do
        declared = Enum.find(Model.fetch(from).events, &(&1.name == original))
        name = Map.get(renames, original, original)
        %{name: name, declared: declared, from: id(:event, from, original), received: false}
      end

    received =
      for %{kind: :published, as: as} <- model.consumes,
          do: %{name: as, declared: %{name: as, label: nil}, from: nil, received: true}

    for e <- own ++ consumed ++ received do
      include = included[e.name]
      declared = e.declared
      own? = e.from == nil and not e.received

      # A stage is this process's: a consumed event sits in one only where an `include`
      # puts it, whatever stage its sibling gives it there.
      stage = if own?, do: declared.stage, else: include && include.stage

      Map.put(
        e,
        :node,
        node(:event, c, %{name: e.name, label: declared.label, source: declared[:source]},
          unit: own? && id(:unit, c, declared.unit),
          stage: stage_id(model, stage),
          included: include != nil,
          declared_as: e.from
        )
      )
    end
  end

  # The process, its stages and promises, who answers for it, and the events that
  # open, fulfil or settle each promise otherwise.
  defp process(%{process: nil}), do: {%{process: [], stage: [], promise: []}, %{}}

  defp process(model) do
    c = model.module
    p = model.process
    pid = id(:process, c, p.name)
    promise_id = &Document.id([:promise, c, p.name, &1])

    promises =
      for pr <- p.promises do
        %{
          id: promise_id.(pr.name),
          name: pr.name,
          label: to_string(pr.name),
          source: pr[:source],
          process: pid
        }
      end

    promised =
      for pr <- p.promises,
          {type, event} <- [opens: pr.from, fulfils: pr.eventually, or_else: pr.or_else],
          event != nil,
          do: {type, relation(id(:event, c, event), promise_id.(pr.name))}

    accountable =
      for actor <- List.wrap(p.accountable),
          do: {:accountable_for, relation(id(:actor, model.domain, actor), pid)}

    {%{
       process: [node(:process, c, p)],
       stage:
         for(
           s <- p.stages,
           do: %{
             id: stage_id(model, s.name),
             name: s.name,
             label: s.label || to_string(s.name),
             source: s[:source],
             process: pid
           }
         ),
       promise: promises
     }, typed(promised ++ accountable)}
  end

  defp stage_id(_model, nil), do: nil
  defp stage_id(model, stage), do: Document.id([:stage, model.module, model.process.name, stage])

  # Units with their statuses and rules, and what a unit is built from.
  defp units(model) do
    c = model.module

    statuses =
      for u <- model.units,
          lifecycle = Lifecycle.of(u),
          s <- lifecycle.statuses,
          do: %{
            id: status_id(c, u.name, s.name),
            name: s.name,
            label: s.label || to_string(s.name),
            source: s[:source],
            unit: id(:unit, c, u.name)
          }

    invariants =
      for u <- model.units,
          i <- u.invariants,
          do: rule(:invariant, c, :unit, u.name, i)

    built =
      for u <- model.units, e <- model.events, u.kind == :aggregate, e.unit == u.name do
        {:builds, relation(id(:event, c, e.name), id(:unit, c, u.name))}
      end

    consulted =
      for u <- model.units, u.kind == :dcb, k <- u.consults do
        {:consulted_by,
         relation(id(:event, c, k.event), id(:unit, c, u.name),
           match: match(k),
           where: k[:where]
         )}
      end

    lifecycle =
      for u <- model.units, lc = Lifecycle.of(u), reduce: [] do
        acc ->
          enters =
            for i <- lc.initial,
                do:
                  {:enters,
                   relation(id(:event, c, i.on), status_id(c, u.name, i.status),
                     source: i[:source]
                   )}

          moves =
            for t <- lc.transitions,
                from <- List.wrap(t.from),
                do:
                  {:transition,
                   relation(status_id(c, u.name, from), status_id(c, u.name, t.to),
                     event: id(:event, c, t.event),
                     source: t[:source]
                   )}

          acc ++ enters ++ moves
      end

    {%{
       unit: Enum.map(model.units, &node(:unit, c, &1)),
       status: statuses,
       invariant: invariants
     }, typed(built ++ consulted ++ lifecycle)}
  end

  defp status_id(c, unit, status), do: Document.id([:status, c, unit, status])

  defp match(%{match: [_ | _] = match}), do: match
  defp match(_where_in_prose), do: nil

  # A rule is its owner's: two owners of one kind may name theirs alike, and so may a
  # command and a policy.
  defp rule(kind, c, owner_kind, owner, rule) do
    %{
      id: Document.id([kind, c, owner_kind, owner, rule.name]),
      name: rule.name,
      label: rule.label || to_string(rule.name),
      source: rule[:source],
      of: id(owner_kind, c, owner)
    }
  end

  # What a command emits, which statuses it may be issued in, and what it is refused on.
  defp commands(model) do
    c = model.module
    units = Map.new(model.units, &{&1.name, &1})

    emits =
      for cmd <- model.commands, e <- cmd.emits do
        {:emits, relation(id(:command, c, cmd.name), id(:event, c, e))}
      end

    allowed =
      for cmd <- model.commands, s <- List.wrap(cmd[:from]) do
        {:allowed_in, relation(id(:command, c, cmd.name), status_id(c, cmd.unit, s))}
      end

    refused =
      for cmd <- model.commands, r <- cmd.rejects do
        unit = units[cmd.unit]

        to =
          if unit && Enum.any?(unit.invariants, &(&1.name == r)),
            do: Document.id([:invariant, c, :unit, cmd.unit, r]),
            else: Document.id([:constraint, c, :command, cmd.name, r])

        {:refused_on,
         relation(id(:command, c, cmd.name), to, outside_from: cmd[:or_rejects] == r || nil)}
      end

    typed(emits ++ allowed ++ refused)
  end

  # Who may issue, record and ask what.
  defp access(model) do
    c = model.module
    d = model.domain

    pairs =
      for(cmd <- model.commands, a <- cmd.by, do: {:may_issue, a, id(:command, c, cmd.name)}) ++
        for(e <- model.events, a <- e.recorded_by, do: {:may_record, a, id(:event, c, e.name)}) ++
        for q <- model.queries, a <- List.wrap(q.by), do: {:may_ask, a, id(:query, c, q.name)}

    typed(for {type, actor, to} <- pairs, do: {type, relation(id(:actor, d, actor), to)})
  end

  # Read models with the events they project, and the queries over them.
  defp read_side(model) do
    c = model.module

    projected =
      for rm <- model.read_models, e <- List.wrap(rm.projects) do
        {:projected_into, relation(id(:event, c, e), id(:read_model, c, rm.name))}
      end

    reads =
      for q <- model.queries,
          do: {:reads, relation(id(:query, c, q.name), id(:read_model, c, q.reads))}

    typed(projected ++ reads)
  end

  # Policies, effects and process managers with their timers and rules, and the flow
  # through them.
  defp reactions(model, events) do
    c = model.module
    received = MapSet.new(for e <- events, e.received, do: e.name)

    constraints =
      for {kind, declarations} <- [
            command: model.commands,
            policy: model.policies,
            process_manager: model.process_managers,
            query: model.queries,
            effect: model.effects
          ],
          d <- declarations,
          k <- Map.get(d, :constraints, []),
          do: rule(:constraint, c, kind, d.name, k)

    pm_invariants =
      for pm <- model.process_managers,
          i <- Map.get(pm, :invariants, []),
          do: rule(:invariant, c, :process_manager, pm.name, i)

    timers =
      for pm <- model.process_managers,
          t <- pm.timers,
          do:
            Map.put(node(:timer, c, t), :process_manager, id(:process_manager, c, pm.name))
            |> Map.put(:id, timer_id(c, pm.name, t.name))

    policy =
      for p <- model.policies, reduce: [] do
        acc ->
          handled =
            for e <- p.handles,
                do:
                  {:handled_by,
                   relation(id(:event, c, e), id(:policy, c, p.name),
                     via_inbox: MapSet.member?(received, e) || nil
                   )}

          issued =
            for cmd <- p.issues,
                do: {:issues, relation(id(:policy, c, p.name), id(:command, c, cmd))}

          acc ++ handled ++ issued
      end

    effect =
      for ef <- model.effects, reduce: [] do
        acc ->
          handled =
            for e <- ef.handles,
                do: {:handled_by, relation(id(:event, c, e), id(:effect, c, ef.name))}

          operations = Map.get(ef, :operations, [])

          calls =
            for x <- List.wrap(ef.calls),
                named = for(o <- operations, o.external == x, do: o.name),
                op <- if(named == [], do: [nil], else: named),
                do:
                  {:calls,
                   relation(id(:effect, c, ef.name), id(:external, model.domain, x),
                     operation: op
                   )}

          acc ++ handled ++ calls
      end

    manager = Enum.flat_map(model.process_managers, &manager(c, &1))

    # A process manager's invariants join the units' under `:invariant` in `group/4`.
    {%{
       policy: Enum.map(model.policies, &node(:policy, c, &1)),
       effect: Enum.map(model.effects, &node(:effect, c, &1)),
       process_manager: Enum.map(model.process_managers, &node(:process_manager, c, &1)),
       timer: timers,
       constraint: constraints,
       invariant_pm: pm_invariants
     }, typed(policy ++ effect ++ manager)}
  end

  defp timer_id(c, pm, timer), do: Document.id([:timer, c, pm, timer])

  # A process manager: what starts it, what it handles during its run and what ends
  # it, and on each way in what it issues, sets and cancels — with the way in on the
  # relation, since one event may start a run and arrive in one, doing different
  # things. A timer of its own may be a way in too (`on :timer`), during the run.
  defp manager(c, pm) do
    me = id(:process_manager, c, pm.name)
    timers = MapSet.new(pm.timers, & &1.name)

    trigger =
      &if(MapSet.member?(timers, &1), do: timer_id(c, pm.name, &1), else: id(:event, c, &1))

    ways =
      for(s <- pm.starts_on, do: {s, :start}) ++ for(o <- pm.on, do: {o, :run})

    entering =
      for {way, phase} <- ways, not MapSet.member?(timers, way.event) do
        {if(phase == :start, do: :starts, else: :handled_by),
         relation(id(:event, c, way.event), me)}
      end

    acting =
      for {way, phase} <- ways,
          {type, targets, to_id} <- [
            {:issues, way.issues, &id(:command, c, &1)},
            {:sets, way.sets, &timer_id(c, pm.name, &1)},
            {:cancels, Map.get(way, :cancels, []), &timer_id(c, pm.name, &1)}
          ],
          target <- targets,
          do: {type, relation(me, to_id.(target), on: trigger.(way.event), phase: phase)}

    ending = for e <- pm.ends_on, do: {:ends, relation(id(:event, c, e), me)}

    fires =
      for t <- pm.timers, cmd <- t.issues do
        {:fires, relation(timer_id(c, pm.name, t.name), id(:command, c, cmd))}
      end

    Enum.uniq(entering ++ acting ++ ending ++ fires)
  end

  # What an event rests on, the consumed ones' as their sibling declares it.
  defp outside(model, events) do
    for e <- events,
        external = e.declared[:depends_on],
        external != nil do
      {:depends_on,
       relation(id(:event, model.module, e.name), id(:external, model.domain, external))}
    end
    |> typed()
  end

  # What leaves for another application and what comes from one.
  defp wire(model) do
    c = model.module
    d = model.domain

    out =
      for p <- model.publishes do
        {:published_as,
         relation(id(:event, c, p.from), id(:publication, d, p.as),
           name: p.name,
           fields: p.fields,
           idempotent_on: p.idempotent_on
         )}
      end

    into =
      for %{kind: :published, from: name, as: as} <- model.consumes do
        {:received_as, relation(id(:publication, d, name), id(:event, c, as))}
      end

    typed(out ++ into)
  end

  # The domain's declarations the contract names: the actors that act in it, the
  # externals it rests on, calls or is given values by, the publications on the wire,
  # the values, entities and subjects its fields name, and every context those sit in
  # — each in the domain's order. A contract may name what its domain does not
  # declare, or a domain that does not exist (v2 §8): that one is a node by its name,
  # so every relation still ends at a node.
  defp domain_nodes(model, domain, events, relations) do
    d = model.domain

    acting =
      Enum.flat_map(model.commands, & &1.by) ++
        Enum.flat_map(model.events, & &1.recorded_by) ++
        Enum.flat_map(model.queries, &List.wrap(&1.by)) ++
        List.wrap(model.process && model.process.accountable)

    actors = declared(domain.actors, acting)

    # A system actor's backing is a fact of the domain, but on this contract's graph
    # only for an actor already on it.
    backing = for a <- actors, Map.get(a, :backed_by) != nil, do: a.backed_by

    {values, entities, subjects, issuers} = referenced(domain, fields(model))

    resting =
      Enum.flat_map(model.effects, &List.wrap(&1.calls)) ++
        for(e <- events, x = e.declared[:depends_on], x != nil, do: x) ++ backing ++ issuers

    publications =
      for r <- relations[:published_as] || [], do: r.to

    publications =
      Enum.uniq(publications ++ for(r <- relations[:received_as] || [], do: r.from))

    contexts =
      ([model.context] ++
         Enum.map(actors, &Map.get(&1, :context)) ++
         Enum.map(values, &Map.get(&1, :context)) ++
         Enum.map(entities, &Map.get(&1, :context)))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    context_of = &(Map.get(&1, :context) && id(:context, d, &1.context))

    backed =
      for a <- actors,
          Map.get(a, :backed_by) != nil,
          do: relation(id(:actor, d, a.name), id(:external, d, a.backed_by))

    {%{
       actor: for(a <- actors, do: node(:actor, d, a, context: context_of.(a))),
       external: Enum.map(declared(domain.externals, resting), &node(:external, d, &1)),
       publication: for(p <- publications, do: publication(d, p, model)),
       value: for(v <- values, do: node(:value, d, v, context: context_of.(v))),
       entity: for(e <- entities, do: node(:entity, d, e, context: context_of.(e))),
       subject: Enum.map(subjects, &node(:subject, d, &1)),
       context: Enum.map(declared(domain.contexts, contexts), &node(:context, d, &1))
     }, backed}
  end

  # The declarations of `names`, in the order the domain declares them, and after them
  # those it does not declare, by name alone.
  defp declared(declarations, names) do
    names = Enum.uniq(names)
    found = for x <- declarations, x.name in names, do: x
    known = MapSet.new(found, & &1.name)
    found ++ for(name <- names, not MapSet.member?(known, name), do: %{name: name, label: nil})
  end

  defp publication(d, id, model) do
    wire =
      Enum.find_value(model.publishes, &(id(:publication, d, &1.as) == id && &1.as)) ||
        Enum.find_value(model.consumes, fn
          %{kind: :published, from: name} -> id(:publication, d, name) == id && name
          _ -> nil
        end)

    %{id: id, name: wire, label: wire, source: nil}
  end

  # Every field the contract declares, wherever it sits.
  defp fields(model) do
    consumed =
      for %{kind: :contract, from: from, events: names} <- model.consumes,
          e <- Model.fetch(from).events,
          e.name in names,
          f <- e.fields,
          do: f

    received = for %{kind: :published, fields: fs} <- model.consumes, f <- fs, do: f

    Enum.flat_map(model.commands, & &1.fields) ++
      Enum.flat_map(model.events, & &1.fields) ++
      consumed ++
      received ++
      Enum.flat_map(model.units, & &1.state.fields) ++
      Enum.flat_map(model.process_managers, & &1.state.fields) ++
      Enum.flat_map(model.read_models, & &1.fields) ++
      Enum.flat_map(model.queries, & &1.params) ++
      for(s <- model.domain_services, f <- s.functions, a <- f.arguments ++ [f.returns], do: a)
  end

  # The values, entities and subjects fields name, values' and entities' own fields
  # followed, and the externals that issue what a field holds.
  defp referenced(domain, fields) do
    values = Map.new(domain.values, &{&1.name, &1})
    entities = Map.new(domain.entities, &{&1.name, &1})

    {found, _seen} = follow(fields, values, entities, {[], MapSet.new()})
    named = fn kind -> for {^kind, name} <- Enum.reverse(found), do: name end

    {declared(domain.values, named.(:value)), declared(domain.entities, named.(:entity)),
     declared(domain.subjects, named.(:subject)), Enum.uniq(named.(:issuer))}
  end

  defp follow([], _values, _entities, acc), do: acc

  defp follow([field | rest], values, entities, {found, seen}) do
    refs =
      Enum.map(type_values(Map.get(field, :type), values), &{:value, &1}) ++
        Enum.map(List.wrap(Map.get(field, :refers_to)), &{:entity, &1}) ++
        Enum.map(List.wrap(Map.get(field, :subject)), &{:subject, &1}) ++
        Enum.map(List.wrap(Map.get(field, :issued_by)), &{:issuer, &1}) ++
        Enum.map(List.wrap(issued_through(field, entities)), &{:issuer, &1})

    new = Enum.reject(refs, &MapSet.member?(seen, &1))
    seen = Enum.reduce(new, seen, &MapSet.put(&2, &1))

    nested =
      for {kind, name} <- new,
          kind in [:value, :entity],
          x = if(kind == :value, do: values, else: entities)[name],
          x != nil,
          f <- x.fields,
          do: f

    follow(nested ++ rest, values, entities, {Enum.reverse(new) ++ found, seen})
  end

  defp type_values({:list, inner}, values), do: type_values(inner, values)
  defp type_values(name, values) when is_atom(name) and is_map_key(values, name), do: [name]
  defp type_values(_type, _values), do: []

  # A field that refers to an entity holds an identifier the entity's issuer gives.
  defp issued_through(field, entities) do
    with entity when entity != nil <- Map.get(field, :refers_to),
         %{identity: identity, fields: fs} <- entities[entity] do
      Enum.find_value(fs, &(&1.name == identity && Map.get(&1, :issued_by)))
    else
      _ -> nil
    end
  end

  # --- a domain ------------------------------------------------------------------------

  @doc """
  The facts of `domain` over `contracts` (those naming another domain are left out):
  its subdomains, contexts, actors, externals, values, entities and subjects; its
  contracts and the events that cross a contract's edge; the context-mapping patterns
  and what flows between contracts and to other applications.
  """
  @spec domain(module() | map(), [module() | map()]) :: %{nodes: map(), relations: map()}
  def domain(domain, contracts) do
    domain = Model.fetch(domain)
    d = domain.module
    contexts = MapSet.new(domain.contexts, & &1.name)

    models =
      contracts
      |> Enum.map(&Model.fetch/1)
      |> Enum.filter(&(&1.domain == d))
      |> Enum.sort_by(& &1.module)

    here = MapSet.new(models, & &1.module)
    contract_id = &Document.id([:contract, &1])

    consumed =
      for m <- models,
          %{kind: :contract, from: from} = k <- m.consumes,
          MapSet.member?(here, from),
          original <- k.events,
          do: {from, m.module, original, Map.get(k.renames, original, original)}

    published = for m <- models, p <- m.publishes, do: {m, p}

    crossing =
      (for({from, _to, name, _as} <- consumed, do: {from, name}) ++
         for({m, p} <- published, do: {m.module, p.from}))
      |> Enum.uniq()

    events =
      for {module, name} <- crossing,
          e = Enum.find(Model.fetch(module).events, &(&1.name == name)),
          do: node(:event, module, e, contract: contract_id.(module))

    consumed_by =
      consumed
      |> Enum.group_by(fn {from, to, _, _} -> {from, to} end)
      |> Enum.map(fn {{from, to}, items} ->
        relation(contract_id.(from), contract_id.(to),
          events: for({_, _, name, as} <- items, do: %{event: id(:event, from, name), as: as})
        )
      end)
      |> Enum.sort_by(&{&1.from, &1.to})

    publishes =
      for {m, p} <- published,
          do:
            relation(contract_id.(m.module), id(:publication, d, p.as),
              event: id(:event, m.module, p.from)
            )

    subscribed =
      for m <- models,
          %{kind: :published, from: name, as: as} <- m.consumes,
          do: relation(id(:publication, d, name), contract_id.(m.module), as: as)

    wire =
      Enum.uniq(
        for({_m, p} <- published, do: p.as) ++
          for(m <- models, %{kind: :published, from: name} <- m.consumes, do: name)
      )

    patterns =
      for r <- domain.relations do
        end_id = fn name ->
          id(if(MapSet.member?(contexts, name), do: :context, else: :external), d, name)
        end

        {from, to} =
          case r do
            %{between: [a, b]} -> {a, b}
            _ -> {r.upstream, r.downstream}
          end

        {r.type,
         relation(end_id.(from), end_id.(to),
           terms: r.terms != [] && r.terms,
           source: r[:source]
         )}
      end

    backed =
      for a <- domain.actors, a.backed_by != nil do
        {:backed_by, relation(id(:actor, d, a.name), id(:external, d, a.backed_by))}
      end

    accountable =
      for m <- models, m.process, a <- List.wrap(m.process.accountable) do
        {:accountable_for, relation(id(:actor, d, a), contract_id.(m.module))}
      end

    context_of = &(Map.get(&1, :context) && id(:context, d, &1.context))

    nodes = %{
      subdomain: Enum.map(domain.subdomains, &node(:subdomain, d, &1)),
      context:
        for(
          c <- domain.contexts,
          do: node(:context, d, c, subdomain: id(:subdomain, d, c.subdomain))
        ),
      contract:
        for m <- models do
          %{
            id: contract_id.(m.module),
            name: m.module,
            label: inspect(m.module),
            source: nil,
            context: id(:context, d, m.context)
          }
        end,
      event: events,
      publication:
        for(w <- wire, do: %{id: id(:publication, d, w), name: w, label: w, source: nil}),
      actor: for(a <- domain.actors, do: node(:actor, d, a, context: context_of.(a))),
      external: Enum.map(domain.externals, &node(:external, d, &1)),
      value: for(v <- domain.values, do: node(:value, d, v, context: context_of.(v))),
      entity: for(e <- domain.entities, do: node(:entity, d, e, context: context_of.(e))),
      subject: Enum.map(domain.subjects, &node(:subject, d, &1))
    }

    relations =
      typed(patterns ++ backed ++ accountable)
      |> Map.merge(%{consumed_by: consumed_by, publishes: publishes, subscribed_by: subscribed})

    group(nodes, @domain_kinds, relations, @domain_types)
  end

  # --- shared --------------------------------------------------------------------------

  defp domain_model(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__eh_os_contract_model__, 0),
      do: Model.fetch(module),
      else: %{
        actors: [],
        externals: [],
        values: [],
        entities: [],
        subjects: [],
        contexts: []
      }
  end

  defp id(kind, scope, name), do: Document.id([kind, scope, name])

  # A node of a declaration: its id, name, label (or name) and source, and the owner
  # fields given, an owner of `nil` or `false` left out.
  defp node(kind, scope, declaration, owners \\ []) do
    base = %{
      id: id(kind, scope, declaration.name),
      name: declaration.name,
      label: Map.get(declaration, :label) || to_string(declaration.name),
      source: Map.get(declaration, :source)
    }

    for {key, value} <- owners, value not in [nil, false], into: base, do: {key, value}
  end

  # A relation from one node id to another, with what its type adds; an attribute
  # given as `nil` or `false` is left out, so a relation has a key only for what it
  # says. Its id is given in `group/4`, once its type is known.
  defp relation(from, to, attrs \\ []) do
    for {key, value} <- attrs,
        value not in [nil, false],
        into: %{from: from, to: to},
        do: {key, value}
  end

  # Relations tagged with their type, grouped.
  defp typed(pairs), do: Enum.group_by(pairs, &elem(&1, 0), &elem(&1, 1))

  # Each relation's id: its type, its ends and what tells it apart from another of
  # that type between them.
  defp with_ids(relations) do
    Map.new(relations, fn {type, rels} ->
      {type,
       Enum.map(rels, fn r ->
         apart = for key <- @discriminators, Map.has_key?(r, key), do: to_string(r[key])
         Map.put(r, :id, Document.id([type, r.from, r.to | apart]))
       end)}
    end)
  end

  # Every kind and type present. The same fact reached twice — an event two promises
  # open, a command two ways in issue — is one element; two different elements with
  # one id are a defect of the ids, and raise rather than lose one of them.
  defp group(nodes, kinds, relations, types) do
    nodes =
      nodes
      |> Map.update(:invariant, [], & &1)
      |> then(fn n -> Map.update!(n, :invariant, &(&1 ++ Map.get(n, :invariant_pm, []))) end)
      |> Map.delete(:invariant_pm)

    relations = with_ids(relations)

    %{
      nodes: Map.new(kinds, &{&1, distinct(Map.get(nodes, &1, []))}),
      relations: Map.new(types, &{&1, distinct(Map.get(relations, &1, []))})
    }
  end

  defp distinct(elements) do
    elements = Enum.uniq(elements)

    case elements -- Enum.uniq_by(elements, & &1.id) do
      [] ->
        elements

      [twice | _] ->
        raise ArgumentError,
              "two different declarations would have one id in the graph, #{inspect(twice.id)}: " <>
                inspect(Enum.filter(elements, &(&1.id == twice.id)))
    end
  end
end
