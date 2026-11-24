defmodule EhosContract.Graph.Facts do
  # A contract or a domain as a graph of facts (plan E13a, "the document as a graph of
  # facts"): every declaration a relation can end at is a node, every link between two
  # of them a relation, each with a stable id. What `EhosContract.Graph.Document` hands
  # a renderer is made of this.
  #
  # **Facts, not pictures.** Nothing here chooses what is shown together: the pictures
  # the dashboard draws — a contract's full graph, a process module's stages, a unit, a
  # lifecycle, a domain's context map and its system — are views over these facts, and
  # views are the renderer's (`ehos_contract_graph`). A fact is what is true of the
  # contract whatever is drawn and takes the DSL's meaning to know — that a timer of a
  # process manager issues a command, that a consumed event is the sibling's under
  # another name.
  #
  # Nodes are grouped by kind and relations by type, each list in declaration order;
  # the kind or type is the group's key, not repeated in the element. An element is
  # `%{id, name, label, source}` for a node, `%{id, from, to}` for a relation, and adds
  # what it alone has. **Ownership is a field naming the owner's id** (`unit`, `stage`,
  # `process`, `process_manager`, `of`, `context`, `subdomain`, `contract`): an event
  # sits in a unit in its contract's document and in a stage in a process module's, so
  # it is not one tree, and every other link is a relation.
  #
  # A relation's id is its type, its two ends and what tells it apart from another of
  # that type between them (`@discriminators`), so what the log says of it later joins
  # on it.
  #
  # **A node carries what its panel shows** (plan E13a, batch 4): a declaration's
  # fields in one shape (`field/2`), what a person needs to be granted to use it, its
  # delivery and idempotency, its windows. A `label` is the client's words or `nil`,
  # never the name put in their place: which to show is the renderer's choice. What
  # holds example or default data — scenarios, defaults, a domain service's rule
  # examples, a value's invariant examples — is redacted first, as
  # `EhosContract.Model.to_data/1` redacts it, so no personal value leaves in a
  # document.
  #
  # **Scenarios** are neither nodes nor relations: a contract's are grouped by the
  # kind of their target (`unit`, `policy`, `process_manager`, `query`), each naming
  # its `target` and the ids of the relations it exercises (`covers`), which the
  # engine computes so a count on an arrow and the list behind it come from one place.
  @moduledoc false

  alias EhosContract.{Lifecycle, Model}
  alias EhosContract.Graph.Document
  alias EhosContract.Contract.Links

  # A contract declares no process (plan DD, P2h, #221): a process's stages, promises and
  # who answers for it are a process module's document's (plan DD, P2e, #220).
  @contract_kinds ~w(unit status invariant constraint command event policy process_manager timer
                     effect read_model query domain_service publication actor external value
                     entity subject context)a

  @contract_types ~w(emits handled_by starts ends issues sets cancels fires may_issue may_record
                     may_ask builds consulted_by projected_into reads refused_on enters transition
                     allowed_in depends_on calls backed_by published_as received_as)a

  @patterns ~w(partnership shared_kernel separate_ways customer_supplier conformist
               anticorruption_layer open_host_service published_language)a

  @domain_kinds ~w(subdomain context contract process event publication actor external value
                   entity subject)a

  @domain_types @patterns ++
                  ~w(consumed_by refers_to publishes subscribed_by backed_by accountable_for
                     includes)a

  @process_kinds ~w(process stage promise event contract context actor external)a

  @process_types ~w(accountable_for opens fulfils or_else depends_on waits_on)a

  # What tells apart two relations of one type between the same two nodes: a
  # subscription's `as`, a DCB's `match` and `where` (the prose by its hash) among them.
  @discriminators [:event, :on, :phase, :operation, :name, :as, :match, :where]

  @doc "The node kinds and relation types of a contract's graph, a domain's and a process's."
  @spec kinds(:contract | :domain | :process) :: %{nodes: [atom()], relations: [atom()]}
  def kinds(:contract), do: %{nodes: @contract_kinds, relations: @contract_types}
  def kinds(:domain), do: %{nodes: @domain_kinds, relations: @domain_types}
  def kinds(:process), do: %{nodes: @process_kinds, relations: @process_types}

  # --- a contract ----------------------------------------------------------------------

  @doc """
  The facts of `contract`: `%{nodes: %{kind => [node]}, relations: %{type =>
  [relation]}, scenarios: %{group => [scenario]}}`, every kind, type and
  group present, empty or not: a group is a target kind, or `record` for the
  scenarios that record an event of a unit. Its own declarations are scoped to the
  contract, the domain's — actors, externals, publications, values, entities,
  subjects, contexts — to the domain, and only those its declarations name are in
  it.
  """
  @spec contract(module() | map()) :: %{nodes: map(), relations: map(), scenarios: map()}
  def contract(contract) do
    {model, domain} = redacted(contract)
    c = model.id
    # A field may identify one of the contract's own units (plan DD, L3 (#286)).
    ctx = Map.put(context(model.domain, domain, grants(model)), :units, unit_scopes(model))
    events = events(model, ctx)

    {unit_nodes, unit_relations} = units(model, ctx)
    {reaction_nodes, reaction_relations} = reactions(model, events, ctx)

    own = %{
      command:
        for cmd <- model.commands do
          node(:command, c, cmd,
            unit: id(:unit, c, cmd.unit),
            fields: fields(cmd.fields, ctx),
            scope: cmd[:scope],
            creates: cmd[:creates],
            reads: reads(cmd, ctx),
            actor_is: cmd[:actor_is] && cmd.actor_is.field,
            capability: ctx.grants[{:command, cmd.name}]
          )
        end,
      event: Enum.map(events, & &1.node),
      read_model:
        for rm <- model.read_models do
          node(:read_model, c, rm,
            fields: fields(rm.fields, ctx, :read_model),
            delivery: rm.delivery
          )
        end,
      query:
        for q <- model.queries do
          node(:query, c, q,
            params: fields(q.params, ctx),
            returns: q.returns,
            scope: q.scope,
            capability: ctx.grants[{:query, q.name}]
          )
        end,
      domain_service:
        for s <- model.domain_services do
          node(:domain_service, c, s, functions: Enum.map(s.functions, &function(&1, ctx)))
        end
    }

    nodes = own |> Map.merge(unit_nodes) |> Map.merge(reaction_nodes)

    relations =
      [
        commands(model),
        access(model),
        read_side(model),
        outside(model, events),
        wire(model),
        unit_relations,
        reaction_relations
      ]
      |> Enum.reduce(&Map.merge(&2, &1, fn _type, a, b -> a ++ b end))

    {domain_nodes, backed} = domain_nodes(model, domain, events, relations, ctx)

    facts =
      nodes
      |> Map.merge(domain_nodes)
      |> group(@contract_kinds, Map.put(relations, :backed_by, backed), @contract_types)

    Map.put(facts, :scenarios, scenarios(model, facts.relations, Model.fetch(contract).scenarios))
  end

  # The model and its domain with every example and default redacted, as
  # `Model.to_data/1` exports them.
  defp redacted(contract) do
    model = Model.fetch(contract)
    Model.Export.redact(model, domain_model(model.domain))
  end

  # Every event this contract names: its own, those it consumes from a sibling under
  # the name they have here, those it receives from another application — each with
  # where it is declared. A consumed one is as
  # its sibling declares it, a received one as this contract's `subscribe` reads it.
  defp events(model, ctx) do
    c = model.id

    own =
      for e <- model.events,
          do: %{name: e.name, declared: e, from: nil, in: nil, received: false}

    consumed =
      for %{kind: :contract, from: from, events: names, renames: renames} <- model.consumes,
          {sibling, _domain} = redacted(from),
          original <- names do
        declared = Enum.find(sibling.events, &(&1.name == original))
        name = Map.get(renames, original, original)

        %{
          name: name,
          declared: declared,
          from: id(:event, sibling.id, original),
          in: sibling.id,
          received: false
        }
      end

    received =
      for %{kind: :published, as: as, fields: fields} <- model.consumes,
          do: %{
            name: as,
            declared: %{name: as, label: nil, fields: fields},
            from: nil,
            in: nil,
            received: true
          }

    for e <- own ++ consumed ++ received do
      declared = e.declared
      own? = e.from == nil and not e.received

      # A person records an event of this contract; the application is granted one it
      # receives. A sibling's is granted in the sibling.
      capability =
        cond do
          own? -> ctx.grants[{:record, e.name}]
          e.received -> subscription(ctx.grants, model, e.name)
          true -> nil
        end

      Map.put(
        e,
        :node,
        node(:event, c, %{name: e.name, label: declared.label, source: declared[:source]},
          unit: own? && id(:unit, c, declared.unit),
          declared_as: e.from,
          declared_in: e.in,
          fields: fields(declared.fields, ctx, if(not e.received, do: :event)),
          type: declared[:type],
          schema_version: declared[:schema_version],
          capability: capability
        )
      )
    end
  end

  # Units with their statuses and rules, and what a unit is built from.
  defp units(model, ctx) do
    c = model.id

    statuses =
      for u <- model.units,
          lifecycle = Lifecycle.of(u),
          s <- lifecycle.statuses,
          do:
            with_attrs(
              %{
                id: status_id(c, u.name, s.name),
                name: s.name,
                label: s.label,
                source: s[:source]
              },
              unit: id(:unit, c, u.name),
              final: s[:final]
            )

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
       unit:
         for u <- model.units do
           node(:unit, c, u,
             unit_kind: u.kind,
             identity: u.identity,
             generated: u[:generated],
             state: fields(u.state.fields, ctx),
             # Plan DD, C1 (#304): as its page says it, derived, never declared.
             records_only: EhosContract.Refusals.records_only?(model, u)
           )
         end,
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
      label: rule.label,
      source: rule[:source],
      of: id(owner_kind, c, owner)
    }
  end

  # What a command emits, which statuses it may be issued in, and what it is refused on.
  defp commands(model) do
    c = model.id
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
        {:refused_on,
         relation(id(:command, c, cmd.name), refusal(c, units[cmd.unit], cmd.name, r),
           outside_from: cmd[:or_rejects] == r || nil,
           actor_is: (cmd[:actor_is] && cmd.actor_is.or_rejects == r) || nil
         )}
      end

    typed(emits ++ allowed ++ refused)
  end

  # What a command's decision reads before it runs (plan DD, T2a, #240): each row by the
  # name the decision gets it under, the field of the command holding its id, and the
  # entity it is a row of — the one the field's type names. Left out where it reads none.
  defp reads(cmd, ctx) do
    case Map.get(cmd, :reads, []) do
      [] ->
        nil

      reads ->
        for {name, field} <- reads do
          refers_to = Enum.find_value(cmd.fields, &(&1.name == field && Map.get(&1, :refers_to)))
          %{name: name, field: field, entity: refers_to && id(:entity, ctx.d, refers_to)}
        end
    end
  end

  # The invariant of a domain value a recording's or a command's data breaks, as
  # dispatch names it, from the fields of `declared`, the event or the command: the
  # value held by the field whose data breaks it.
  defp broken(model, declared, s) do
    with invariant when invariant != nil <- s.rejected,
         %{fields: fields} <- declared,
         values = EhosContract.Codec.values(model.domain),
         value when value != nil <-
           Links.Scenarios.refusing_value(fields, invariant, values, s.written_data, model.domain) do
      %{value: id(:value, model.domain, value), invariant: Atom.to_string(invariant)}
    else
      _ -> nil
    end
  end

  # The rule a command is refused on: an invariant of its unit, or else a constraint of
  # its own.
  defp refusal(c, unit, command, rule) do
    if unit && Enum.any?(unit.invariants, &(&1.name == rule)),
      do: Document.id([:invariant, c, :unit, unit.name, rule]),
      else: Document.id([:constraint, c, :command, command, rule])
  end

  # Who may issue, record and ask what.
  defp access(model) do
    c = model.id
    d = model.domain

    pairs =
      for(cmd <- model.commands, a <- cmd.by, do: {:may_issue, a, id(:command, c, cmd.name)}) ++
        for(e <- model.events, a <- e.recorded_by, do: {:may_record, a, id(:event, c, e.name)}) ++
        for q <- model.queries, a <- List.wrap(q.by), do: {:may_ask, a, id(:query, c, q.name)}

    typed(for {type, actor, to} <- pairs, do: {type, relation(id(:actor, d, actor), to)})
  end

  # Read models with the events they project, and the queries over them.
  defp read_side(model) do
    c = model.id

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
  defp reactions(model, events, ctx) do
    c = model.id
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
            node(:timer, c, t,
              process_manager: id(:process_manager, c, pm.name),
              wait: t.wait,
              at: t.at
            )
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
       policy: Enum.map(model.policies, &reaction(:policy, c, &1)),
       effect: Enum.map(model.effects, &reaction(:effect, c, &1)),
       process_manager:
         for pm <- model.process_managers do
           reaction(:process_manager, c, pm,
             state: fields(pm.state.fields, ctx),
             correlate: pm.correlate
           )
         end,
       timer: timers,
       constraint: constraints,
       invariant_pm: pm_invariants
     }, typed(policy ++ effect ++ manager)}
  end

  defp timer_id(c, pm, timer), do: Document.id([:timer, c, pm, timer])

  # A reaction runs in the dispatch's transaction or after it, and says what makes a
  # second delivery harmless.
  defp reaction(kind, c, declaration, attrs \\ []) do
    node(
      kind,
      c,
      declaration,
      attrs ++ [delivery: declaration.delivery, idempotency: declaration.idempotency]
    )
  end

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

  # The scenarios, grouped by what they are about — a unit, a policy, a process
  # manager or a query; an effect and a read model are no scenario's target (S6) —
  # each with the ids of the relations it exercises. Their data is already redacted.
  defp scenarios(model, relations, unredacted) do
    c = model.id

    find = fn type, from, to, attrs ->
      Enum.find_value(relations[type], fn r ->
        (r.from == from and r.to == to and Enum.all?(attrs, fn {k, v} -> r[k] == v end)) && r.id
      end)
    end

    groups = [aggregate: :unit, dcb: :unit, policy: :policy, process_manager: :process_manager]
    groups = groups ++ [query: :query]

    # A recording's scenario is about its unit, and a group of its own, since it has
    # no command a unit's scenario always carries (issue #430).
    # Which value a scenario's data breaks is asked of the data as written, before the
    # redaction masks a personal field (the review of #458); only the value's id leaves.
    for {s, written} <- Enum.zip(model.scenarios, unredacted),
        s = Map.put(s, :written_data, written.trigger.data),
        about = groups[s.target.kind],
        group = if(s.trigger.kind == :record, do: :record, else: about),
        reduce: Map.new([:unit, :record, :policy, :process_manager, :query], &{&1, []}) do
      acc ->
        base = %{
          id: Document.id([:scenario, c, s.description]),
          description: s.description,
          target: id(about, c, s.target.name)
        }

        {shape, covers} = scenario(group, s, model, find)
        covers = covers |> Enum.reject(&is_nil/1) |> Enum.uniq()
        Map.update!(acc, group, &(&1 ++ [base |> Map.merge(shape) |> Map.put(:covers, covers)]))
    end
  end

  # A unit's: who issues which command after which events, and what it emits or the
  # rule it is refused on, or the invariant of a domain value its data breaks (issue
  # #458). It covers the command's arrow to each expected event, or to that rule.
  defp scenario(:unit, s, model, find) do
    c = model.id
    command = id(:command, c, s.trigger.name)
    unit = Enum.find(model.units, &(&1.name == s.target.name))
    declared = Enum.find(model.commands, &(&1.name == s.trigger.name))

    {rule, on_value} =
      cond do
        s.rejected == nil -> {nil, nil}
        Links.Scenarios.refused_on_value?(s, declared) -> {nil, broken(model, declared, s)}
        true -> {refusal(c, unit, s.trigger.name, s.rejected), nil}
      end

    covers =
      for(e <- s.expect, do: find.(:emits, command, id(:event, c, e.event), [])) ++
        [rule && find.(:refused_on, command, rule, [])]

    # The rows its command reads and the person issuing it (plan DD, T2a, #240, and A1,
    # #247), where the scenario gives them; the rows redacted as the model's export does.
    entities =
      for row <- Map.get(s, :given_entities, []),
          do: %{entity: id(:entity, model.domain, row.entity), data: row.data}

    {with_attrs(
       %{
         given: happened(c, s.given),
         command: %{command: command, data: s.trigger.data},
         expect: happened(c, s.expect)
       },
       actor: s.actor && id(:actor, model.domain, s.actor),
       as: s[:as],
       given_entities: if(entities != [], do: entities),
       rejected: rule,
       rejected_on_value: on_value
     ), covers}
  end

  # A recording's (issue #430): who records which event after which events, and that it
  # is appended, or the invariant of a domain value its data breaks. It covers the
  # actor's arrow to the event.
  defp scenario(:record, s, model, find) do
    c = model.id
    event = id(:event, c, s.trigger.name)
    actor = s.actor && id(:actor, model.domain, s.actor)

    rejected = broken(model, Enum.find(model.events, &(&1.name == s.trigger.name)), s)

    {with_attrs(
       %{
         given: happened(c, s.given),
         record: %{event: event, data: s.trigger.data},
         expect: happened(c, s.expect)
       },
       actor: actor,
       rejected: rejected
     ), [actor && find.(:may_record, actor, event, [])]}
  end

  # A policy's: the event delivered and the commands it issues. It covers the event's
  # arrow to the policy and the policy's to each command.
  defp scenario(:policy, s, model, find) do
    c = model.id
    me = id(:policy, c, s.target.name)
    event = id(:event, c, s.trigger.name)

    covers =
      [find.(:handled_by, event, me, [])] ++
        for i <- s.issues, do: find.(:issues, me, id(:command, c, i.command), [])

    {%{
       event: %{event: event, data: s.trigger.data},
       issues: issued(c, s.issues),
       illustrates: illustrated(c, :policy, s.target.name, [], s)
     }, covers}
  end

  # A process manager's: the run so far, the event or timer that arrives, whether it
  # starts the run, and what the manager issues, sets, cancels, whether it ends and
  # what it holds after. It starts the run when its event is one the run starts on and
  # no given has started one, as `EhosContract.ScenarioCase` and dispatch read it
  # (decision 1 before batch 4); otherwise it arrives during the run, and a timer
  # always does. It covers the way the trigger reaches the manager — `starts`, or
  # `handled_by` where the event is handled during the run, plus `ends` where it ends
  # the run; a timer's `fires` to each command issued — and each `issues`, `sets` and
  # `cancels` the manager does on that way in.
  defp scenario(:process_manager, s, model, find) do
    c = model.id
    pm = Enum.find(model.process_managers, &(&1.name == s.target.name))
    me = id(:process_manager, c, pm.name)
    starts = Enum.map(pm.starts_on, & &1.event)
    timer? = Enum.any?(pm.timers, &(&1.name == s.trigger.name))
    started? = Enum.any?(s.given, &(&1.event in starts))
    phase = if not timer? and s.trigger.name in starts and not started?, do: :start, else: :run

    {trigger, way} =
      if timer?,
        do: {timer_id(c, pm.name, s.trigger.name), :timer},
        else: {id(:event, c, s.trigger.name), :event}

    command = &id(:command, c, &1)
    timer = &timer_id(c, pm.name, &1)
    on = [on: trigger, phase: phase]

    entering =
      cond do
        timer? -> for i <- s.issues, do: find.(:fires, trigger, command.(i.command), [])
        phase == :start -> [find.(:starts, trigger, me, [])]
        true -> [find.(:handled_by, trigger, me, [])]
      end

    ending = if timer?, do: [], else: [find.(:ends, trigger, me, [])]

    acting =
      for(i <- s.issues, do: find.(:issues, me, command.(i.command), on)) ++
        for(t <- s.sets, do: find.(:sets, me, timer.(t), on)) ++
        for t <- s.cancels, do: find.(:cancels, me, timer.(t), on)

    {with_attrs(
       %{
         given: happened(c, s.given),
         trigger: %{way => trigger, :data => s.trigger.data},
         phase: phase,
         issues: issued(c, s.issues),
         sets: Enum.map(s.sets, timer),
         cancels: Enum.map(s.cancels, timer),
         illustrates: illustrated(c, :process_manager, pm.name, pm[:invariants] || [], s)
       },
       ended: s.ended,
       state: s[:state]
     ), entering ++ ending ++ acting}
  end

  # A query's: the events projected, the parameters asked with, the rows answered. It
  # covers the query's read and each given event's projection into what it reads.
  defp scenario(:query, s, model, find) do
    c = model.id
    query = Enum.find(model.queries, &(&1.name == s.target.name))
    me = id(:query, c, query.name)
    read = id(:read_model, c, query.reads)

    covers =
      [find.(:reads, me, read, [])] ++
        for g <- s.given, do: find.(:projected_into, id(:event, c, g.event), read, [])

    {with_attrs(
       %{
         given: happened(c, s.given),
         params: s.trigger.data,
         illustrates: illustrated(c, :query, query.name, [], s)
       },
       answers: s[:answers]
     ), covers}
  end

  # A given's moment where the scenario dates it (plan DD, S2, #251).
  defp happened(c, events),
    do:
      for(e <- events, do: with_attrs(%{event: id(:event, c, e.event), data: e.data}, at: e[:at]))

  defp issued(c, commands),
    do: for(i <- commands, do: %{command: id(:command, c, i.command), data: i.data})

  # The rules a scenario shows: the owner's invariants where it has the name, else its
  # constraints.
  defp illustrated(c, kind, owner, invariants, s) do
    for name <- Map.get(s, :illustrates, []) do
      rule = if Enum.any?(invariants, &(&1.name == name)), do: :invariant, else: :constraint
      Document.id([rule, c, kind, owner, name])
    end
  end

  # What an event rests on, the consumed ones' as their sibling declares it.
  defp outside(model, events) do
    for e <- events,
        external = e.declared[:depends_on],
        external != nil do
      {:depends_on, relation(id(:event, model.id, e.name), id(:external, model.domain, external))}
    end
    |> typed()
  end

  # What leaves for another application and what comes from one.
  defp wire(model) do
    c = model.id
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
  defp domain_nodes(model, domain, events, relations, ctx) do
    d = model.domain

    acting =
      Enum.flat_map(model.commands, & &1.by) ++
        Enum.flat_map(model.events, & &1.recorded_by) ++
        Enum.flat_map(model.queries, &List.wrap(&1.by))

    actors = declared(domain.actors, acting)

    # A system actor's backing is a fact of the domain, but on this contract's graph
    # only for an actor already on it.
    backing = for a <- actors, Map.get(a, :backed_by) != nil, do: a.backed_by

    {values, entities, subjects, issuers} = referenced(domain, all_fields(model))

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

    backed =
      for a <- actors,
          Map.get(a, :backed_by) != nil,
          do: relation(id(:actor, d, a.name), id(:external, d, a.backed_by))

    {%{
       actor: for(a <- actors, do: actor(a, ctx)),
       external: for(x <- declared(domain.externals, resting), do: external(x, ctx)),
       publication: for(p <- publications, do: publication(d, p, model)),
       value: for(v <- values, do: value(v, ctx)),
       entity: for(e <- entities, do: entity(e, ctx)),
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

    # A publication is a name on the wire, with no words of its own in the DSL.
    %{id: id, name: wire, label: nil, source: nil}
  end

  # Every field the contract declares, wherever it sits.
  defp all_fields(model) do
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
      for(s <- model.domain_services, f <- s.functions, a <- f.arguments ++ [returned(f)], do: a)
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
    # A unit's name is no entity (plan DD, L3 (#286)), whatever this document holds of it.
    refs =
      Enum.map(type_values(Map.get(field, :type), values), &{:value, &1}) ++
        for(
          name <- List.wrap(Map.get(field, :refers_to)),
          is_map_key(entities, name),
          do: {:entity, name}
        ) ++
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
          # A value is followed through its own type as well as its fields.
          f <- if(kind == :value and x.type != nil, do: [x | x.fields], else: x.fields),
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

  # --- a process module (plan DD, P2e, #220) ---------------------------------------------

  @doc """
  The facts of the process module `process`: the process, its stages, the events its
  stages include — each under the id it has in the document of the contract that
  declares it, so the two documents join — with the stage it sits in and whether it
  ends a run, the contracts those events come from and their contexts, the external
  systems those events rest on (`depends_on`, as in the contract's document), its
  promises with the events that open, fulfil or settle each otherwise and the systems
  each waits on (`waits_on`), and the actor
  accountable for it. Every kind and type present, empty or not.
  """
  @spec process(module() | map()) :: %{nodes: map(), relations: map()}
  def process(process) do
    model = Model.fetch(process)
    %{} = p = Model.process(model)
    domain = domain_model(model.domain)
    d = model.domain
    ctx = context(d, domain, %{})
    pid = id(:process, p.name)
    stage_id = &Document.id([:stage, p.name, &1])
    promise_id = &Document.id([:promise, p.name, &1])

    included = Model.process_events(model)
    contracts = included |> Enum.map(& &1.contract) |> Enum.uniq() |> Enum.map(&Model.fetch/1)
    ids = Map.new(contracts, &{&1.module, &1.id})
    contract_id = &id(:contract, ids[&1])
    event_id = Map.new(included, &{&1.name, Document.id([:event, ids[&1.contract], &1.name])})

    events =
      for e <- included do
        node(:event, ids[e.contract], e.declaration,
          contract: contract_id.(e.contract),
          stage: stage_id.(e.stage),
          terminal: e.terminal,
          type: e.type
        )
      end

    # A promise has no words of its own in the DSL.
    promises =
      for pr <- p.promises do
        with_attrs(%{id: promise_id.(pr.name), name: pr.name, label: nil, source: pr[:source]},
          process: pid,
          within: pr.within,
          unverified: pr.unverified
        )
      end

    promised =
      for pr <- p.promises,
          {type, event} <- [opens: pr.from, fulfils: pr.eventually, or_else: pr.or_else],
          from = event && event_id[event],
          do: {type, relation(from, promise_id.(pr.name))}

    # What an included event rests on, as its contract declares it: an outage of it is
    # what suspends a promise.
    resting =
      for e <- included,
          x = e.declaration[:depends_on],
          x != nil,
          do: {event_id[e.name], x}

    rests = for {from, x} <- resting, do: {:depends_on, relation(from, id(:external, d, x))}

    # What a promise waits on through an earlier step (plan DD, OW1 (#355)): an outage of
    # it suspends the promise as one of its events' own dependencies does.
    waiting =
      for pr <- p.promises, x <- Map.get(pr, :waits_on, []), do: {promise_id.(pr.name), x}

    waits = for {from, x} <- waiting, do: {:waits_on, relation(from, id(:external, d, x))}

    actors = List.wrap(accountable(domain, p.accountable))

    accountable =
      for a <- actors, do: {:accountable_for, relation(id(:actor, d, a.name), pid)}

    contexts =
      (Enum.map(contracts, & &1.context) ++ Enum.map(actors, &Map.get(&1, :context)))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    nodes = %{
      process: [
        with_attrs(%{id: pid, name: p.name, label: p.label, source: p[:source]},
          correlate: p.correlate,
          deadline: p.deadline
        )
      ],
      stage:
        for(
          s <- p.stages,
          do: %{
            id: stage_id.(s.name),
            name: s.name,
            label: s.label,
            source: s[:source],
            process: pid
          }
        ),
      promise: promises,
      event: events,
      # The same node as in the domain's document.
      contract: Enum.map(contracts, &contract_node(&1, d)),
      context: Enum.map(declared(domain.contexts, contexts), &node(:context, d, &1)),
      actor: for(a <- actors, do: actor(a, ctx)),
      external:
        for(
          x <- declared(domain.externals, Enum.map(resting ++ waiting, &elem(&1, 1))),
          do: external(x, ctx)
        )
    }

    group(nodes, @process_kinds, typed(promised ++ accountable ++ rests ++ waits), @process_types)
  end

  # A contract as a node of a domain's or a process module's document. A contract has no
  # words of its own in the DSL. Named by its id, as everything outside the code names it
  # (plan DD, P1a, #183); its module beside it, for a reader in the code. A contract
  # declares no process (plan DD, P2h, #221), so the optional `process` and `correlate`
  # of the shape are left out.
  defp contract_node(m, d) do
    with_attrs(%{id: id(:contract, m.id), name: m.id, label: nil, source: nil},
      context: id(:context, d, m.context),
      module: m.module
    )
  end

  # The actor who answers for a process module, as the domain declares it, or nil: one
  # the domain does not declare is no node and no arrow, in the process's document as in
  # the domain's, where only declared actors are nodes.
  defp accountable(_domain, nil), do: nil
  defp accountable(domain, name), do: Enum.find(domain.actors, &(&1.name == name))

  # --- a domain ------------------------------------------------------------------------

  @doc """
  The facts of `domain` over `modules`, its contracts and process modules (those naming
  another domain are left out): its subdomains, contexts, actors, externals, values,
  entities and subjects; its contracts and the events that cross a contract's edge; the
  context-mapping patterns and what flows between contracts and to other applications;
  its process modules, the contracts whose events each includes and who answers for it.
  """
  @spec domain(module() | map(), [module() | map()]) :: %{nodes: map(), relations: map()}
  def domain(domain, modules) do
    domain = domain |> Model.fetch() |> Model.Export.redact_domain()
    d = domain.module
    ctx = context(d, domain, %{})
    contexts = MapSet.new(domain.contexts, & &1.name)
    code = EhosContract.CodeWords.code_language(domain)

    fetched =
      modules
      |> Enum.map(&Model.fetch/1)
      |> Enum.filter(&(&1.domain == d))
      |> Enum.sort_by(& &1.id)

    models = Enum.filter(fetched, &(&1.kind == :contract))
    processes = Enum.filter(fetched, &(&1.kind == :process))

    here = MapSet.new(models, & &1.module)
    # Everything of a contract is named by its `id:` (plan DD, ID3, #173), which the
    # log names it by too; a sibling is reached here by its module.
    ids = Map.new(models, &{&1.module, &1.id})
    contract_id = &Document.id([:contract, ids[&1]])

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
          do: node(:event, ids[module], e, contract: contract_id.(module))

    consumed_by =
      consumed
      |> Enum.group_by(fn {from, to, _, _} -> {from, to} end)
      |> Enum.map(fn {{from, to}, items} ->
        relation(contract_id.(from), contract_id.(to),
          events:
            for({_, _, name, as} <- items, do: %{event: id(:event, ids[from], name), as: as})
        )
      end)
      |> Enum.sort_by(&{&1.from, &1.to})

    # A contract keeping the number of a sibling's unit (plan DD, L3 (#286)): one relation
    # per pair, from the contract that keeps it to the one whose unit it is.
    referents = EhosContract.References.index(domain, models)

    refers_to =
      for(
        m <- models,
        name <- EhosContract.References.in_model(m),
        {:unit, owner, unit} <- [Map.get(referents, name)],
        owner.module != m.module,
        do: {m.module, owner.module, unit}
      )
      |> Enum.group_by(fn {from, to, _} -> {from, to} end, &elem(&1, 2))
      |> Enum.map(fn {{from, to}, units} ->
        relation(contract_id.(from), contract_id.(to), units: Enum.sort(Enum.uniq(units)))
      end)
      |> Enum.sort_by(&{&1.from, &1.to})

    publishes =
      for {m, p} <- published,
          do:
            relation(contract_id.(m.module), id(:publication, d, p.as),
              event: id(:event, m.id, p.from)
            )

    granted = Map.new(models, &{&1.module, Model.capabilities(&1)})

    # The grant to take it is the application's, never a person's: only where a policy
    # handles it (`EhosContract.Model.capabilities/1`).
    subscribed =
      for m <- models,
          %{kind: :published, from: name, as: as} <- m.consumes,
          do:
            relation(id(:publication, d, name), contract_id.(m.module),
              as: as,
              capability: subscription(keyed(granted[m.module]), m, as)
            )

    # What each role may do, by contract, under the names EHOS grants it by.
    capabilities =
      Enum.group_by(
        for m <- models,
            {capability, g} <- Enum.sort(granted[m.module]),
            role <- g.roles do
          {role,
           %{
             capability: capability,
             kind: g.kind,
             contract: contract_id.(m.module),
             declaration: id(declaration_kind(g.kind), m.id, g.name)
           }}
        end,
        &elem(&1, 0),
        &elem(&1, 1)
      )

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

        # A pattern declared `between:` two contexts is symmetric: neither is upstream.
        {r.type,
         relation(end_id.(from), end_id.(to),
           terms: r.terms != [] && r.terms,
           source: r[:source],
           symmetric: match?(%{between: [_, _]}, r)
         )}
      end

    backed =
      for a <- domain.actors, a.backed_by != nil do
        {:backed_by, relation(id(:actor, d, a.name), id(:external, d, a.backed_by))}
      end

    # A process module (plan DD, P2e, #220): an arrow to each contract of these whose
    # events it includes, and from the actor who answers for it.
    process_id = &id(:process, &1.id)

    includes =
      for p <- processes,
          contract <- p |> Model.process_events() |> Enum.map(& &1.contract) |> Enum.uniq(),
          MapSet.member?(here, contract),
          do: {:includes, relation(process_id.(p), contract_id.(contract))}

    accountable =
      for p <- processes,
          a = accountable(domain, p.accountable),
          a != nil,
          do: {:accountable_for, relation(id(:actor, d, a.name), process_id.(p))}

    nodes = %{
      process:
        for p <- processes do
          with_attrs(%{id: process_id.(p), name: p.id, label: p.label, source: p.source},
            module: p.module,
            correlate: p.correlate
          )
        end,
      subdomain: for(s <- domain.subdomains, do: node(:subdomain, d, s, type: s.type)),
      context:
        for c <- domain.contexts do
          node(:context, d, c,
            subdomain: id(:subdomain, d, c.subdomain),
            language: c.language,
            terms: Enum.map(c.terms, &term(&1, c.language || domain.language, code))
          )
        end,
      contract: Enum.map(models, &contract_node(&1, d)),
      event: events,
      publication:
        for(w <- wire, do: %{id: id(:publication, d, w), name: w, label: nil, source: nil}),
      actor:
        for a <- domain.actors do
          a
          |> actor(ctx)
          |> Map.put(:capabilities, Map.get(capabilities, "#{domain.name}.#{a.name}", []))
        end,
      external: for(x <- domain.externals, do: external(x, ctx)),
      value: for(v <- domain.values, do: value(v, ctx)),
      entity: for(e <- domain.entities, do: entity(e, ctx)),
      subject: Enum.map(domain.subjects, &node(:subject, d, &1))
    }

    relations =
      typed(patterns ++ backed ++ includes ++ accountable)
      |> Map.merge(%{
        consumed_by: consumed_by,
        refers_to: refers_to,
        publishes: publishes,
        subscribed_by: subscribed
      })

    group(nodes, @domain_kinds, relations, @domain_types)
  end

  # --- shared --------------------------------------------------------------------------

  defp domain_model(module) do
    if compiled?(module),
      do: Model.fetch(module),
      else: %{
        name: nil,
        actors: [],
        externals: [],
        values: [],
        entities: [],
        subjects: [],
        contexts: []
      }
  end

  defp compiled?(module),
    do: Code.ensure_loaded?(module) and function_exported?(module, :__ehos_contract_model__, 0)

  defp id(kind, scope, name), do: Document.id([kind, scope, name])
  defp id(kind, name), do: Document.id([kind, name])

  # A node of a declaration: its id, name, label and source — the label the client's
  # words or `nil`, never the name in their place — and what else is given.
  defp node(kind, scope, declaration, attrs \\ []) do
    with_attrs(
      %{
        id: id(kind, scope, declaration.name),
        name: declaration.name,
        label: Map.get(declaration, :label),
        source: Map.get(declaration, :source)
      },
      attrs
    )
  end

  # A relation from one node id to another, with what its type adds. Its id is given
  # in `group/4`, once its type is known.
  defp relation(from, to, attrs \\ []), do: with_attrs(%{from: from, to: to}, attrs)

  # An attribute given as `nil` or `false` is left out, so an element has a key only
  # for what it says (batch 3: absent, not null).
  defp with_attrs(base, attrs),
    do: for({key, value} <- attrs, value not in [nil, false], into: base, do: {key, value})

  # What a field's content is resolved against: the domain's module, its name, its
  # values and entities, and the capabilities of the contract by kind and name.
  defp context(d, domain, grants) do
    %{
      d: d,
      name: Map.get(domain, :name),
      values: MapSet.new(domain.values, & &1.name),
      entities: Map.new(domain.entities, &{&1.name, &1}),
      units: %{},
      grants: grants
    }
  end

  # The contract's capabilities keyed `{kind, name}`, where its domain is compiled to
  # name them by (`EhosContract.Model.capabilities/1`).
  defp grants(model) do
    if compiled?(model.domain),
      do: keyed(Model.capabilities(model)),
      else: %{}
  end

  defp keyed(capabilities), do: Map.new(capabilities, fn {c, g} -> {{g.kind, g.name}, c} end)

  # The application's grant to take what it receives as `as`, only where a policy
  # handles that name. `Model.capabilities/1` keeps one grant per publication, named
  # after one of the names it is received under, so a publication received under two
  # names finds its grant by the publication, not by the name.
  defp subscription(grants, model, as) do
    with %{from: from} <- Enum.find(model.consumes, &match?(%{kind: :published, as: ^as}, &1)),
         true <- Enum.any?(model.policies, &(as in &1.handles)) do
      Enum.find_value(model.consumes, fn
        %{kind: :published, from: ^from, as: name} -> grants[{:subscribe, name}]
        _ -> nil
      end)
    else
      _ -> nil
    end
  end

  defp declaration_kind(:record), do: :event
  defp declaration_kind(kind), do: kind

  defp fields(fields, ctx, held \\ nil), do: Enum.map(fields || [], &field(&1, ctx, held))

  # A field in the one shape every panel shows: name, label, type, whether it is
  # required, and what applies of its default, whose personal data it is, the subject
  # it points at, the domain value its type is, the entity it identifies, the external
  # that issues it — its own `issued_by:` or its entity's identity's — and whether the
  # host supplies it — and what keeps a value about a person, where the declaration
  # holding the field is `held` in the log (`:event`) or in a read model's rows.
  defp field(f, ctx, held \\ nil) do
    issuer = Map.get(f, :issued_by) || issued_through(f, ctx.entities)

    for {key, value} <- [
          default: Map.get(f, :default),
          personal_of: Map.get(f, :personal),
          subject: Map.get(f, :subject) && id(:subject, ctx.d, f.subject),
          value: value_of(f.type, ctx),
          refers_to: refers_to(Map.get(f, :refers_to), ctx),
          issued_by: issuer && id(:external, ctx.d, issuer),
          supplied_by: Map.get(f, :supplied_by),
          kept: kept(f, held)
        ],
        value != nil,
        into: %{
          name: f.name,
          label: Map.get(f, :label),
          type: type(f.type),
          required: not Map.get(f, :optional, false)
        },
        do: {key, value}
  end

  # What keeps a field's value about a person (v2 §14, `EhosContract.Personal`): an
  # event's personal data is sealed in the log with its subject's key, which erasing the
  # subject destroys, and its pointer at the subject stays in the log in the clear; a
  # read model's personal data is in its rows, which it forgets when the subject is
  # erased — the engine does not start a read model that projects personal data and
  # cannot forget (`Personal.check_forgetting!/1`). A command, a unit's state, a
  # manager's and a received event's keep nothing of it in the log, so it is left out.
  defp kept(f, :event) do
    cond do
      Map.get(f, :personal) -> "log_sealed"
      Map.get(f, :subject) -> "log_clear"
      true -> nil
    end
  end

  defp kept(f, :read_model), do: if(Map.get(f, :personal), do: "rows_forgotten")
  defp kept(_f, nil), do: nil

  # A type as data: a built-in's or a domain value's name, `%{list: type}`, or an
  # inline enum with each member's label.
  defp type({:list, inner}), do: %{list: type(inner)}

  defp type({:enum, members}) do
    %{
      enum:
        for m <- members do
          case m do
            {value, label} -> %{value: value, label: label}
            value -> %{value: value, label: nil}
          end
        end
    }
  end

  defp type(name), do: name

  defp value_of({:list, inner}, ctx), do: value_of(inner, ctx)

  defp value_of(name, ctx) when is_atom(name),
    do: if(MapSet.member?(ctx.values, name), do: id(:value, ctx.d, name))

  defp value_of(_type, _ctx), do: nil

  # A domain service's function: its arguments, its result and its rules with their
  # examples, which `redacted/1` has already redacted.
  defp function(f, ctx) do
    returns = field(returned(f), ctx)

    %{
      name: f.name,
      label: f.label,
      arguments: fields(f.arguments, ctx),
      returns: Map.drop(returns, [:name, :label]),
      rules:
        for r <- f.rules do
          %{
            name: r.name,
            label: r.label,
            source: r[:source],
            examples:
              for({arguments, result} <- r.examples, do: %{arguments: arguments, result: result})
          }
        end
    }
  end

  # What a field identifies (plan DD, L3 (#286)): an entity of the domain, or a unit of
  # this contract. A unit of another contract is in no node here: the document holds
  # this contract and the domain's declarations it names, never a sibling's.
  defp refers_to(nil, _ctx), do: nil

  defp refers_to(name, ctx) do
    cond do
      Map.has_key?(ctx.entities, name) -> id(:entity, ctx.d, name)
      scope = Map.get(ctx.units, name) -> id(:unit, scope, name)
      true -> nil
    end
  end

  defp unit_scopes(model), do: Map.new(model.units, &{&1.name, model.id})

  # What a function returns, as a field without a name: `{:id, entity}` read the way
  # the model reads it on every named field (`EhosContract.Domain.Build.reference/1`).
  defp returned(f), do: EhosContract.Domain.Build.reference(Map.put(f.returns, :name, nil))

  # The domain's declarations, as both documents carry them; one known by its name
  # alone carries nothing else.
  defp actor(a, ctx) do
    node(:actor, ctx.d, a,
      context: in_context(a, ctx),
      actor_kind: Map.get(a, :kind),
      role: Map.get(a, :kind) == :human && ctx.name && "#{ctx.name}.#{a.name}",
      scope: Map.get(a, :scope),
      responsibilities: described(Map.get(a, :responsibilities))
    )
  end

  defp external(x, ctx) do
    node(:external, ctx.d, x,
      direction: Map.get(x, :direction),
      unavailable_looks_like: Map.get(x, :unavailable_looks_like),
      expected_latency: duration(Map.get(x, :expected_latency)),
      operations: described(Map.get(x, :operations))
    )
  end

  defp value(v, ctx) do
    typed = Map.get(v, :type) && field(v, ctx)

    # A value typed as another value, or as an entity's id, names it as a field would.
    node(:value, ctx.d, v,
      context: in_context(v, ctx),
      type: typed && typed.type,
      value: typed && typed[:value],
      refers_to: typed && typed[:refers_to],
      issued_by: typed && typed[:issued_by],
      unit: Map.get(v, :unit),
      fields: Map.has_key?(v, :fields) && fields(v.fields, ctx),
      invariants:
        Map.has_key?(v, :invariants) &&
          for i <- v.invariants do
            %{
              name: i.name,
              label: i.label,
              source: i[:source],
              satisfied_by: i.satisfied_by,
              violated_by: i.violated_by
            }
          end
    )
  end

  defp entity(e, ctx) do
    node(:entity, ctx.d, e,
      context: in_context(e, ctx),
      identity: Map.get(e, :identity),
      fields: Map.has_key?(e, :fields) && fields(e.fields, ctx)
    )
  end

  defp in_context(declaration, ctx),
    do: Map.get(declaration, :context) && id(:context, ctx.d, declaration.context)

  defp described(nil), do: nil

  defp described(items),
    do: for(x <- items, do: %{name: x.name, label: x.label, source: x[:source]})

  defp duration({amount, unit}), do: %{amount: amount, unit: unit}
  defp duration(other), do: other

  # A term of a context's glossary, whole: its definition, what to avoid and why, its
  # translations, and its word in code where it has one — its text in the domain's
  # `code_language:`, written in the context's language `own` (plan DD, L1, #269), as
  # the glossary and the check read it.
  defp term(t, own, code) do
    word = EhosContract.CodeWords.in_code(t, own, code)

    %{
      text: t.text,
      definition: t.definition,
      source: t[:source],
      avoid: avoid(t.avoid),
      translations:
        for tr <- t.translations do
          %{
            language: tr.language,
            text: tr.text,
            definition: tr.definition,
            avoid: avoid(tr.avoid)
          }
        end
    }
    |> then(&if(word, do: Map.put(&1, :code, word), else: &1))
  end

  defp avoid(items), do: for(a <- items, do: %{text: a.text, reason: a.reason})

  # Relations tagged with their type, grouped.
  defp typed(pairs), do: Enum.group_by(pairs, &elem(&1, 0), &elem(&1, 1))

  # Each relation's id: its type, its ends and what tells it apart from another of
  # that type between them.
  defp with_ids(relations) do
    Map.new(relations, fn {type, rels} ->
      {type,
       Enum.map(rels, fn r ->
         apart = for key <- @discriminators, Map.has_key?(r, key), do: apart(key, r[key])
         Map.put(r, :id, Document.id([type, r.from, r.to | apart]))
       end)}
    end)
  end

  defp apart(:match, fields), do: "match=" <> Enum.map_join(fields, ",", &to_string/1)

  defp apart(:where, prose),
    do: "where=" <> String.slice(Base.encode16(:crypto.hash(:sha256, prose), case: :lower), 0, 16)

  defp apart(_key, value), do: to_string(value)

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
