defmodule EhOsContract.Contract.Build do
  @moduledoc """
  Builds a v2 contract's model and compiles it into the module as
  `__eh_os_contract_model__/0` (v2 §9).

  Runs last, after every rule, so the model is only built from a contract that is
  well formed. It is plain data: maps, lists, atoms, strings, integers and booleans,
  with durations as `%{amount: 24, unit: :hour}`. Spark's structs and source
  annotations stay behind.

  **Collections keep declaration order**, because readers print in it (E1's
  correction to v2 §9). A unit's commands and events are lifted to the top level,
  each naming its `unit`, so a reader asking for an event does not walk units; an
  event declared in a stage group carries that `stage`. `grants` says, per actor,
  which commands it may issue, queries it may ask and events it may record.

  **Identity is injected** (v2 §4.2): a unit's identity fields, typed `:id`, come
  first in its state, in each of its commands and in each of its events, as if they
  had been declared there. A process manager's `correlate` fields come first in its
  state the same way, unless the state declares them.

  **The digest does not see declaration order.** Every collection of declarations
  is a set to it, nested ones included, and so is every value with set meaning
  (`by`, `emits`, `handles`, …). What keeps its order is what has one: `identity`
  and `correlate`, the process's stages, and a scenario's givens and expectations.
  Each declaration also has its own digest, keyed `"<kind>:<name>"`; scenarios share
  one, `"scenario:*"`, since nothing names them.
  """

  use Spark.Dsl.Transformer

  alias EhOsContract.Digest
  alias EhOsContract.Contract.{Dsl, Rules}
  alias Spark.Dsl.Transformer

  @impl true
  def transform(dsl) do
    model = model(dsl)

    {:ok,
     dsl
     |> Transformer.persist(:eh_os_contract_model, model)
     |> Transformer.eval(
       [],
       quote do
         @doc false
         def __eh_os_contract_model__, do: unquote(Macro.escape(model))
       end
     )}
  end

  @doc false
  @spec model(map()) :: map()
  def model(dsl) do
    %{domain: domain, context: context} =
      persisted = Transformer.get_persisted(dsl, :eh_os_contract_contract)

    entities = Transformer.get_entities(dsl, [:contract])
    process = Enum.find(entities, &match?(%Dsl.ProcessDeclaration{}, &1))
    prefix = process && process.name

    units = of(entities, Dsl.Unit)
    declarations = Rules.declarations(dsl)

    events = for u <- units, {stage, e} <- events(u), do: event(u, stage, e, prefix)

    collections = %{
      units: Enum.map(units, &unit/1),
      commands: for(u <- units, c <- u.commands, do: command(u, c)),
      events: events,
      policies: entities |> of(Dsl.Policy) |> Enum.map(&(&1 |> reaction() |> delivery())),
      effects: entities |> of(Dsl.Effect) |> Enum.map(&(&1 |> reaction() |> operations())),
      process_managers:
        entities |> of(Dsl.ProcessManager) |> Enum.map(&process_manager(&1, events)),
      read_models: entities |> of(Dsl.ReadModel) |> Enum.map(&(&1 |> plain() |> delivery())),
      queries:
        entities |> of(Dsl.Query) |> Enum.map(&(&1 |> plain() |> without_empty(:constraints))),
      domain_services: entities |> of(Dsl.DomainService) |> Enum.map(&plain/1),
      consumes: entities |> of(Dsl.Consumes) |> Enum.map(&consumes/1),
      publishes: entities |> of(Dsl.Publish) |> Enum.map(&plain/1),
      scenarios: entities |> of(Dsl.Scenario) |> Enum.map(&scenario(&1, declarations))
    }

    own = %{domain: domain, context: context}
    process = process && process(process)

    collections
    |> Map.merge(%{
      format: 1,
      kind: :contract,
      module: Transformer.get_persisted(dsl, :module),
      domain: domain,
      context: context,
      process: process,
      grants: grants(collections),
      version: version(own, process, collections),
      digests: digests(own, process, collections)
    })
    |> with_id(Map.get(persisted, :id))
  end

  # Plan DD, ID1: the contract's `id:`, kept only where it names one, and outside the
  # version and the declarations' digests: naming a contract changes nothing it decides
  # or records. The exported model carries it, so the export's document digest moves.
  defp with_id(model, nil), do: model
  defp with_id(model, id), do: Map.put(model, :id, id)

  defp of(entities, struct), do: for(%{__struct__: ^struct} = e <- entities, do: e)

  # A key a later stage added, kept out of the model where it is empty so no
  # declaration written without it moves its digest (plan EL2's constraints).
  defp without_empty(map, key),
    do: if(Map.get(map, key) == [], do: Map.delete(map, key), else: map)

  # --- declarations as data --------------------------------------------------------

  defp reaction(declaration),
    do: declaration |> plain() |> without_empty(:constraints) |> idempotency()

  # Plan DD, X1: a policy or a read model left without `delivery` runs inside the
  # transaction, as it always has, so no contract written without it moves its digest.
  # The DSL leaves it `nil` so that X10 can tell a declared one from a default.
  defp delivery(%{delivery: nil} = reaction), do: %{reaction | delivery: :in_transaction}
  defp delivery(reaction), do: reaction

  # Plan EP5a: `calls` keeps the systems an effect calls, as every reader has always
  # read it, and the operations it names go under their own key, only where it names
  # some, so no effect written without one moves its digest.
  defp operations(%{calls: calls} = effect) do
    case Enum.uniq(for {external, operation} <- calls, do: %{external: external, name: operation}) do
      [] ->
        effect

      named ->
        systems =
          Enum.map(calls, fn
            {external, _} -> external
            external -> external
          end)

        Map.merge(effect, %{calls: Enum.uniq(systems), operations: named})
    end
  end

  # `[key: :event_id, owner: :self]` as a map, as every other pair of the model is
  # (plan EP4).
  defp idempotency(%{idempotency: [_ | _] = idempotency} = reaction),
    do: %{reaction | idempotency: Map.new(idempotency)}

  defp idempotency(reaction), do: reaction

  defp unit(%Dsl.Unit{} = unit) do
    %{
      name: unit.name,
      kind: unit.kind,
      label: unit.label,
      source: unit.source,
      identity: unit.identity,
      consults: plain(unit.consults),
      state: %{fields: identity_fields(unit) ++ state_fields(unit.state)},
      invariants: plain(unit.invariants)
    }
    # Kept only where it is set, so no other unit's digest moves (plan EM3).
    |> then(&if unit.generated, do: Map.put(&1, :generated, unit.generated), else: &1)
    # The same for a lifecycle (plan LC1).
    |> then(fn built ->
      case unit.lifecycle do
        [lifecycle | _] -> Map.put(built, :lifecycle, lifecycle(lifecycle))
        [] -> built
      end
    end)
  end

  # One transition per status it leaves, so a reader asking where an event moves the
  # aggregate from a status finds one entry.
  defp lifecycle(%Dsl.Lifecycle{} = lifecycle) do
    %{
      statuses: plain(lifecycle.statuses),
      initial: for(i <- lifecycle.initials, do: %{status: i.status, on: i.on, source: i.source}),
      transitions:
        for t <- lifecycle.transitions, from <- Enum.uniq(t.from) do
          %{from: from, event: t.event, to: t.to, source: t.source}
        end
    }
  end

  # A command that creates its aggregate arrives without the generated identity, so
  # the identity is optional in it (plan EM3). `creates` is kept only where it is
  # true, so no other command's digest moves.
  defp command(unit, command) do
    identity =
      for field <- identity_fields(unit),
          do: if(command.creates, do: %{field | optional: true}, else: field)

    command
    |> plain()
    |> then(&if command.creates, do: &1, else: Map.delete(&1, :creates))
    # Kept only where it is set, for the same reason (plan E9c).
    |> then(&if command.scope, do: &1, else: Map.delete(&1, :scope))
    # And for a lifecycle's precondition (plan LC1).
    |> then(fn built ->
      if command.from == [],
        do: Map.drop(built, [:from, :or_rejects]),
        else: %{built | from: Enum.uniq(command.from)}
    end)
    |> without_empty(:constraints)
    |> Map.merge(%{unit: unit.name, fields: identity ++ plain(command.fields)})
  end

  # A unit's events, each with the stage group it sits in: `nil` outside one.
  defp events(unit) do
    for(e <- unit.events, do: {nil, e}) ++
      for stage <- unit.stages, e <- stage.events, do: {stage.name, e}
  end

  defp event(unit, stage, event, prefix) do
    event
    |> plain()
    |> Map.merge(%{
      unit: unit.name,
      type: prefix && "#{prefix}.#{event.name}",
      stage: stage,
      fields: identity_fields(unit) ++ plain(event.fields)
    })
  end

  defp identity_fields(unit), do: id_fields(unit.identity)

  defp id_fields(names) do
    for name <- names do
      %{
        name: name,
        type: :id,
        optional: false,
        label: nil,
        personal: nil,
        subject: nil,
        default: nil
      }
    end
  end

  defp state_fields(states), do: Enum.flat_map(states, &plain(&1.fields))

  # A run is told by its correlation, so a process manager's state starts with those
  # fields, as a unit's starts with its identity, unless the state declares them. Each
  # has the type a local event gives the field; one only consumed events carry is an
  # :id, since their fields are the sibling's, which a contract does not compile against.
  defp process_manager(pm, events) do
    declared = state_fields(pm.state)
    names = MapSet.new(declared, & &1.name)

    correlation =
      for f <- id_fields(pm.correlate), not MapSet.member?(names, f.name) do
        type =
          Enum.find_value(
            events,
            :id,
            &Enum.find_value(&1.fields, fn e -> e.name == f.name && e.type end)
          )

        %{f | type: type}
      end

    pm
    |> plain()
    |> idempotency()
    |> Map.merge(%{
      state: %{fields: correlation ++ declared},
      timers:
        Enum.map(pm.timers, &(&1 |> plain() |> Map.update!(:wait, fn w -> duration(w) end))),
      ends_on: Enum.map(pm.ends_on, & &1.event)
    })
    # Plan EP2: kept only where declared, so no other manager's digest moves.
    |> without_empty(:constraints)
    |> without_empty(:invariants)
  end

  # Two words, one struct (plan N2): `consumes` a sibling contract's events, by module,
  # or `subscribe` to another application's published event, by name, with the fields
  # this contract reads.
  defp consumes(%Dsl.Consumes{from: from} = consumes) when is_binary(from) do
    %{
      kind: :published,
      from: from,
      as: consumes.as,
      events: [],
      renames: %{},
      fields: plain(consumes.fields)
    }
  end

  defp consumes(%Dsl.Consumes{} = consumes) do
    %{
      kind: :contract,
      from: consumes.from,
      as: nil,
      events: consumes.events,
      renames: Map.new(List.wrap(consumes.as)),
      fields: []
    }
  end

  defp process(process) do
    includes =
      for(i <- process.includes, do: Map.put(plain(i), :stage, nil)) ++
        for stage <- process.stages,
            i <- stage.includes,
            do: Map.put(plain(i), :stage, stage.name)

    %{
      name: process.name,
      label: process.label,
      correlate: process.correlate,
      accountable: process.accountable,
      stages: for(s <- process.stages, do: %{name: s.name, label: s.label}),
      includes: includes,
      cadence: timed(process.cadence, :every),
      deadline: timed(process.deadline, :within),
      promises: for(p <- process.promises, do: p |> plain() |> Map.update!(:within, &duration/1)),
      source: process.source
    }
  end

  defp timed([], _key), do: nil

  defp timed([declaration | _], key),
    do: declaration |> Map.fetch!(key) |> duration() |> put_unverified(declaration.unverified)

  defp put_unverified(%{} = duration, unverified), do: Map.put(duration, :unverified, unverified)
  defp put_unverified(other, _unverified), do: other

  # One trigger, which S1 has made sure of, and the declaration it resolves to. A
  # query's scenario also has `answers`, its rows as a list; the key is left out of
  # every other scenario, so adding the word moved no contract's version.
  defp scenario(%Dsl.Scenario{trigger: [trigger]} = scenario, declarations) do
    {kind, target} = Rules.Scenarios.target(scenario, declarations)

    answers =
      case scenario.answers do
        [%Dsl.Answers{rows: rows}] when kind == :query -> %{answers: List.wrap(rows)}
        _ -> %{}
      end

    # Plan EP2: the rules it shows, kept only where it names some, for the same reason.
    illustrates =
      if scenario.illustrates == [], do: %{}, else: %{illustrates: scenario.illustrates}

    # Plan EP4: a process manager's state after the trigger, where the scenario says it.
    state =
      case scenario.state do
        [%Dsl.ExpectedState{data: data}] when kind == :process_manager -> %{state: data}
        _ -> %{}
      end

    answers
    |> Map.merge(illustrates)
    |> Map.merge(state)
    |> Map.merge(%{
      description: scenario.description,
      target: %{kind: kind, name: target.name},
      actor: scenario.actor,
      given: plain(scenario.given),
      trigger: plain(trigger),
      expect: plain(scenario.expect),
      rejected: scenario.rejected,
      issues: plain(scenario.issues),
      sets: Enum.map(scenario.sets, & &1.timer),
      cancels: Enum.map(scenario.cancels, & &1.timer),
      ended: scenario.ended
    })
  end

  # `{24, :hour}` as data. Anything else is left as written, for the rules to refuse.
  defp duration({amount, unit}) when is_integer(amount) and is_atom(unit),
    do: %{amount: amount, unit: unit}

  defp duration(other), do: other

  # --- grants ----------------------------------------------------------------------

  # What each actor may do, derived from `by:` and `recorded_by:`, never written as a
  # separate list (v2 §4.6, D10). Keyed by the actor's local name: the names EHOS
  # reads, `<domain>.<command>`, need the domain's `name:`, which a contract does not
  # compile against, so `EhOsContract.Model.capabilities/1` derives them (D14).
  defp grants(collections) do
    grants =
      for(c <- collections.commands, actor <- c.by, do: {actor, :commands, c.name}) ++
        for(q <- collections.queries, actor <- q.by, do: {actor, :queries, q.name}) ++
        for e <- collections.events, actor <- e.recorded_by, do: {actor, :records, e.name}

    grants
    |> Enum.group_by(&elem(&1, 0))
    |> Map.new(fn {actor, grants} ->
      by_kind = Enum.group_by(grants, &elem(&1, 1), &elem(&1, 2))

      {actor,
       Map.new([:commands, :queries, :records], fn kind ->
         {kind, by_kind |> Map.get(kind, []) |> Enum.uniq() |> Enum.sort()}
       end)}
    end)
  end

  # --- the digest ------------------------------------------------------------------

  @collections [
    units: :unit,
    commands: :command,
    events: :event,
    policies: :policy,
    effects: :effect,
    process_managers: :process_manager,
    read_models: :read_model,
    queries: :query,
    publishes: :publish,
    domain_services: :domain_service
  ]

  # Kinds that came after the first contracts were digested: a contract that declares
  # none of one hashes as it did before the kind existed, so adding a kind to the
  # library moves no contract's version.
  @later [:domain_services]

  # Kinds that took `source:` after the first contracts were digested (plan EP1), the
  # process and a process manager's timers among them: a `nil` one is left out of the
  # digest, so no declaration written without it moves. The model keeps the key, `nil`
  # or not, as it does for every other kind, so a reader needs no second shape.
  @sourced_later [:policies, :effects, :process_managers, :read_models, :queries]

  defp digested(key, declaration) when key in @sourced_later, do: unsourced(declaration)
  defp digested(_key, declaration), do: declaration

  defp unsourced(%{timers: timers} = manager),
    do: %{without_nil_source(manager) | timers: Enum.map(timers, &without_nil_source/1)}

  defp unsourced(declaration), do: without_nil_source(declaration)

  defp without_nil_source(%{source: nil} = declaration), do: Map.delete(declaration, :source)
  defp without_nil_source(declaration), do: declaration

  defp version(own, process, collections) do
    Digest.hash_groups(
      [contract: [own], process: List.wrap(process && digest_form(unsourced(process)))] ++
        for(
          {key, _} <- @collections,
          key not in @later or collections[key] != [],
          do: {key, Enum.map(collections[key], &digest_form(digested(key, &1)))}
        ) ++
        [
          consumes: Enum.map(consumed(collections.consumes), &digest_form/1),
          scenarios: Enum.map(collections.scenarios, &digest_form/1)
        ]
    )
  end

  defp digests(own, process, collections) do
    declarations =
      for {key, kind} <- @collections, declaration <- collections[key] do
        {"#{kind}:#{declaration.name}", Digest.hash(digest_form(digested(key, declaration)))}
      end

    consumed =
      for declaration <- consumed(collections.consumes) do
        {"consumes:#{declaration.as}", Digest.hash(digest_form(declaration))}
      end

    process =
      if process,
        do: [{"process:#{process.name}", Digest.hash(digest_form(unsourced(process)))}]

    scenarios =
      if collections.scenarios != [],
        do: [{"scenario:*", Digest.hash(Enum.map(collections.scenarios, &digest_form/1))}]

    Map.new(
      [{"contract", Digest.hash(own)}] ++
        declarations ++ consumed ++ List.wrap(process) ++ List.wrap(scenarios)
    )
  end

  # One declaration per consumed event, under the name it has in this contract: a
  # sibling's event under its rename, a published event under its `as:`.
  defp consumed(consumes) do
    Enum.flat_map(consumes, fn
      %{kind: :published} = published ->
        [published]

      %{kind: :contract} = sibling ->
        for event <- sibling.events do
          %{from: sibling.from, event: event, as: Map.get(sibling.renames, event, event)}
        end
    end)
  end

  # Lists of declarations and values with set meaning are sorted; `identity`,
  # `correlate`, stages, givens and expectations keep their order.
  @sets ~w(fields params invariants consults starts_on on timers ends_on includes promises
           by emits rejects handles issues calls projects recorded_by match sets cancels events
           idempotent_on answers functions rules constraints illustrates operations statuses from
           initial transitions)a

  defp digest_form(%{} = declaration) do
    Map.new(declaration, fn
      {key, list} when key in @sets and is_list(list) ->
        {key, list |> Enum.map(&digest_form/1) |> Enum.sort_by(&Digest.canonical/1)}

      {key, %{} = nested} ->
        {key, digest_form(nested)}

      other ->
        other
    end)
  end

  defp digest_form(other), do: other

  # A Spark struct becomes a plain map, recursively, without the struct tag and
  # without the source annotation.
  # Plan T1: `supplied_by` only where a field sets it, so no field written without it
  # moves its contract's digest.
  defp plain(%Dsl.Field{supplied_by: nil} = field),
    do: field |> plain_struct() |> Map.delete(:supplied_by)

  defp plain(%{__struct__: _} = struct), do: plain_struct(struct)

  defp plain(list) when is_list(list), do: Enum.map(list, &plain/1)
  defp plain(other), do: other

  defp plain_struct(struct) do
    struct
    |> Map.from_struct()
    |> Map.delete(:__spark_metadata__)
    |> Map.new(fn {key, value} -> {key, plain(value)} end)
    |> EhOsContract.Domain.Build.reference()
  end
end
