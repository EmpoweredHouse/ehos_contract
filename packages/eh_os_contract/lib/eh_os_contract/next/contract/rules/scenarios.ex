defmodule EhOsContract.Next.Contract.Rules.Scenarios do
  @moduledoc """
  S1–S8 of v2 §6: scenarios, the examples a process owner reads.

  - **S1.** A scenario has exactly one trigger — `command`, `on` or `query` — and
    it resolves to the declaration that answers it. A command belongs to one unit;
    an event may be handled by several reactions, and then `scope:` names the one.
  - **S2.** `given` events are ones the target keeps its state from: a unit's own
    events, and for a boundary also the events it consults; a process manager's
    triggers. A policy keeps no state, so it takes no `given`.
  - **S3.** Data names declared fields only. `given` and the trigger supply every
    required field, except the target's identity, which a scenario fills in itself:
    it is one stream. A value of a built-in type fits it (`EhOsContract.Next.Contract.Data`);
    one of a domain value is the Mix compiler's (X9). An event consumed from a
    sibling contract has its fields in the sibling, so its data is X9's as well.
  - **S4.** `rejected` names an invariant in the command's `rejects:`.
  - **S5.** `expect` names events in the command's `emits:`.
  - **S6.** Trigger and outcome fit the target. A command to a unit is followed by
    `expect` or by `rejected`, not both. An event delivered to a policy is followed
    by what it `issues`; to a process manager, by what it `issues`, `sets`,
    `cancels` or whether it has `ended`, and each of those is one its declaration
    allows. An effect's outcome is outside the log and a read model's rows have no
    word yet, so neither is a scenario's target; nor is a query, for the same
    reason.
  - **S7.** A scenario's `actor` is in the command's `by:`, and only a command has one.
  - **S8.** **Every invariant is named by at least one `rejected` scenario** — the
    successor of architecture §18's gate, kept an error although ESDM makes it a
    warning.
  """

  alias EhOsContract.DslRules
  alias EhOsContract.Next.Contract.{Data, Dsl, Rules}

  @doc false
  @spec check(map()) :: [DslRules.violation()]
  def check(declarations) do
    Enum.flat_map(declarations.scenarios, &scenario(&1, declarations)) ++ covered(declarations)
  end

  @doc """
  What a scenario is about: `{kind, declaration}` of the unit, policy or process
  manager its trigger resolves to, or `nil` when it resolves to none or to more
  than one. `Build` records it in the model as the scenario's target.
  """
  @spec target(struct(), map()) :: {atom(), struct()} | nil
  def target(%Dsl.Scenario{trigger: [trigger]} = scenario, declarations) do
    case candidates(trigger, declarations) do
      [one] when scenario.scope == nil -> one
      many -> Enum.find(many, fn {_kind, d} -> d.name == scenario.scope end)
    end
  end

  def target(_scenario, _declarations), do: nil

  defp scenario(%Dsl.Scenario{trigger: triggers} = scenario, d) do
    where = ~s|scenario "#{scenario.description}"|

    case triggers do
      [] ->
        [{"S1: #{where} has no trigger; give it one command, on or query", scenario}]

      [_, _ | _] = many ->
        [
          {"S1: #{where} has #{length(many)} triggers; a scenario has exactly one", scenario}
        ]

      [trigger] ->
        resolved(where, scenario, trigger, d)
    end
  end

  defp resolved(where, scenario, trigger, d) do
    case {candidates(trigger, d), scenario.scope} do
      {[], _} ->
        [{"S1: #{where}: #{unresolved(trigger)}", trigger}]

      {[_, _ | _] = many, nil} ->
        names = Enum.map(many, fn {kind, x} -> "#{kind(kind)} #{inspect(x.name)}" end)

        [
          {"S1: #{where}: #{inspect(trigger.name)} is handled by #{Enum.join(names, ", ")}; " <>
             "name one with scope:", trigger}
        ]

      {many, scope} ->
        case Enum.find(many, fn {_kind, x} -> scope == nil or x.name == scope end) do
          nil ->
            [
              {"S1: #{where}: scope #{inspect(scope)} does not answer #{inspect(trigger.name)}",
               scenario}
            ]

          {kind, target} ->
            fits(where, scenario, trigger, kind, target, d)
        end
    end
  end

  defp candidates(%Dsl.Trigger{kind: :command, name: name}, d) do
    for unit <- d.units, Enum.any?(unit.commands, &(&1.name == name)), do: {unit.kind, unit}
  end

  defp candidates(%Dsl.Trigger{kind: :on, name: name}, d) do
    for(p <- d.policies, name in p.handles, do: {:policy, p}) ++
      for(pm <- d.process_managers, name in triggers(pm), do: {:process_manager, pm}) ++
      for(e <- d.effects, name in e.handles, do: {:effect, e}) ++
      for r <- d.read_models, name in r.projects, do: {:read_model, r}
  end

  defp candidates(%Dsl.Trigger{kind: :query, name: name}, d) do
    for q <- d.queries, q.name == name, do: {:query, q}
  end

  defp unresolved(%Dsl.Trigger{kind: :command, name: name}),
    do: "#{inspect(name)} is not a command of this contract"

  defp unresolved(%Dsl.Trigger{kind: :on, name: name}),
    do: "nothing in this contract handles #{inspect(name)}"

  defp unresolved(%Dsl.Trigger{kind: :query, name: name}),
    do: "#{inspect(name)} is not a query of this contract"

  defp triggers(pm) do
    Enum.map(pm.starts_on, & &1.event) ++
      Enum.map(pm.on, & &1.event) ++ Enum.map(pm.ends_on, & &1.event)
  end

  defp kind(:aggregate), do: "aggregate"
  defp kind(:dcb), do: "dcb"
  defp kind(:policy), do: "policy"
  defp kind(:process_manager), do: "process manager"
  defp kind(:effect), do: "effect"
  defp kind(:read_model), do: "read model"
  defp kind(:query), do: "query"

  # --- S2–S7, once the target is known ----------------------------------------------

  defp fits(where, scenario, trigger, kind, unit, _d) when kind in [:aggregate, :dcb] do
    command = Enum.find(unit.commands, &(&1.name == trigger.name))
    events = Map.new(Rules.events(unit), &{&1.name, &1})
    consulted = MapSet.new(unit.consults, & &1.event)
    where = "#{where} (#{kind(kind)} #{inspect(unit.name)})"

    givens =
      Enum.flat_map(scenario.given, fn given ->
        cond do
          Map.has_key?(events, given.event) ->
            data(where, given, "event #{inspect(given.event)}", events[given.event].fields, unit,
              required: true
            )

          MapSet.member?(consulted, given.event) ->
            []

          true ->
            [
              {"S2: #{where}: given #{inspect(given.event)} is neither an event of the unit nor " <>
                 "one it consults", given}
            ]
        end
      end)

    command_data =
      data(where, trigger, "command #{inspect(command.name)}", command.fields, unit,
        required: true
      )

    expected =
      Enum.flat_map(scenario.expect, fn expect ->
        if expect.event in command.emits do
          data(where, expect, "event #{inspect(expect.event)}", events[expect.event].fields, unit,
            required: false
          )
        else
          [
            {"S5: #{where}: expects #{inspect(expect.event)}, which command " <>
               "#{inspect(command.name)} does not emit", expect}
          ]
        end
      end)

    rejected =
      cond do
        scenario.rejected == nil ->
          []

        scenario.rejected in command.rejects ->
          []

        true ->
          [
            {"S4: #{where}: rejected #{inspect(scenario.rejected)} is not among what command " <>
               "#{inspect(command.name)} rejects, #{inspect(command.rejects)}", scenario}
          ]
      end

    outcome =
      case {scenario.expect, scenario.rejected} do
        {[], nil} ->
          [{"S6: #{where}: after a command, expect the events or say it is rejected", scenario}]

        {[_ | _], rejected} when rejected != nil ->
          [{"S6: #{where}: a command either emits or is rejected; not both", scenario}]

        _ ->
          []
      end

    foreign =
      reactions_only(where, scenario, "a command to a unit") ++
        actor(where, scenario, command)

    givens ++ command_data ++ expected ++ rejected ++ outcome ++ foreign
  end

  defp fits(where, scenario, trigger, :policy, policy, d) do
    where = "#{where} (policy #{inspect(policy.name)})"

    givens =
      for given <- scenario.given do
        {"S2: #{where}: a policy keeps no state, so it takes no given", given}
      end

    outcome =
      if scenario.issues == [],
        do: [{"S6: #{where}: after an event, a policy issues something; say what", scenario}],
        else: []

    givens ++
      delivered(where, trigger, d) ++
      issued(where, scenario, policy.issues, d) ++
      decisions_only(where, scenario) ++
      no_timers(where, scenario, "a policy") ++ outcome ++ no_actor(where, scenario)
  end

  defp fits(where, scenario, trigger, :process_manager, pm, d) do
    where = "#{where} (process manager #{inspect(pm.name)})"
    reactions = Enum.filter(pm.starts_on ++ pm.on, &(&1.event == trigger.name))
    ends = Enum.any?(pm.ends_on, &(&1.event == trigger.name))

    givens =
      for given <- scenario.given, given.event not in triggers(pm) do
        {"S2: #{where}: given #{inspect(given.event)} is not an event it handles", given}
      end

    allowed = fn key -> reactions |> Enum.flat_map(&Map.get(&1, key, [])) |> MapSet.new() end

    timers =
      for {key, verb} <- [sets: "set", cancels: "cancel"],
          ref <- Map.fetch!(scenario, key),
          not MapSet.member?(allowed.(key), ref.timer) do
        {"S6: #{where}: #{inspect(trigger.name)} does not #{verb} timer #{inspect(ref.timer)}",
         ref}
      end

    ended =
      if scenario.ended and not ends,
        do: [{"S6: #{where}: #{inspect(trigger.name)} is not among what it ends on", scenario}],
        else: []

    outcome =
      if scenario.issues == [] and scenario.sets == [] and scenario.cancels == [] and
           not scenario.ended,
         do: [
           {"S6: #{where}: after an event, say what it issues, sets, cancels, or that it ended",
            scenario}
         ],
         else: []

    givens ++
      delivered(where, trigger, d) ++
      issued(where, scenario, Enum.flat_map(reactions, & &1.issues), d) ++
      decisions_only(where, scenario) ++ timers ++ ended ++ outcome ++ no_actor(where, scenario)
  end

  defp fits(where, scenario, _trigger, kind, target, _d) do
    why =
      case kind do
        :effect -> "an effect's outcome is outside the log"
        :read_model -> "a read model's rows have no word in a scenario yet"
        :query -> "a query's answer has no word in a scenario yet"
      end

    [
      {"S6: #{where}: #{kind(kind)} #{inspect(target.name)} cannot be a scenario's target: " <>
         "#{why}", scenario}
    ]
  end

  # The event an `on` delivers: its data, when this contract declares its fields.
  defp delivered(where, trigger, d) do
    case Enum.find(Rules.local_events(d), &(&1.name == trigger.name)) do
      nil ->
        case received_fields(d, trigger.name) do
          nil ->
            []

          fields ->
            data(where, trigger, "event #{inspect(trigger.name)}", fields, nil, required: true)
        end

      event ->
        unit = Enum.find(d.units, fn u -> event in Rules.events(u) end)
        data(where, trigger, "event #{inspect(event.name)}", event.fields, unit, required: true)
    end
  end

  defp received_fields(d, name) do
    Enum.find_value(d.consumes, fn
      %Dsl.Consumes{from: from, as: ^name, fields: fields} when is_binary(from) -> fields
      _ -> nil
    end)
  end

  defp issued(where, scenario, allowed, d) do
    commands = Map.new(Rules.commands(d), &{&1.name, &1})

    Enum.flat_map(scenario.issues, fn issues ->
      if issues.command in allowed do
        unit = Enum.find(d.units, fn u -> Enum.any?(u.commands, &(&1.name == issues.command)) end)

        data(
          where,
          issues,
          "command #{inspect(issues.command)}",
          commands[issues.command].fields,
          unit,
          required: false
        )
      else
        [{"S6: #{where}: issues #{inspect(issues.command)}, which it does not issue", issues}]
      end
    end)
  end

  defp reactions_only(where, scenario, what) do
    for {key, word} <- [issues: "issues", sets: "sets", cancels: "cancels"],
        declaration <- Map.fetch!(scenario, key) do
      {"S6: #{where}: #{word} belongs to a reaction's scenario, not to #{what}", declaration}
    end ++
      if(scenario.ended,
        do: [{"S6: #{where}: ended belongs to a process manager's scenario", scenario}],
        else: []
      )
  end

  defp decisions_only(where, scenario) do
    expected =
      for expect <- scenario.expect do
        {"S6: #{where}: a reaction issues commands; expect belongs to a command's scenario",
         expect}
      end

    rejected =
      if scenario.rejected,
        do: [{"S6: #{where}: rejected belongs to a command's scenario", scenario}],
        else: []

    expected ++ rejected
  end

  defp no_timers(where, scenario, what) do
    for key <- [:sets, :cancels], ref <- Map.fetch!(scenario, key) do
      {"S6: #{where}: #{what} has no timers", ref}
    end ++
      if(scenario.ended, do: [{"S6: #{where}: #{what} does not end", scenario}], else: [])
  end

  defp actor(_where, %{actor: nil}, _command), do: []

  defp actor(where, scenario, command) do
    if scenario.actor in command.by,
      do: [],
      else: [
        {"S7: #{where}: actor #{inspect(scenario.actor)} is not among who may issue " <>
           "#{inspect(command.name)}, #{inspect(command.by)}", scenario}
      ]
  end

  defp no_actor(_where, %{actor: nil}), do: []

  defp no_actor(where, scenario),
    do: [{"S7: #{where}: only a command's scenario names an actor", scenario}]

  # --- S3: data -----------------------------------------------------------------------

  defp data(where, declaration, what, fields, unit, required: required?) do
    identity = if unit, do: unit.identity, else: []
    declared = Map.new(fields, &{&1.name, &1})
    data = declaration.data

    unknown =
      for key <- Map.keys(data), key not in identity, not Map.has_key?(declared, key) do
        {"S3: #{where}: #{what} has no field #{inspect(key)}", declaration}
      end

    missing =
      if required? do
        for f <- fields, not f.optional, not Map.has_key?(data, f.name) do
          {"S3: #{where}: #{what} needs #{inspect(f.name)}", declaration}
        end
      else
        []
      end

    types =
      for {key, value} <- data,
          type = type_of(key, declared, identity),
          type != nil,
          problem <- Data.problems(type, value) do
        {"S3: #{where}: #{what}, field #{inspect(key)}: #{problem}", declaration}
      end

    unknown ++ missing ++ types
  end

  defp type_of(key, declared, identity) do
    cond do
      Map.has_key?(declared, key) -> declared[key].type
      key in identity -> :id
      true -> nil
    end
  end

  # --- S8 -----------------------------------------------------------------------------

  # Per unit: two units may each have an invariant of the same name.
  defp covered(d) do
    rejected =
      for scenario <- d.scenarios,
          scenario.rejected != nil,
          {_kind, unit} <- List.wrap(target(scenario, d)),
          into: MapSet.new(),
          do: {unit.name, scenario.rejected}

    for unit <- d.units,
        invariant <- unit.invariants,
        not MapSet.member?(rejected, {unit.name, invariant.name}) do
      {"S8: invariant #{inspect(invariant.name)} of #{kind(unit.kind)} #{inspect(unit.name)} has " <>
         "no scenario in which a command is rejected on it", invariant}
    end
  end
end
