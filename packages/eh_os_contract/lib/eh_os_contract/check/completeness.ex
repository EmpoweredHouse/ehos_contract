defmodule EhOsContract.Check.Completeness do
  @moduledoc """
  ESDM's completeness rules over v2 contracts and their domains (v2 §6, L5; plan
  EL1): what a model may legally leave out and a reader should still hear about.

  ESDM makes them warnings and so does this module; the structural rules ESDM has
  are errors here, in L2 and L3. Each rule reads a whole domain at once — every
  contract naming it — because what makes an actor an orphan or a context empty is
  that *no* contract uses it, which no one contract can tell.

  A domain's declarations are read with the file and line Spark kept, as L3 reads a
  contract's, so a finding points at the actor, the context or the relation it is
  about.
  """

  alias EhOsContract.Check.Finding
  alias EhOsContract.Domain
  alias EhOsContract.Next.Contract.{Links, Rules}

  @doc """
  Every finding of a completeness rule about `contracts`, v2 contract modules,
  and the domains they name.
  """
  @spec findings([module()]) :: [Finding.t()]
  def findings(contracts) do
    linked = contracts |> Enum.map(&Links.contract/1) |> Enum.reject(&is_nil/1)

    domains =
      for {domain, members} <- Enum.group_by(linked, & &1.model.domain),
          members = Enum.reject(members, &is_nil(&1.domain)),
          members != [],
          finding <- domain(domain, members),
          do: finding

    domains ++ Enum.flat_map(linked, &contract(&1, linked))
  end

  # --- one contract --------------------------------------------------------------

  defp contract(c, all) do
    Enum.concat([
      units_without_events(c),
      events_without_consumer(c, all),
      read_models_without_query(c),
      managers_without_ends_on(c),
      managers_without_event_reactions(c),
      prefixed_event_names(c),
      consults_without_match(c)
    ])
  end

  defp declared_unit(c, name), do: Enum.find(c.declarations.units, &(&1.name == name))

  defp declared_event(c, unit, name) do
    with %{} = declared <- declared_unit(c, unit),
         %{} = event <- Enum.find(Rules.events(declared), &(&1.name == name)),
         do: Links.at(event)
  end

  # ESDM's `aggregate-without-events`, and a boundary's alike: a unit that can
  # decide nothing, since a command has to emit (A1) and there is nothing to emit.
  defp units_without_events(%{model: model} = c) do
    for unit <- model.units, not Enum.any?(model.events, &(&1.unit == unit.name)) do
      Finding.new(
        "aggregate-without-events",
        "#{unit.kind} #{inspect(unit.name)} of #{inspect(model.module)} declares no event, so " <>
          "no command of it can decide anything and nothing is ever recorded of it",
        c.declarations.units |> Enum.find(&(&1.name == unit.name)) |> Links.at()
      )
    end
  end

  # ESDM's `event-without-consumer`. A consumer is what reacts to or reads the
  # event: a policy, an effect, a process manager, a read model, a boundary that
  # consults it, a contract that consumes it, a `publish`. So is the conformance
  # half of this library, for an event a promise names or one that ends a run: the
  # report reads it. The unit's own `evolve` does not count; ESDM's aggregate folds
  # its events too.
  defp events_without_consumer(%{model: model} = c, all) do
    process = model.process

    local =
      Enum.flat_map(model.policies, &List.wrap(&1.handles)) ++
        Enum.flat_map(model.effects, &List.wrap(&1.handles)) ++
        Enum.flat_map(model.process_managers, fn pm ->
          Enum.map(pm.starts_on, & &1.event) ++ Enum.map(pm.on, & &1.event) ++ pm.ends_on
        end) ++
        Enum.flat_map(model.read_models, &List.wrap(&1.projects)) ++
        Enum.flat_map(model.units, fn u -> Enum.map(u.consults, & &1.event) end) ++
        Enum.map(model.publishes, & &1.from) ++
        if(process,
          do: Enum.flat_map(process.promises, &[&1.from, &1.eventually, &1.or_else]),
          else: []
        )

    siblings =
      for %{model: other} <- all,
          %{kind: :contract, from: from, events: events} <- other.consumes,
          from == model.module,
          event <- events,
          do: event

    consumed = MapSet.new(local ++ siblings)

    for event <- model.events,
        not event.terminal,
        not MapSet.member?(consumed, event.name) do
      Finding.new(
        "event-without-consumer",
        "event #{inspect(event.name)} of #{inspect(model.module)} has no consumer: no policy, " <>
          "effect, process manager or read model takes it, no boundary consults it, no contract " <>
          "consumes it, nothing publishes it, and no promise names it",
        declared_event(c, event.unit, event.name)
      )
    end
  end

  # ESDM's `read-model-without-query`.
  defp read_models_without_query(%{model: model} = c) do
    read = MapSet.new(model.queries, & &1.reads)

    for read_model <- model.read_models, not MapSet.member?(read, read_model.name) do
      Finding.new(
        "read-model-without-query",
        "read model #{inspect(read_model.name)} of #{inspect(model.module)} is read by no query, " <>
          "so nothing can ask it anything",
        at(c.declarations.read_models, read_model.name)
      )
    end
  end

  # ESDM's `process-manager-without-ends-when`, under the word this DSL uses.
  defp managers_without_ends_on(%{model: model} = c) do
    for pm <- model.process_managers, pm.ends_on == [] do
      Finding.new(
        "process-manager-without-ends-on",
        "process manager #{inspect(pm.name)} of #{inspect(model.module)} declares no `ends_on`, " <>
          "so every run it starts stays open for ever",
        at(c.declarations.process_managers, pm.name)
      )
    end
  end

  # ESDM's `process-manager-without-event-reactions`: a manager whose every reaction
  # after its start is one of its own timers. `ends_on` is not a reaction, as ESDM's
  # `endsWhen` is not.
  defp managers_without_event_reactions(%{model: model} = c) do
    for pm <- model.process_managers,
        timers = MapSet.new(pm.timers, & &1.name),
        pm.timers != [],
        Enum.all?(pm.on, &MapSet.member?(timers, &1.event)) do
      Finding.new(
        "process-manager-without-event-reactions",
        "process manager #{inspect(pm.name)} of #{inspect(model.module)} reacts to nothing after " <>
          "it starts but its own timers — no `on` names an event — so what happens in the " <>
          "process can end it, and not steer it",
        at(c.declarations.process_managers, pm.name)
      )
    end
  end

  # ESDM's `event-name-with-aggregate-prefix`: the event's type already carries its
  # process, and the unit is where it is declared.
  defp prefixed_event_names(%{model: model} = c) do
    for event <- model.events,
        String.starts_with?(Atom.to_string(event.name), "#{event.unit}_") do
      Finding.new(
        "event-name-with-aggregate-prefix",
        "event #{inspect(event.name)} repeats the name of its unit #{inspect(event.unit)} " <>
          "(#{inspect(model.module)}); the unit is where it is declared, so the name can say " <>
          "only what happened",
        declared_event(c, event.unit, event.name)
      )
    end
  end

  # The library's own: a boundary consulting an event by `where:` alone reads every
  # event of that type, and conflicts with every new one (plan EM1).
  defp consults_without_match(%{model: model} = c) do
    for unit <- model.units,
        consults <- unit.consults,
        consults.match == [] do
      at =
        with %{} = declared <- declared_unit(c, unit.name),
             %{} = found <- Enum.find(declared.consults, &(&1.event == consults.event)),
             do: Links.at(found)

      Finding.new(
        "consults-without-match",
        "boundary #{inspect(unit.name)} of #{inspect(model.module)} consults " <>
          "#{inspect(consults.event)} with `where:` alone, so it reads every such event and " <>
          "any new one, whoever it is about, conflicts with its decision",
        at
      )
    end
  end

  # --- a whole domain ------------------------------------------------------------

  defp domain(module, contracts) do
    model = hd(contracts).domain
    declared = declared(module)

    Enum.concat([
      orphan_actors(model, declared, contracts),
      orphan_externals(model, declared, contracts),
      empty_contexts(model, declared, contracts),
      empty_subdomains(model, declared),
      orphan_relations(model, declared, contracts),
      unmapped_references(model, contracts),
      relations_against_references(model, declared, contracts),
      avoided_terms(model, contracts)
    ])
  end

  # The domain's declarations as Spark kept them, with where each was written.
  defp declared(module) do
    entities = Spark.Dsl.Extension.get_entities(module, [:domain])
    of = fn struct -> for %{__struct__: ^struct} = e <- entities, do: e end

    %{
      subdomains: of.(Domain.Dsl.Subdomain),
      actors: of.(Domain.Dsl.Actor),
      externals: of.(Domain.Dsl.External),
      contexts: of.(Domain.Dsl.Context),
      relations: of.(Domain.Dsl.Relation)
    }
  end

  defp at(declarations, name) do
    case Enum.find(declarations, &(&1.name == name)) do
      nil -> nil
      declaration -> Links.at(declaration)
    end
  end

  # ESDM's `orphan-actor`: an actor no command, query, recorded event or process
  # names. A scenario's actor is in a command's `by:` already (S7).
  defp orphan_actors(model, declared, contracts) do
    named =
      MapSet.new(
        for %{model: m} <- contracts,
            actor <-
              Enum.flat_map(m.commands, & &1.by) ++
                Enum.flat_map(m.queries, & &1.by) ++
                Enum.flat_map(m.events, & &1.recorded_by) ++
                List.wrap(m.process && m.process.accountable),
            do: actor
      )

    for actor <- model.actors, not MapSet.member?(named, actor.name) do
      Finding.new(
        "orphan-actor",
        "actor #{inspect(actor.name)} of #{inspect(model.module)} is in no command's or query's " <>
          "`by:`, no event's `recorded_by:` and no process's `accountable`, so no contract gives " <>
          "it anything to do",
        at(declared.actors, actor.name)
      )
    end
  end

  # ESDM's `orphan-external-system`: an external no actor stands for, no effect calls
  # and no event depends on.
  defp orphan_externals(model, declared, contracts) do
    named =
      MapSet.new(
        Enum.map(model.actors, & &1.backed_by) ++
          Enum.flat_map(model.relations, &Domain.Build.endpoints/1) ++
          for({_context, external} <- domain_issuers(model), do: external) ++
          Enum.flat_map(contracts, &issuers(&1.model)) ++
          for(
            %{model: m} <- contracts,
            external <-
              Enum.flat_map(m.effects, &List.wrap(&1.calls)) ++
                Enum.flat_map(m.events, &List.wrap(&1.depends_on)),
            do: external
          )
      )

    for external <- model.externals, not MapSet.member?(named, external.name) do
      Finding.new(
        "orphan-external-system",
        "external #{inspect(external.name)} of #{inspect(model.module)} backs no actor, ends no " <>
          "relation and issues no field, and no effect `calls:` it and no event `depends_on:` it",
        at(declared.externals, external.name)
      )
    end
  end

  # ESDM's `bounded-context-without-content`, which counts aggregates, boundaries and
  # read models: here a context no contract belongs to, since a contract is what
  # holds them.
  defp empty_contexts(model, declared, contracts) do
    used = MapSet.new(contracts, & &1.model.context)

    for context <- model.contexts, not MapSet.member?(used, context.name) do
      Finding.new(
        "bounded-context-without-content",
        "context #{inspect(context.name)} of #{inspect(model.module)} is the `context:` of no " <>
          "contract, so nothing is decided, recorded or read in it",
        at(declared.contexts, context.name)
      )
    end
  end

  # ESDM's `subdomain-without-bounded-context`: a subdomain no context names.
  defp empty_subdomains(model, declared) do
    named = MapSet.new(model.contexts, & &1.subdomain)

    for subdomain <- model.subdomains, not MapSet.member?(named, subdomain.name) do
      Finding.new(
        "subdomain-without-bounded-context",
        "subdomain #{inspect(subdomain.name)} of #{inspect(model.module)} is the `subdomain:` of " <>
          "no context",
        at(declared.subdomains, subdomain.name)
      )
    end
  end

  # ESDM's `orphan-context-mapping`: a relation no reference crosses, in either
  # direction.
  defp orphan_relations(model, declared, contracts) do
    # A relation to an external is crossed when a contract of its context uses the
    # external (plan EL2); only a relation between contexts counts as ESDM's mapping for
    # `cross-bounded-context-reference-without-mapping`, so these stay out of it.
    external_uses =
      for(
        c <- contracts,
        external <- externals_used(c.model, model),
        do: MapSet.new([external, c.model.context])
      ) ++
        for {context, external} <- domain_issuers(model),
            context != nil,
            do: MapSet.new([external, context])

    crossing =
      MapSet.new(Enum.map(crossings(model, contracts), &elem(&1, 0)) ++ external_uses)

    for {relation, index} <- Enum.with_index(model.relations),
        pair = relation |> Domain.Build.endpoints() |> MapSet.new(),
        not MapSet.member?(crossing, pair) do
      [a, b] = Domain.Build.endpoints(relation)

      Finding.new(
        "orphan-context-mapping",
        "relation #{inspect(relation.type)} between #{inspect(a)} and #{inspect(b)} in " <>
          "#{inspect(model.module)} is crossed by no reference: no contract of one consumes a " <>
          "contract of the other or names an entity it owns, and none uses an external it ends at",
        declared.relations |> Enum.at(index) |> then(&(&1 && Links.at(&1)))
      )
    end
  end

  # ESDM's `cross-bounded-context-reference-without-mapping`: a contract that consumes
  # a contract of another context, or names an entity another context owns, with no
  # relation declared between the two contexts. One finding per reference.
  defp unmapped_references(model, contracts) do
    mapped = MapSet.new(model.relations, &MapSet.new(Domain.Build.endpoints(&1)))

    for {pair, contract, what, at} <- crossings(model, contracts),
        not MapSet.member?(mapped, pair),
        uniq: true do
      other = pair |> MapSet.delete(contract.model.context) |> Enum.at(0)

      Finding.new(
        "cross-bounded-context-reference-without-mapping",
        "#{inspect(contract.module)} in context #{inspect(contract.model.context)} #{what} of " <>
          "context #{inspect(other)}, and #{inspect(model.module)} declares no relation between " <>
          "the two",
        at
      )
    end
  end

  # The library's own (plan EL2, "Po EL2" rule 1): a relation that says which way the
  # dependency runs, and a reference that runs the other way. `separate_ways` says
  # there is none, so any reference contradicts it; a directed relation says the
  # downstream context depends on the upstream one, so a reference from the upstream
  # context into the downstream one contradicts it. Between contexts only: which way
  # a call to an external system runs says nothing about who depends on whom.
  defp relations_against_references(model, declared, contracts) do
    references = crossings(model, contracts)
    directed = EhOsContract.Domain.Dsl.directed_relations()

    for {relation, index} <- Enum.with_index(model.relations),
        {pair, contract, what, _at} <- references,
        pair == MapSet.new(Domain.Build.endpoints(relation)),
        against?(relation, contract.model.context, directed),
        uniq: true do
      Finding.new(
        "relation-against-references",
        "#{inspect(contract.module)} in context #{inspect(contract.model.context)} #{what}, " <>
          "and #{describe_relation(relation)} in #{inspect(model.module)} says #{says(relation)}",
        declared.relations |> Enum.at(index) |> then(&(&1 && Links.at(&1)))
      )
    end
  end

  defp against?(%{type: :separate_ways}, _from, _directed), do: true

  defp against?(%{type: type, upstream: upstream}, from, directed),
    do: type in directed and from == upstream

  defp says(%{type: :separate_ways}), do: "the two contexts do not depend on each other"

  defp says(relation),
    do: "#{inspect(relation.upstream)} does not depend on #{inspect(relation.downstream)}"

  defp describe_relation(%{type: :separate_ways, between: [a, b]}),
    do: "relation :separate_ways between #{inspect(a)} and #{inspect(b)}"

  defp describe_relation(relation),
    do:
      "relation #{inspect(relation.type)} from upstream #{inspect(relation.upstream)} to " <>
        "downstream #{inspect(relation.downstream)}"

  # The library's own (plan EL2, "Po EL2" rule 2): a label of a contract that uses a
  # word its context's glossary says to avoid. Whole words, any case; the words a
  # translation avoids belong to another language, which labels are not written in.
  defp avoided_terms(model, contracts) do
    avoided =
      Map.new(model.contexts, fn context ->
        {context.name, for(t <- context.terms, a <- t.avoid, do: {a.text, t.text})}
      end)

    for c <- contracts,
        words = Map.get(avoided, c.model.context, []),
        words != [],
        declaration <- labelled(c.declarations),
        {word, term} <- words,
        String.match?(declaration.label, word_pattern(word)),
        uniq: true do
      Finding.new(
        "label-with-avoided-term",
        "#{inspect(c.module)}: the label #{inspect(declaration.label)} says #{inspect(word)}, which " <>
          "context #{inspect(c.model.context)} avoids in favour of #{inspect(term)}",
        Links.at(declaration)
      )
    end
  end

  defp word_pattern(word),
    do: Regex.compile!("(?<![\\p{L}\\p{N}])#{Regex.escape(word)}(?![\\p{L}\\p{N}])", "iu")

  # Every declaration of a contract that has a label, at any depth.
  defp labelled(%{__struct__: _} = struct) do
    own = if is_binary(Map.get(struct, :label)), do: [struct], else: []

    own ++
      (struct
       |> Map.from_struct()
       |> Map.delete(:__spark_metadata__)
       |> Map.values()
       |> labelled())
  end

  defp labelled(%{} = map), do: map |> Map.values() |> labelled()
  defp labelled(list) when is_list(list), do: Enum.flat_map(list, &labelled/1)
  defp labelled(_other), do: []

  # Every reference from a contract into another context: `{contexts, contract, what,
  # at}`, the contexts as an unordered pair, `at` the `consumes` it is made by or, for
  # an entity named in a field, the contract's `use`.
  defp crossings(model, contracts) do
    context_of = Map.new(contracts, &{&1.module, &1.model.context})
    owner = Map.new(model.entities, &{&1.name, &1.context})

    for contract <- contracts,
        {other, what, at} <-
          for(
            %{from: from} = consumes <- contract.declarations.consumes,
            is_atom(from),
            other = Map.get(context_of, from) || context_of(from),
            do: {other, "consumes #{inspect(from)}", Links.at(consumes)}
          ) ++
            for(
              entity <- contract.model |> references() |> Enum.uniq(),
              other = Map.get(owner, entity),
              do: {other, "names entity #{inspect(entity)}", contract.at}
            ),
        other != nil and other != contract.model.context do
      {MapSet.new([other, contract.model.context]), contract, what, at}
    end
  end

  # The externals a contract reaches: what its effects call, what its events depend on,
  # what issues its fields' values, and what stands behind the actors it names — in a
  # command's or a query's `by:`, an event's `recorded_by:`, the process's `accountable`.
  defp externals_used(contract, domain) do
    backing = Map.new(domain.actors, &{&1.name, &1.backed_by})

    actors =
      Enum.flat_map(contract.commands, & &1.by) ++
        Enum.flat_map(contract.queries, & &1.by) ++
        Enum.flat_map(contract.events, & &1.recorded_by) ++
        List.wrap(contract.process && contract.process.accountable)

    Enum.flat_map(contract.effects, &List.wrap(&1.calls)) ++
      Enum.flat_map(contract.events, &List.wrap(&1.depends_on)) ++
      issuers(contract) ++
      for(actor <- actors, backed = Map.get(backing, actor), do: backed)
  end

  # Every external a field of the contract says issues its value (plan EL2), read off
  # the model's lists of fields, not off every map in it: a scenario's data may have a
  # key of that name.
  defp issuers(contract) do
    fields =
      Enum.flat_map(contract.units, & &1.state.fields) ++
        Enum.flat_map(contract.commands, & &1.fields) ++
        Enum.flat_map(contract.events, & &1.fields) ++
        Enum.flat_map(contract.read_models, & &1.fields) ++
        Enum.flat_map(contract.process_managers, & &1.state.fields) ++
        Enum.flat_map(contract.consumes, & &1.fields)

    for field <- fields, external = Map.get(field, :issued_by), do: external
  end

  # `{context, external}` for every field of a domain value or entity an external
  # issues: the entity's context, or the value's, when it names one.
  defp domain_issuers(domain) do
    for owner <- domain.values ++ domain.entities,
        field <- Map.get(owner, :fields, []),
        external = Map.get(field, :issued_by),
        do: {Map.get(owner, :context), external}
  end

  # A consumed contract outside the modules checked is looked up by name, as L3 does.
  defp context_of(module) do
    case Links.contract(module) do
      %{model: %{context: context}} -> context
      nil -> nil
    end
  end

  # Every entity a field of the model refers to (plan EM2), at any depth.
  defp references(%{refers_to: entity} = map),
    do: [entity | map |> Map.delete(:refers_to) |> references()]

  defp references(%{} = map), do: map |> Map.values() |> Enum.flat_map(&references/1)
  defp references(list) when is_list(list), do: Enum.flat_map(list, &references/1)
  defp references(_other), do: []
end
