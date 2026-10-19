defmodule EhOsContract.Check.Completeness do
  # ESDM's completeness rules over v2 contracts and their domains (v2 §6, L5; plan
  # EL1): what a model may legally leave out and a reader should still hear about.
  #
  # ESDM makes them warnings and so does this module; the structural rules ESDM has
  # are errors here, in L2 and L3. Each rule reads a whole domain at once — every
  # contract naming it — because what makes an actor an orphan or a context empty is
  # that *no* contract uses it, which no one contract can tell.
  #
  # A domain's declarations are read with the file and line Spark kept, as L3 reads a
  # contract's, so a finding points at the actor, the context or the relation it is
  # about.
  @moduledoc false

  alias EhOsContract.Check.Finding
  alias EhOsContract.Domain
  alias EhOsContract.Lifecycle
  alias EhOsContract.Model
  alias EhOsContract.Contract.{Links, Rules}
  alias EhOsContract.Contract.Links.ContextMap

  @doc """
  Every finding of a completeness rule about `contracts`, v2 contract modules,
  and the domains they name. `processes`, the process modules, are read for what they
  include: an event one includes has a reader, the report of its runs (plan DD, P2d,
  #213); and for whom they hold `accountable`, an actor with something to do (plan DD,
  P2h, #221).
  """
  @spec findings([module()], [module()]) :: [Finding.t()]
  def findings(contracts, processes \\ []) do
    linked = contracts |> Enum.map(&Links.contract/1) |> Enum.reject(&is_nil/1)
    included = included(processes)

    domains =
      for {domain, members} <- Enum.group_by(linked, & &1.model.domain),
          members = Enum.reject(members, &is_nil(&1.domain)),
          members != [],
          finding <- domain(domain, members, processes),
          do: finding

    domains ++ Enum.flat_map(linked, &contract(&1, linked, included))
  end

  # Every event a process module includes, as `{contract, event}`.
  defp included(processes) do
    for module <- processes,
        event <- Model.process_events(module),
        into: MapSet.new(),
        do: {event.contract, event.name}
  end

  # --- one contract --------------------------------------------------------------

  defp contract(c, all, included) do
    Enum.concat([
      units_without_events(c),
      events_without_consumer(c, all, included),
      read_models_without_query(c),
      managers_without_ends_on(c),
      managers_without_event_reactions(c),
      in_transaction_fan_out(c),
      prefixed_event_names(c),
      consults_without_match(c),
      without_scenario(c),
      unillustrated(c),
      untaken_transitions(c),
      core_commands_never_refusing(c),
      core_units_recording_only(c)
    ])
  end

  # Plan DD, L2 (#272): the core is where things are decided. A contract is core when
  # its context belongs to a subdomain of `type: :core`.
  defp core?(%{domain: nil}), do: false

  defp core?(%{domain: domain, model: model}) do
    with %{subdomain: subdomain} <- Enum.find(domain.contexts, &(&1.name == model.context)),
         %{type: type} <- Enum.find(domain.subdomains, &(&1.name == subdomain)) do
      type == :core
    else
      _ -> false
    end
  end

  # A command of the core that nothing can refuse, unless only a reaction issues it:
  # what a policy or a timer sends follows from an event already decided. A command an
  # actor may issue too (`by:`) is a person's request like any other.
  defp core_commands_never_refusing(%{model: model} = c) do
    if core?(c) do
      # Every way a reaction issues, a timer's included: what one fires was decided too.
      issued = MapSet.new(EhOsContract.Reactions.issued(model), & &1.command)

      for command <- model.commands,
          not EhOsContract.Refusals.refuses?(command),
          List.wrap(command.by) != [] or not MapSet.member?(issued, command.name) do
        Finding.new(
          "core-command-never-refuses",
          "command #{inspect(command.name)} of #{inspect(c.module)}, in core context " <>
            "#{inspect(model.context)}, rejects nothing: no rule of its unit can refuse it",
          declared_command(c, command.unit, command.name)
        )
      end
    else
      []
    end
  end

  # A unit of the core none of whose commands can be refused: it decides nothing.
  defp core_units_recording_only(%{model: model} = c) do
    if core?(c) do
      for unit <- model.units, EhOsContract.Refusals.records_only?(model, unit) do
        Finding.new(
          "core-unit-records-only",
          "#{unit.kind} #{inspect(unit.name)} of #{inspect(c.module)}, in core context " <>
            "#{inspect(model.context)}, only records: no command it takes can be refused",
          with(%{} = declared <- declared_unit(c, unit.name), do: Links.at(declared))
        )
      end
    else
      []
    end
  end

  defp declared_unit(c, name), do: Enum.find(c.declarations.units, &(&1.name == name))

  defp declared_event(c, unit, name) do
    with %{} = declared <- declared_unit(c, unit),
         %{} = event <- Enum.find(declared.events, &(&1.name == name)),
         do: Links.at(event)
  end

  defp declared_command(c, unit, name) do
    with %{} = declared <- declared_unit(c, unit),
         %{} = command <- Enum.find(declared.commands, &(&1.name == name)),
         do: Links.at(command)
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
  # half of this library, for an event a unit's lifecycle starts on or moves on (plan
  # DD, P1b, #186): the report reads it, process or not; and for one a process module
  # includes (plan DD, P2d, #213), whose promises and ends are its own events. The
  # unit's own `evolve` does not count; ESDM's aggregate folds its events too.
  defp events_without_consumer(%{model: model} = c, all, included) do
    local =
      Enum.flat_map(model.policies, &List.wrap(&1.handles)) ++
        Enum.flat_map(model.effects, &List.wrap(&1.handles)) ++
        Enum.flat_map(model.process_managers, fn pm ->
          Enum.map(pm.starts_on, & &1.event) ++ Enum.map(pm.on, & &1.event) ++ pm.ends_on
        end) ++
        Enum.flat_map(model.read_models, &List.wrap(&1.projects)) ++
        Enum.flat_map(model.units, fn u -> Enum.map(u.consults, & &1.event) end) ++
        Enum.map(model.publishes, & &1.from) ++
        lifecycle_events(model)

    siblings =
      for %{model: other} <- all,
          %{kind: :contract, from: from, events: events} <- other.consumes,
          from == model.module,
          event <- events,
          do: event

    of_modules = for {contract, event} <- included, contract == model.module, do: event

    consumed = MapSet.new(local ++ siblings ++ of_modules)

    for event <- model.events, not MapSet.member?(consumed, event.name) do
      Finding.new(
        "event-without-consumer",
        "event #{inspect(event.name)} of #{inspect(model.module)} has no consumer: no policy, " <>
          "effect, process manager or read model takes it, no boundary consults it, no contract " <>
          "consumes it, nothing publishes it, no process includes it, and no lifecycle moves on " <>
          "it",
        declared_event(c, event.unit, event.name)
      )
    end
  end

  defp lifecycle_events(model) do
    for unit <- model.units,
        %{} = lifecycle <- [EhOsContract.Lifecycle.of(unit)],
        event <-
          Enum.map(lifecycle.initial, & &1.on) ++ Enum.map(lifecycle.transitions, & &1.event),
        do: event
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

  # A scenario is the contract's executable example of cardinality. More than one
  # issued command proves the policy fans out while the append transaction holds
  # the store's global lock (plan E10); no guessed runtime list limit is needed.
  defp in_transaction_fan_out(%{model: model} = c) do
    for policy <- model.policies,
        policy.delivery == :in_transaction,
        scenario <- model.scenarios,
        scenario.target == %{kind: :policy, name: policy.name},
        length(scenario.issues) > 1 do
      Finding.new(
        "in-transaction-policy-fan-out",
        "policy #{inspect(policy.name)} of #{inspect(model.module)} is delivered " <>
          "`:in_transaction`, and scenario #{inspect(scenario.description)} shows it issuing " <>
          "#{length(scenario.issues)} commands while the global append lock is held; use " <>
          "`delivery: :at_least_once` for fan-out",
        at(c.declarations.policies, policy.name)
      )
    end
    |> Enum.uniq_by(&{&1.rule, &1.at})
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

  # ESDM's `feature-without-scenarios`, per declaration a scenario can target (plan EL2,
  # rule 4 of the prose review): a policy, a process manager or a query no scenario runs, so nothing
  # shows its implementation does what its label says. An effect is left out: its
  # outcome is outside the log, and no scenario can name it (S6).
  defp without_scenario(%{model: model} = c) do
    covered = MapSet.new(model.scenarios, &{&1.target.kind, &1.target.name})

    for {kind, what, declarations, declared} <- [
          {:policy, "policy", model.policies, c.declarations.policies},
          {:process_manager, "process manager", model.process_managers,
           c.declarations.process_managers},
          {:query, "query", model.queries, c.declarations.queries}
        ],
        declaration <- declarations,
        not MapSet.member?(covered, {kind, declaration.name}) do
      Finding.new(
        "reaction-without-scenario",
        "#{what} #{inspect(declaration.name)} of #{inspect(model.module)} has no scenario, so " <>
          "nothing shows its implementation does what #{inspect(declaration.label)} says",
        at(declared, declaration.name)
      )
    end
  end

  # The ladder's first step up (plan EP2): a rule of a policy, a process manager or a
  # query that no scenario of that declaration `illustrates:`, so it is prose alone. An
  # effect's constraint is left out, as `without_scenario/1` leaves out the effect: no
  # scenario runs one (S6), so its prose has no rung above it (the user's choice of 3
  # October 2026). So is a declaration no scenario runs at all, which
  # `without_scenario/1` reports once, rather than once more per rule (the EP2 review).
  defp unillustrated(%{model: model} = c) do
    run = MapSet.new(model.scenarios, &{&1.target.kind, &1.target.name})

    shown =
      MapSet.new(
        for s <- model.scenarios,
            name <- Map.get(s, :illustrates, []),
            do: {s.target.kind, s.target.name, name}
      )

    for {kind, what, declarations, declared} <- [
          {:policy, "policy", model.policies, c.declarations.policies},
          {:process_manager, "process manager", model.process_managers,
           c.declarations.process_managers},
          {:query, "query", model.queries, c.declarations.queries}
        ],
        declaration <- declarations,
        MapSet.member?(run, {kind, declaration.name}),
        {word, rule} <- Rules.Scenarios.illustratable(kind, declaration),
        not MapSet.member?(shown, {kind, declaration.name, rule.name}) do
      Finding.new(
        "prose-without-scenario",
        "#{word} #{inspect(rule.name)} of #{what} #{inspect(declaration.name)} of " <>
          "#{inspect(model.module)} is prose alone: no scenario `illustrates:` it, so nothing " <>
          "shows its implementation keeps #{inspect(rule.label)}",
        rule_at(declared, kind, declaration.name, rule.name)
      )
    end
  end

  # Plan DD, S4: a declared transition no scenario takes. A command's scenario takes it
  # when its `given`, walked as dispatch walks a stream, leaves the unit in `from`, and
  # what it expects moves the unit out of `from` on the transition's event — the graph
  # read by `Lifecycle.tally/2`, as the report reads the log, with the given events
  # moving the status and only the expected ones counted. A scenario with `rejected`
  # expects nothing, so it takes nothing. Left out: a transition on an event no command
  # of the unit emits, which is recorded with no decision for a scenario to run, and a
  # `from` no such command's `from:` admits, which no scenario could start in.
  defp untaken_transitions(%{model: model} = c) do
    for unit <- model.units,
        lifecycle = Lifecycle.of(unit),
        lifecycle != nil,
        commands = Enum.filter(model.commands, &(&1.unit == unit.name)),
        taken = taken(model, unit, lifecycle),
        declared <- declared_transitions(c, unit.name),
        emitting = Enum.filter(commands, &(declared.event in &1.emits)),
        untaken =
          for(
            from <- Enum.uniq(declared.from),
            Enum.any?(emitting, &Lifecycle.admits?(&1, from)),
            not Map.has_key?(taken, {from, declared.event, declared.to}),
            do: from
          ),
        untaken != [] do
      Finding.new(
        "transition-without-scenario",
        "#{unit.kind} #{inspect(unit.name)} of #{inspect(model.module)} moves from " <>
          "#{Enum.map_join(untaken, " and ", &inspect/1)} to #{inspect(declared.to)} on " <>
          "#{inspect(declared.event)}, and no scenario of a command starts there and expects " <>
          "it, so nothing shows the implementation takes that transition",
        Links.at(declared)
      )
    end
  end

  # Every `{from, event, to}` some command's scenario of `unit` takes, as a map's keys.
  defp taken(model, unit, lifecycle) do
    streams =
      for scenario <- model.scenarios,
          scenario.target == %{kind: unit.kind, name: unit.name},
          do:
            Enum.map(scenario.given, &{&1.event, false}) ++
              Enum.map(scenario.expect, &{&1.event, true})

    Lifecycle.tally(lifecycle, streams).taken
  end

  defp declared_transitions(c, unit) do
    case declared_unit(c, unit) do
      %{lifecycle: [lifecycle | _]} -> lifecycle.transitions
      _ -> []
    end
  end

  defp rule_at(declarations, kind, name, rule) do
    with %{} = declaration <- Enum.find(declarations, &(&1.name == name)),
         {_word, found} <-
           Enum.find(
             Rules.Scenarios.illustratable(kind, declaration),
             fn {_word, r} -> r.name == rule end
           ) do
      Links.at(found)
    end
  end

  # --- a whole domain ------------------------------------------------------------

  defp domain(module, contracts, processes) do
    model = hd(contracts).domain
    declared = declared(module)

    Enum.concat([
      orphan_actors(model, declared, contracts, processes),
      orphan_externals(model, declared, contracts),
      uncalled_operations(model, declared, contracts),
      empty_contexts(model, declared, contracts),
      empty_subdomains(model, declared),
      orphan_relations(model, declared, contracts),
      unmapped_references(model, contracts),
      avoided_terms(model, contracts),
      words_without_terms(model, declared, contracts),
      terms_of_other_contexts(model, contracts),
      directions(model, declared, contracts),
      scoped_actors_with_unscoped_commands(model, contracts),
      unchecked_values(model, declared, contracts),
      unlabelled_values(model, declared)
    ])
  end

  # Plan DD, L4 (#326): the owner's view names a value, and each member of its enum, by
  # its label; a member written as a bare atom has none.
  defp unlabelled_values(model, declared) do
    for value <- model.values,
        unlabelled = unlabelled(value),
        unlabelled != [] do
      Finding.new(
        "owner-view-without-label",
        "value #{inspect(value.name)} of #{inspect(model.module)}: #{Enum.join(unlabelled, ", ")} " <>
          "#{if length(unlabelled) == 1, do: "has", else: "have"} no label, so the owner's view " <>
          "names it as the code does",
        at(declared.values, value.name)
      )
    end
  end

  defp unlabelled(value) do
    own = if value.label == nil, do: ["the value"], else: []

    members =
      case value.type do
        {:enum, members} ->
          for member <- members, is_atom(member), do: "member #{inspect(member)}"

        _other ->
          []
      end

    own ++ members
  end

  # A scoped actor has a grant narrowed to rows or units identified by those
  # dimensions. Letting the same actor issue an unscoped command makes that grant
  # unexpectedly application-wide (plan E10).
  defp scoped_actors_with_unscoped_commands(model, contracts) do
    scoped = Map.new(model.actors, &{&1.name, &1.scope})

    for %{model: contract, declarations: declarations} <- contracts,
        command <- contract.commands,
        Map.get(command, :scope) == nil,
        actor <- command.by,
        Map.get(scoped, actor, []) != [] do
      dimensions = scoped |> Map.fetch!(actor) |> Enum.map_join(", ", &inspect/1)

      Finding.new(
        "scoped-actor-with-unscoped-command",
        "actor #{inspect(actor)} of #{inspect(model.module)} has scope #{dimensions}, but command " <>
          "#{inspect(command.name)} of #{inspect(contract.module)} grants it without a `scope`, so " <>
          "the capability is application-wide",
        declared_command(%{declarations: declarations}, command.unit, command.name)
      )
    end
  end

  # A value whose invariants no module checks, in a domain whose contracts have code:
  # dispatch raises on the first value of it (plan EL2b).
  defp unchecked_values(model, declared, contracts) do
    implemented = EhOsContract.Implementations.index(model.module).declarations

    running? =
      Enum.any?(Map.keys(implemented), fn {module, _kind, _name} ->
        Enum.any?(contracts, &(&1.model.module == module))
      end)

    for %{invariants: [_ | _]} = value <- model.values,
        running?,
        not Map.has_key?(implemented, {model.module, :value, value.name}) do
      Finding.new(
        "value-without-implementation",
        "value #{inspect(value.name)} of #{inspect(model.module)} declares invariants and no " <>
          "module checks them, so dispatch raises on every value of it; bind one with " <>
          "`use #{inspect(model.module)}, value: #{inspect(value.name)}`",
        at(declared.values, value.name)
      )
    end
  end

  # The domain's declarations as Spark kept them, with where each was written.
  defp declared(module) do
    entities = Spark.Dsl.Extension.get_entities(module, [:domain])
    of = fn struct -> for %{__struct__: ^struct} = e <- entities, do: e end

    %{
      values: of.(Domain.Dsl.Value),
      entities: of.(Domain.Dsl.Entity),
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
  # module names. A scenario's actor is in a command's `by:` already (S7). A process
  # module of the domain names its `accountable` (plan DD, P2h, #221).
  defp orphan_actors(model, declared, contracts, processes) do
    accountable =
      for module <- processes,
          %{domain: domain, accountable: actor} <- [Model.fetch(module)],
          domain == model.module,
          actor != nil,
          do: actor

    named =
      MapSet.new(
        accountable ++
          for(
            %{model: m} <- contracts,
            actor <-
              Enum.flat_map(m.commands, & &1.by) ++
                Enum.flat_map(m.queries, & &1.by) ++
                Enum.flat_map(m.events, & &1.recorded_by),
            do: actor
          )
      )

    for actor <- model.actors, not MapSet.member?(named, actor.name) do
      Finding.new(
        "orphan-actor",
        "actor #{inspect(actor.name)} of #{inspect(model.module)} is in no command's or query's " <>
          "`by:`, no event's `recorded_by:` and no process's `accountable`, so no contract or " <>
          "process gives it anything to do",
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

  # Plan EP5a: an operation an external declares and no effect names in `calls:`. An
  # external no effect calls at all is `orphan-external-system`'s or simply unused:
  # its operations are reported only once something calls the system.
  defp uncalled_operations(model, declared, contracts) do
    calling =
      MapSet.new(for %{model: m} <- contracts, effect <- m.effects, x <- effect.calls, do: x)

    called =
      MapSet.new(
        for %{model: m} <- contracts,
            effect <- m.effects,
            operation <- Map.get(effect, :operations, []),
            do: {operation.external, operation.name}
      )

    for external <- model.externals,
        MapSet.member?(calling, external.name),
        operation <- Map.get(external, :operations, []),
        not MapSet.member?(called, {external.name, operation.name}) do
      Finding.new(
        "operation-never-called",
        "operation #{inspect(operation.name)} of external #{inspect(external.name)} of " <>
          "#{inspect(model.module)} is called by no effect: no `calls: " <>
          "#{inspect({external.name, operation.name})}`",
        operation_at(declared.externals, external.name, operation.name)
      )
    end
  end

  defp operation_at(externals, external, name) do
    with %{operations: operations} <- Enum.find(externals, &(&1.name == external)),
         %{} = operation <- Enum.find(operations, &(&1.name == name)) do
      Links.at(operation)
    else
      _ -> at(externals, external)
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
      MapSet.new(Enum.map(ContextMap.crossings(model, contracts), & &1.pair) ++ external_uses)

    for {relation, index} <- Enum.with_index(model.relations),
        pair = relation |> Domain.Build.endpoints() |> MapSet.new(),
        not MapSet.member?(crossing, pair) do
      [a, b] = Domain.Build.endpoints(relation)

      Finding.new(
        "orphan-context-mapping",
        "relation #{inspect(relation.type)} between #{inspect(a)} and #{inspect(b)} in " <>
          "#{inspect(model.module)} is crossed by no reference: no contract of one consumes a " <>
          "contract of the other or names an entity or a unit it owns, and none uses an external it " <>
          "ends at",
        declared.relations |> Enum.at(index) |> then(&(&1 && Links.at(&1)))
      )
    end
  end

  # ESDM's `cross-bounded-context-reference-without-mapping`: a contract that consumes
  # a contract of another context, or names an entity or a unit another context owns, with no
  # relation declared between the two contexts. One finding per reference.
  defp unmapped_references(model, contracts) do
    mapped = MapSet.new(model.relations, &MapSet.new(Domain.Build.endpoints(&1)))

    for %{pair: pair, contract: contract, what: what, at: at} <-
          ContextMap.crossings(model, contracts),
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

  # The library's own (plan EL2, rule 2 of the prose review): a label of a contract that uses a
  # word its context's glossary says to avoid. Whole words, any case; the words a
  # translation avoids belong to another language, which labels are not written in.
  defp avoided_terms(model, contracts) do
    # One pattern per word, compiled once; a blank word would match between any two
    # characters that are not letters.
    avoided =
      Map.new(model.contexts, fn context ->
        {context.name,
         for(
           t <- context.terms,
           a <- t.avoid,
           String.trim(a.text) != "",
           do: {a.text, t.text, word_pattern(a.text), word_pattern(t.text)}
         )}
      end)

    for c <- contracts,
        words = Map.get(avoided, c.model.context, []),
        words != [],
        {label, at} <- labelled(c.declarations),
        {word, term, pattern, term_pattern} <- words,
        # The term itself may contain the word it replaces ("Zaliczka na podatek"
        # avoiding "Zaliczka"): what the label says as the term is not the word.
        String.match?(String.replace(label, term_pattern, " "), pattern),
        uniq: true do
      Finding.new(
        "label-with-avoided-term",
        "#{inspect(c.module)}: the label #{inspect(label)} says #{inspect(word)}, which " <>
          "context #{inspect(c.model.context)} avoids in favour of #{inspect(term)}",
        at
      )
    end
  end

  # Plan DD, L1 (#269): the glossary joined to the code. Only the names of things —
  # units, read models, fields — are read: a command's or an event's name is a verb
  # phrase, its verb inflected ("closed") where the term is not ("Close"), and the
  # noun in it names a unit or a field already read. Words of one or two letters
  # (`id`, `at`, `by`) are the library's and the language's, not the business's.
  @shown_words 10

  defp words_without_terms(model, declared, contracts) do
    for context <- model.contexts,
        terms = EhOsContract.CodeWords.terms(model, context.name),
        tally = untermed(contracts, context.name, terms),
        tally != [] do
      {shown, rest} = Enum.split(tally, @shown_words)
      listed = Enum.map_join(shown, ", ", fn {word, count} -> "#{word} (#{count})" end)
      more = if rest == [], do: "", else: " and #{length(rest)} more"

      Finding.new(
        "word-without-term",
        "context #{inspect(context.name)} of #{inspect(model.module)} names things with words " <>
          "no term of its glossary has in #{inspect(EhOsContract.CodeWords.code_language(model))}, " <>
          "most used first: " <>
          listed <> more,
        at(declared.contexts, context.name)
      )
    end
  end

  # Each word of the context's names of things that no term covers, with how many
  # distinct names use it, most used first and then alphabetically.
  defp untermed(contracts, context, terms) do
    names =
      for c <- contracts,
          c.model.context == context,
          %{thing?: true} = name <- EhOsContract.CodeWords.names(c),
          uniq: true,
          do: name.words

    names
    |> Enum.flat_map(fn words ->
      covered = own_coverage(terms, words)

      for {word, position} <- Enum.with_index(words),
          not MapSet.member?(covered, position),
          String.length(word) > 2,
          uniq: true,
          do: word
    end)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {word, count} -> {-count, word} end)
  end

  # A name of a thing that says a term another context has and its own does not: a
  # word of another context's language in this one's code. A word the context's own
  # terms cover is its own, as "Member" is of both lending contexts that have it, and
  # so is one inside a longer term of its own ("Member card"). A field named like the
  # identity of a unit of another context refers to that unit, as a field typed
  # `{:id, entity}` refers to an entity, and is not read. One finding per name of a
  # contract, at its first declaration.
  defp terms_of_other_contexts(model, contracts) do
    by_context = Map.new(model.contexts, &{&1.name, EhOsContract.CodeWords.terms(model, &1.name)})

    identities =
      for c <- contracts, id <- EhOsContract.CodeWords.identities(c), do: {id, c.model.context}

    for c <- contracts,
        own = Map.get(by_context, c.model.context, []),
        names = EhOsContract.CodeWords.names(c),
        {{kind, name}, [first | _] = all} <-
          Enum.group_by(Enum.filter(names, & &1.thing?), &{&1.kind, &1.name}),
        not (kind == :field and reference?(identities, name, c.model.context)),
        covered = own_coverage(own, first.words),
        {sequence, others} <- elsewhere(by_context, c.model.context, first.words),
        not MapSet.subset?(EhOsContract.CodeWords.covers(first.words, sequence), covered) do
      where =
        Enum.map_join(others, " and ", fn {context, term} ->
          "#{inspect(term)} of #{inspect(context)}"
        end)

      what =
        case all do
          [_one] -> first.what
          _many -> "#{kind} #{inspect(name)} (in #{length(all)} declarations)"
        end

      Finding.new(
        "term-of-another-context",
        "#{inspect(c.module)}: #{what} says #{inspect(Enum.join(sequence, " "))}, the " <>
          "word in code of #{where}, which context #{inspect(c.model.context)} has no term for",
        first.at
      )
    end
  end

  defp reference?(identities, name, own) do
    Enum.any?(identities, fn {id, context} -> id == name and context != own end)
  end

  defp own_coverage(own, words) do
    Enum.reduce(own, MapSet.new(), fn {_term, sequence}, covered ->
      MapSet.union(covered, EhOsContract.CodeWords.covers(words, sequence))
    end)
  end

  # The words of other contexts' terms that stand in `words`, each with the contexts
  # and terms that have it.
  defp elsewhere(by_context, own, words) do
    for {context, terms} <- by_context,
        context != own,
        {term, sequence} <- terms,
        EhOsContract.CodeWords.contains?(words, sequence) do
      {sequence, {context, term}}
    end
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {sequence, others} -> {sequence, Enum.sort(others)} end)
    |> Enum.sort()
  end

  defp word_pattern(word),
    do: Regex.compile!("(?<![\\p{L}\\p{N}])#{Regex.escape(word)}(?![\\p{L}\\p{N}])", "iu")

  # Every label of a contract's declarations, at any depth, with where it was written:
  # a declaration's own, and the labels of an enum's members, at the field of that type.
  defp labelled(%{__struct__: _} = struct) do
    own = if is_binary(Map.get(struct, :label)), do: [{struct.label, Links.at(struct)}], else: []

    members =
      case Map.get(struct, :type) do
        {:enum, members} when is_list(members) ->
          for {_value, label} <- members, is_binary(label), do: {label, Links.at(struct)}

        _other ->
          []
      end

    own ++
      members ++
      (struct
       |> Map.from_struct()
       |> Map.delete(:__spark_metadata__)
       |> Map.values()
       |> labelled())
  end

  defp labelled(%{} = map), do: map |> Map.values() |> labelled()
  defp labelled(list) when is_list(list), do: Enum.flat_map(list, &labelled/1)
  defp labelled(_other), do: []

  # The library's own (plan EL2, rule 3 of the prose review): an external's
  # `direction:` and how the model uses it. A field or an entity `issued_by:` a system, and an actor
  # `backed_by:` one, bring what it says into this application, so a system this
  # application only sends to (`:outbound`) can do neither. A call says nothing: an
  # effect calls to send, and to fetch what flows in.
  defp directions(model, declared, contracts) do
    direction = Map.new(model.externals, &{&1.name, &1.direction})

    domain_fields =
      for owner <- declared.values ++ declared.entities, field <- owner.fields, do: field

    contract_fields =
      for c <- contracts,
          {_where, fields, _injected, _kind} <-
            EhOsContract.Contract.Rules.Fields.structs(c.declarations),
          field <- fields,
          do: field

    # Plan N1: an entity's identity is injected, so its issuer is the entity's option.
    issuers =
      for(field <- domain_fields ++ contract_fields, do: {"field", field.name, field}) ++
        for entity <- declared.entities,
            do: {"entity #{inspect(entity.name)}, identity", entity.identity, entity}

    issued =
      for {what, name, at} <- issuers,
          external = Map.get(at, :issued_by),
          direction[external] == :outbound do
        Finding.new(
          "external-direction-contradicted",
          "#{what} #{inspect(name)} is issued_by: #{inspect(external)}, which " <>
            "#{inspect(model.module)} declares `direction: :outbound`: it only receives from this " <>
            "application",
          Links.at(at)
        )
      end

    backed =
      for actor <- declared.actors,
          direction[actor.backed_by] == :outbound do
        Finding.new(
          "external-direction-contradicted",
          "actor #{inspect(actor.name)} is backed_by: #{inspect(actor.backed_by)}, which " <>
            "#{inspect(model.module)} declares `direction: :outbound`: it only receives from this " <>
            "application, so nothing of it acts here",
          Links.at(actor)
        )
      end

    issued ++ backed
  end

  # The externals a contract reaches: what its effects call, what its events depend on,
  # what issues its fields' values, and what stands behind the actors it names — in a
  # command's or a query's `by:`, an event's `recorded_by:`. A process module's
  # `accountable` is not among them: the module belongs to no context, and a use here
  # crosses a relation of the contract's context.
  defp externals_used(contract, domain) do
    backing = Map.new(domain.actors, &{&1.name, &1.backed_by})

    actors =
      Enum.flat_map(contract.commands, & &1.by) ++
        Enum.flat_map(contract.queries, & &1.by) ++
        Enum.flat_map(contract.events, & &1.recorded_by)

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
end
