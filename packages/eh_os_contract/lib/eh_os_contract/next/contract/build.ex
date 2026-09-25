defmodule EhOsContract.Next.Contract.Build do
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
  event declared in a stage group carries that `stage`.

  **Identity is injected** (v2 §4.2): a unit's identity fields, typed `:id`, come
  first in its state, in each of its commands and in each of its events, as if they
  had been declared there.

  **The digest does not see declaration order.** Every collection of declarations
  is a set to it, nested ones included, and so is every value with set meaning
  (`by`, `emits`, `handles`, …). What keeps its order is what has one: `identity`
  and `correlate`, the process's stages, and a scenario's givens and expectations.
  Each declaration also has its own digest, keyed `"<kind>:<name>"`; scenarios share
  one, `"scenario:*"`, since nothing names them.
  """

  use Spark.Dsl.Transformer

  alias EhOsContract.Digest
  alias EhOsContract.Next.Contract.Dsl
  alias Spark.Dsl.Transformer

  @impl true
  def transform(dsl) do
    model = model(dsl)

    {:ok,
     Transformer.eval(
       dsl,
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
    %{domain: domain, context: context} = Transformer.get_persisted(dsl, :eh_os_contract_contract)
    entities = Transformer.get_entities(dsl, [:contract])
    process = Enum.find(entities, &match?(%Dsl.ProcessDeclaration{}, &1))
    prefix = process && process.name

    units = of(entities, Dsl.Unit)

    collections = %{
      units: Enum.map(units, &unit/1),
      commands: for(u <- units, c <- u.commands, do: command(u, c)),
      events: for(u <- units, {stage, e} <- events(u), do: event(u, stage, e, prefix)),
      policies: entities |> of(Dsl.Policy) |> Enum.map(&plain/1),
      effects: entities |> of(Dsl.Effect) |> Enum.map(&plain/1),
      process_managers: entities |> of(Dsl.ProcessManager) |> Enum.map(&process_manager/1),
      read_models: entities |> of(Dsl.ReadModel) |> Enum.map(&plain/1),
      queries: entities |> of(Dsl.Query) |> Enum.map(&plain/1),
      consumes: entities |> of(Dsl.Consumes) |> Enum.map(&consumes/1),
      publishes: entities |> of(Dsl.Publish) |> Enum.map(&plain/1),
      scenarios: entities |> of(Dsl.Scenario) |> Enum.map(&scenario/1)
    }

    own = %{domain: domain, context: context}
    process = process && process(process)

    Map.merge(collections, %{
      format: 1,
      kind: :contract,
      module: Transformer.get_persisted(dsl, :module),
      domain: domain,
      context: context,
      process: process,
      capabilities: capabilities(collections),
      version: version(own, process, collections),
      digests: digests(own, process, collections)
    })
  end

  defp of(entities, struct), do: for(%{__struct__: ^struct} = e <- entities, do: e)

  # --- declarations as data --------------------------------------------------------

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
  end

  defp command(unit, command) do
    command
    |> plain()
    |> Map.merge(%{unit: unit.name, fields: identity_fields(unit) ++ plain(command.fields)})
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

  defp identity_fields(unit) do
    for name <- unit.identity do
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

  defp process_manager(pm) do
    pm
    |> plain()
    |> Map.merge(%{
      state: %{fields: state_fields(pm.state)},
      timers:
        Enum.map(pm.timers, &(&1 |> plain() |> Map.update!(:wait, fn w -> duration(w) end))),
      ends_on: Enum.map(pm.ends_on, & &1.event)
    })
  end

  # Two shapes under one word: a sibling contract's events, by module, or another
  # application's published event, by name, with the fields this contract reads.
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
      promises: for(p <- process.promises, do: p |> plain() |> Map.update!(:within, &duration/1))
    }
  end

  defp timed([], _key), do: nil

  defp timed([declaration | _], key),
    do: declaration |> Map.fetch!(key) |> duration() |> put_unverified(declaration.unverified)

  defp put_unverified(%{} = duration, unverified), do: Map.put(duration, :unverified, unverified)
  defp put_unverified(other, _unverified), do: other

  defp scenario(scenario) do
    %{
      description: scenario.description,
      scope: scenario.scope,
      actor: scenario.actor,
      given: plain(scenario.given),
      trigger:
        case scenario.trigger do
          [trigger | _] -> plain(trigger)
          [] -> nil
        end,
      expect: plain(scenario.expect),
      rejected: scenario.rejected,
      issues: plain(scenario.issues),
      sets: Enum.map(scenario.sets, & &1.timer),
      cancels: Enum.map(scenario.cancels, & &1.timer),
      ended: scenario.ended
    }
  end

  # `{24, :hour}` as data. Anything else is left as written, for the rules to refuse.
  defp duration({amount, unit}) when is_integer(amount) and is_atom(unit),
    do: %{amount: amount, unit: unit}

  defp duration(other), do: other

  # --- capabilities ----------------------------------------------------------------

  # What each actor may do, derived from `by:` and `recorded_by:`, never written as a
  # separate list (v2 §4.6, D10).
  defp capabilities(collections) do
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
    publishes: :publish
  ]

  defp version(own, process, collections) do
    Digest.hash_groups(
      [contract: [own], process: List.wrap(process && digest_form(process))] ++
        for({key, _} <- @collections, do: {key, Enum.map(collections[key], &digest_form/1)}) ++
        [
          consumes: Enum.map(consumed(collections.consumes), &digest_form/1),
          scenarios: Enum.map(collections.scenarios, &digest_form/1)
        ]
    )
  end

  defp digests(own, process, collections) do
    declarations =
      for {key, kind} <- @collections, declaration <- collections[key] do
        {"#{kind}:#{declaration.name}", Digest.hash(digest_form(declaration))}
      end

    consumed =
      for declaration <- consumed(collections.consumes) do
        {"consumes:#{declaration.as}", Digest.hash(digest_form(declaration))}
      end

    process = if process, do: [{"process:#{process.name}", Digest.hash(digest_form(process))}]

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
           idempotent_on)a

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
  defp plain(%{__struct__: _} = struct) do
    struct
    |> Map.from_struct()
    |> Map.delete(:__spark_metadata__)
    |> Map.new(fn {key, value} -> {key, plain(value)} end)
  end

  defp plain(list) when is_list(list), do: Enum.map(list, &plain/1)
  defp plain(other), do: other
end
