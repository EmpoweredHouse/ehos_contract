defmodule EhOsContract.Contract.Rules.Scenarios do
  # S1–S10 of v2 §6 and the plan: scenarios, the examples a process owner reads.
  #
  # - **S1.** A scenario has exactly one trigger — `command`, `on` or `query` — and
  #   it resolves to the declaration that answers it. No two scenarios have the same
  #   description, which is what names each one. A command belongs to one unit;
  #   an event may be handled by several reactions, and then `target` names the one.
  # - **S2.** `given` events are ones the target keeps its state from: a unit's own
  #   events, and for a boundary also the events it consults; a process manager's
  #   triggers; for a query, the events the read model it reads projects. A policy
  #   keeps no state, so it takes no `given`.
  # - **S3.** Data names declared fields only. `given` and the trigger supply every
  #   required field, except the target's identity, which a scenario fills in itself:
  #   it is one stream. A value of a built-in type fits it (`EhOsContract.Contract.Data`);
  #   one of a domain value is the Mix compiler's (X9). An event consumed from a
  #   sibling contract has its fields in the sibling, so its data is X9's as well. A
  #   given's `at:` is an ISO 8601 timestamp with an offset, never earlier than the given
  #   before it, since a log never holds a later event before an earlier one, and no
  #   undated given comes before a dated one (plan DD, S2, #251).
  # - **S4.** `rejected` names an invariant or a constraint in the command's `rejects:`.
  # - **S5.** `expect` names events in the command's `emits:`.
  # - **S6.** Trigger and outcome fit the target. A command to a unit is followed by
  #   `expect` or by `rejected`, not both. An event delivered to a policy is followed
  #   by what it `issues`; to a process manager, by what it `issues`, `sets`,
  #   `cancels`, whether it has `ended`, or the `state` its run holds after it (plan
  #   EP4), and each of those is one its declaration allows — `state` once, naming
  #   fields of the state or the correlation; `on` may also name one of its timers,
  #   which then fires. Only a process manager's scenario says a `state`. A query is
  #   followed by one `answers`, ESDM's `result`: a list of rows when it returns
  #   many, one row or `nil` when it returns one, each row naming fields of the read
  #   model it reads. An effect's outcome is outside the log, so an effect is no
  #   scenario's target; neither is a read model on its own, which a scenario reaches
  #   through a query, as ESDM's read model scenario does.
  # - **S7.** A scenario's `actor` is in the command's `by:`, and only a command has one;
  #   `as:`, the person issuing it (plan DD, A1, #247), only beside an `actor`.
  # - **S8.** **Every invariant is named by at least one `rejected` scenario** — the
  #   successor of architecture §18's gate, kept an error although ESDM makes it a
  #   warning — and so is every constraint of a command, by a scenario of that command
  #   (plan EL2).
  # - **S9.** **A domain service's rule gives at least one example** (plan EL2b), and
  #   each is `{[argument, …], result}`: as many arguments as the function takes, each
  #   of its argument's type and the result of the one it returns, as plain data —
  #   `nil` only where the declaration says optional — and none twice, since each
  #   names its test. A value of a domain type is the Mix compiler's (X9), as a
  #   scenario's is.
  # - **S12** (plan DD, T2a, #240). `given_entity` gives the row of an entity the
  #   scenario's command `reads:`, and a scenario of such a command gives at least one of
  #   every entity it reads: the decision cannot be run without them. Whether the row's
  #   fields are the entity's is X9's, where the domain is known.
  # - **S10.** `illustrates:` names rules of the scenario's target that only a scenario
  #   shows (plan EP2), each once: a constraint of a policy, a process manager or a
  #   query, or an invariant of a process manager. A command's scenario names none: a
  #   unit's invariants and a command's constraints are shown by `rejected` (S8). An
  #   effect is no scenario's target.
  @moduledoc false

  alias EhOsContract.DslRules
  alias EhOsContract.Contract.{Data, Dsl, Rules}

  @doc false
  @spec check(map()) :: [DslRules.violation()]
  def check(declarations) do
    Enum.flat_map(declarations.scenarios, &scenario(&1, declarations)) ++
      Enum.flat_map(declarations.scenarios, &entities(&1, declarations)) ++
      Enum.flat_map(declarations.scenarios, &dated/1) ++
      described_once(declarations) ++ covered(declarations) ++ rule_examples(declarations)
  end

  # --- S9: a rule of a domain service, on examples (plan EL2b) -----------------------

  defp rule_examples(d) do
    for s <- d.domain_services,
        f <- s.functions,
        r <- f.rules,
        violation <- rule_violations(s, f, r) do
      violation
    end
  end

  defp rule_violations(service, function, %{examples: []} = rule) do
    [
      {"S9: rule #{inspect(rule.name)} of function #{inspect(function.name)} of domain service " <>
         "#{inspect(service.name)} gives no example; give at least one, " <>
         "`examples: [{[argument, …], result}]`, since each is a test", rule}
    ]
  end

  defp rule_violations(_service, function, rule) do
    where = "S9: rule #{inspect(rule.name)} of function #{inspect(function.name)}"
    arity = length(function.arguments)

    shapes =
      for {example, index} <- Enum.with_index(rule.examples, 1),
          problem <- example_problems(example, function, arity) do
        {"#{where}, example #{index}: #{problem}", rule}
      end

    # Each example names its test, so one given twice would name two alike.
    twice =
      for example <- Enum.uniq(DslRules.duplicates(rule.examples, & &1)) do
        {"#{where} gives the example #{inspect(example, charlists: :as_lists)} twice", rule}
      end

    shapes ++ twice
  end

  @doc """
  The arguments and result of a well-formed example of a rule, each with what it
  fills — `{argument or returns, value}` — or `:error` when S9 refuses its shape.
  """
  @spec example_values(term(), struct()) :: {:ok, [{struct(), term()}]} | :error
  def example_values({arguments, result}, function)
      when is_list(arguments) and length(arguments) == length(function.arguments),
      do: {:ok, Enum.zip(function.arguments, arguments) ++ [{function.returns, result}]}

  def example_values(_example, _function), do: :error

  defp example_problems(example, function, arity) do
    case example_values(example, function) do
      :error ->
        [
          "#{inspect(example, charlists: :as_lists)} is not {[argument, …], result} with " <>
            "#{arity} " <>
            "argument#{if arity == 1, do: "", else: "s"}"
        ]

      {:ok, filled} ->
        for {declared, value} <- filled,
            # F2 refuses a function without `returns`.
            declared != nil,
            problem <- value_problems(declared, value) do
          "#{describe(declared)}: #{problem}"
        end
    end
  end

  defp value_problems(%{optional: true}, nil), do: []
  defp value_problems(_declared, nil), do: ["nil, and the declaration does not say optional"]
  defp value_problems(declared, value), do: Data.problems(declared.type, value)

  defp describe(%Dsl.Argument{name: name}), do: "argument #{inspect(name)}"
  defp describe(%Dsl.Returns{}), do: "the result"

  defp entities(%Dsl.Scenario{} = scenario, d) do
    where = ~s|scenario "#{scenario.description}"|
    command = reading(scenario, d)

    case {command, scenario.given_entities} do
      {nil, []} ->
        []

      {nil, [first | _]} ->
        [
          {"S12: #{where}: given_entity gives a row only to a command that reads: entities",
           first}
        ]

      {command, entities} ->
        read = for {_name, field} <- command.reads, do: read_entity(command, field)
        given = Enum.map(entities, & &1.entity)

        stray =
          for e <- entities, e.entity not in read do
            {"S12: #{where}: given_entity #{inspect(e.entity)} is not an entity command " <>
               "#{inspect(command.name)} reads (#{inspect(Enum.uniq(read))})", e}
          end

        missing =
          for entity <- Enum.uniq(read), entity != nil, entity not in given do
            {"S12: #{where}: command #{inspect(command.name)} reads #{inspect(entity)}, and the " <>
               "scenario gives no given_entity #{inspect(entity)}", scenario}
          end

        stray ++ missing
    end
  end

  # The command a scenario triggers, when it reads entities.
  defp reading(%Dsl.Scenario{trigger: [%Dsl.Trigger{kind: :command, name: name}]}, d),
    do: Enum.find(Rules.commands(d), &(&1.name == name and &1.reads != []))

  defp reading(_scenario, _d), do: nil

  # The entity a read names, by its field's type; `nil` for a field A8 refuses.
  defp read_entity(command, field) do
    case Enum.find(command.fields, &(&1.name == field)) do
      %{type: {:id, entity}} -> entity
      _ -> nil
    end
  end

  # A scenario is named by its description, in the test `EhOsContract.ScenarioCase`
  # generates for it too.
  defp described_once(d) do
    for scenario <- DslRules.duplicates(d.scenarios, & &1.description) do
      {~s|S1: two scenarios are described "#{scenario.description}"; each case needs its own words|,
       scenario}
    end
  end

  @doc """
  What a scenario is about: `{kind, declaration}` of the unit, policy or process
  manager its trigger resolves to, or `nil` when it resolves to none or to more
  than one. `Build` records it in the model as the scenario's target.
  """
  @spec target(struct(), map()) :: {atom(), struct()} | nil
  def target(%Dsl.Scenario{trigger: [trigger]} = scenario, declarations) do
    case candidates(trigger, declarations) do
      [one] when scenario.target == nil -> one
      many -> Enum.find(many, fn {_kind, d} -> d.name == scenario.target end)
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
    case {candidates(trigger, d), scenario.target} do
      {[], _} ->
        [{"S1: #{where}: #{unresolved(trigger)}", trigger}]

      {[_, _ | _] = many, nil} ->
        names = Enum.map(many, fn {kind, x} -> "#{kind(kind)} #{inspect(x.name)}" end)

        [
          {"S1: #{where}: #{inspect(trigger.name)} is handled by #{Enum.join(names, ", ")}; " <>
             "name one with target", trigger}
        ]

      {many, named} ->
        case Enum.find(many, fn {_kind, x} -> named == nil or x.name == named end) do
          nil ->
            [
              {"S1: #{where}: target #{inspect(named)} does not answer #{inspect(trigger.name)}",
               scenario}
            ]

          {kind, target} ->
            fits(where, scenario, trigger, kind, target, d) ++
              illustrated(where, scenario, kind, target)
        end
    end
  end

  # S10 (plan EP2). An effect or a read model is refused as a target by S6 already.
  defp illustrated(_where, _scenario, kind, _target) when kind in [:effect, :read_model], do: []

  defp illustrated(where, %{illustrates: [_ | _]} = scenario, kind, _target)
       when kind in [:aggregate, :dcb] do
    [
      {"S10: #{where} names rules in illustrates:, but a command's scenario shows the rules " <>
         "it is refused on with `rejected`", scenario}
    ]
  end

  defp illustrated(where, scenario, kind, target) do
    rules = Enum.map(illustratable(kind, target), fn {_word, rule} -> rule.name end)

    unknown =
      for name <- scenario.illustrates, name not in rules do
        {"S10: #{where} illustrates #{inspect(name)}, which is no rule of #{kind(kind)} " <>
           "#{inspect(target.name)}: it illustrates #{rules_of(kind)} by name", scenario}
      end

    twice =
      for name <- scenario.illustrates |> DslRules.duplicates(& &1) |> Enum.uniq() do
        {"S10: #{where} illustrates #{inspect(name)} twice", scenario}
      end

    unknown ++ twice
  end

  @doc """
  The rules of a scenario's target that a scenario `illustrates:` (plan EP2), each with
  its word: a policy's and a query's constraints, a process manager's constraints and
  invariants. Nothing for any other kind. Takes a declaration or its model, where an
  empty list is left out, so S10 and `mix eh_os_contract.check` read one list.
  """
  @spec illustratable(atom(), map()) :: [{String.t(), map()}]
  def illustratable(kind, target) when kind in [:policy, :query, :process_manager] do
    Enum.map(Map.get(target, :constraints, []), &{"constraint", &1}) ++
      Enum.map(Map.get(target, :invariants, []), &{"invariant", &1})
  end

  def illustratable(_kind, _target), do: []

  defp rules_of(:process_manager), do: "the process manager's constraints and invariants"
  defp rules_of(kind), do: "the #{kind(kind)}'s constraints"

  defp candidates(%Dsl.Trigger{kind: :command, name: name}, d) do
    for unit <- d.units, Enum.any?(unit.commands, &(&1.name == name)), do: {unit.kind, unit}
  end

  defp candidates(%Dsl.Trigger{kind: :on, name: name}, d) do
    for(p <- d.policies, name in p.handles, do: {:policy, p}) ++
      for(
        pm <- d.process_managers,
        name in triggers(pm) or name in timers(pm),
        do: {:process_manager, pm}
      ) ++
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

  defp timers(pm), do: Enum.map(pm.timers, & &1.name)

  defp kind(:aggregate), do: "aggregate"
  defp kind(:dcb), do: "dcb"
  defp kind(:policy), do: "policy"
  defp kind(:process_manager), do: "process manager"
  defp kind(:effect), do: "effect"
  defp kind(:read_model), do: "read model"
  defp kind(:query), do: "query"

  # --- S2–S7, once the target is known ----------------------------------------------

  defp fits(where, scenario, trigger, kind, unit, d) when kind in [:aggregate, :dcb] do
    command = Enum.find(unit.commands, &(&1.name == trigger.name))
    events = Map.new(unit.events, &{&1.name, &1})
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
            event_data(where, given, given.event, d)

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
        no_state(where, scenario) ++ actor(where, scenario, command)

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
      event_data(where, trigger, trigger.name, d) ++
      issued(where, scenario, policy.issues, d) ++
      decisions_only(where, scenario) ++
      no_timers(where, scenario, "a policy") ++
      no_state(where, scenario) ++ outcome ++ no_actor(where, scenario)
  end

  defp fits(where, scenario, trigger, :process_manager, pm, d) do
    where = "#{where} (process manager #{inspect(pm.name)})"
    reactions = Enum.filter(pm.starts_on ++ pm.on, &(&1.event == trigger.name))
    timer = Enum.find(pm.timers, &(&1.name == trigger.name))
    ends = Enum.any?(pm.ends_on, &(&1.event == trigger.name))

    givens =
      Enum.flat_map(scenario.given, fn given ->
        if given.event in triggers(pm),
          do: event_data(where, given, given.event, d),
          else: [
            {"S2: #{where}: given #{inspect(given.event)} is not an event it handles", given}
          ]
      end)

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
           scenario.state == [] and not scenario.ended,
         do: [
           {"S6: #{where}: after an event, say what it issues, sets, cancels, the state it " <>
              "holds, or that it ended", scenario}
         ],
         else: []

    state =
      case scenario.state do
        [] ->
          []

        [expected] ->
          data(
            where,
            expected,
            "the state of process manager #{inspect(pm.name)}",
            Rules.state_fields(pm.state),
            %{identity: pm.correlate},
            required: false
          )

        [_, second | _] ->
          [{"S6: #{where}: a scenario says the state once", second}]
      end

    # A timer that fires delivers no event, so it has no data to check.
    delivered = if timer, do: [], else: event_data(where, trigger, trigger.name, d)
    issues = Enum.flat_map(reactions, & &1.issues) ++ if(timer, do: timer.issues, else: [])

    givens ++
      delivered ++
      issued(where, scenario, issues, d) ++
      decisions_only(where, scenario) ++
      timers ++ ended ++ outcome ++ state ++ no_actor(where, scenario)
  end

  defp fits(where, scenario, trigger, :query, query, d) do
    where = "#{where} (query #{inspect(query.name)})"
    read_model = Enum.find(d.read_models, &(&1.name == query.reads))
    projects = if read_model, do: read_model.projects, else: []

    givens =
      Enum.flat_map(scenario.given, fn given ->
        if given.event in projects,
          do: event_data(where, given, given.event, d),
          else: [
            {"S2: #{where}: given #{inspect(given.event)} is not an event read model " <>
               "#{inspect(query.reads)} projects", given}
          ]
      end)

    params =
      data(where, trigger, "query #{inspect(query.name)}", query.params, nil, required: true)

    answered =
      case scenario.answers do
        [answers] ->
          answers(where, answers, query, read_model)

        [] ->
          [{"S6: #{where}: after a query, say what it answers", scenario}]

        [_, second | _] ->
          [{"S6: #{where}: a query answers once", second}]
      end

    foreign =
      reactions_only(where, %{scenario | answers: []}, "a query") ++
        decisions_only(where, %{scenario | answers: []}) ++
        no_state(where, scenario) ++ no_actor(where, scenario)

    givens ++ params ++ answered ++ foreign
  end

  defp fits(where, scenario, _trigger, kind, target, _d) do
    why =
      case kind do
        :effect -> "an effect's outcome is outside the log"
        :read_model -> "a scenario reaches a read model through a query that reads it"
      end

    [
      {"S6: #{where}: #{kind(kind)} #{inspect(target.name)} cannot be a scenario's target: " <>
         "#{why}", scenario}
    ]
  end

  # The data of an event a scenario gives — delivered by `on`, or given — when this
  # contract declares its fields: a local event's, whose unit's identity the scenario
  # fills in, or a received one's. A sibling's fields are the sibling's (X9).
  defp event_data(where, declaration, name, d) do
    case Enum.find(Rules.local_events(d), &(&1.name == name)) do
      nil ->
        case received_fields(d, name) do
          nil ->
            []

          fields ->
            data(where, declaration, "event #{inspect(name)}", fields, nil, required: true)
        end

      event ->
        unit = Enum.find(d.units, fn u -> event in u.events end)
        data(where, declaration, "event #{inspect(name)}", event.fields, unit, required: true)
    end
  end

  defp received_fields(d, name) do
    case List.keyfind(Rules.consumed(d), name, 0) do
      {_, %Dsl.Consumes{from: from, fields: fields}} when is_binary(from) -> fields
      _ -> nil
    end
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
    for {key, word} <- [issues: "issues", sets: "sets", cancels: "cancels", answers: "answers"],
        declaration <- Map.fetch!(scenario, key) do
      owner = if key == :answers, do: "a query's", else: "a reaction's"
      {"S6: #{where}: #{word} belongs to #{owner} scenario, not to #{what}", declaration}
    end ++
      if(scenario.ended,
        do: [{"S6: #{where}: ended belongs to a process manager's scenario", scenario}],
        else: []
      )
  end

  defp decisions_only(where, scenario) do
    answered =
      for answers <- scenario.answers do
        {"S6: #{where}: answers belongs to a query's scenario", answers}
      end

    expected =
      for expect <- scenario.expect do
        {"S6: #{where}: a reaction issues commands; expect belongs to a command's scenario",
         expect}
      end

    rejected =
      if scenario.rejected,
        do: [{"S6: #{where}: rejected belongs to a command's scenario", scenario}],
        else: []

    answered ++ expected ++ rejected
  end

  defp no_timers(where, scenario, what) do
    for key <- [:sets, :cancels], ref <- Map.fetch!(scenario, key) do
      {"S6: #{where}: #{what} has no timers", ref}
    end ++
      if(scenario.ended, do: [{"S6: #{where}: #{what} does not end", scenario}], else: [])
  end

  defp no_state(where, scenario) do
    for state <- scenario.state do
      {"S6: #{where}: state belongs to a process manager's scenario", state}
    end
  end

  # Plan DD, A1 (#247): `as:` names the person beside the role, so it needs one.
  defp actor(where, %{actor: nil, as: as} = scenario, _command) when is_binary(as),
    do: [{"S7: #{where}: as: names a person only beside an actor:", scenario}]

  defp actor(_where, %{actor: nil}, _command), do: []

  defp actor(where, scenario, command) do
    if scenario.actor in command.by,
      do: [],
      else: [
        {"S7: #{where}: actor #{inspect(scenario.actor)} is not among who may issue " <>
           "#{inspect(command.name)}, #{inspect(command.by)}", scenario}
      ]
  end

  defp no_actor(where, %{actor: nil, as: as} = scenario) when is_binary(as),
    do: [{"S7: #{where}: only a command's scenario names a person with as:", scenario}]

  defp no_actor(_where, %{actor: nil}), do: []

  defp no_actor(where, scenario),
    do: [{"S7: #{where}: only a command's scenario names an actor", scenario}]

  # The rows a query answers: as many as it returns, each naming fields of the row.
  defp answers(where, answers, query, read_model) do
    rows =
      case {query.returns, answers.rows} do
        {:many, rows} when is_list(rows) -> rows
        {:one, nil} -> []
        {:one, %{} = row} -> [row]
        _ -> :unfit
      end

    case rows do
      :unfit ->
        shape = if query.returns == :one, do: "one row, a map, or nil", else: "a list of rows"
        [{"S6: #{where}: answers #{shape}, as the query returns #{query.returns}", answers}]

      rows ->
        fields = if read_model, do: read_model.fields, else: []

        Enum.flat_map(rows, fn
          %{} = row ->
            data(where, answers, "a row of read model #{inspect(query.reads)}", fields, nil,
              required: false,
              data: row
            )

          other ->
            [{"S6: #{where}: a row is a map of fields, and #{inspect(other)} is not", answers}]
        end)
    end
  end

  # --- S3: when each given happened (plan DD, S2, #251) ------------------------------

  @epoch ~U[2026-01-01 09:00:00Z]

  @doc false
  # The moment each given happened, in order: its `at:`, or a minute after the given
  # before it, the first at 2026-01-01 09:00 UTC. An `at:` that is no timestamp is
  # `{:unfit, problem}`, and the given after it counts from the one before. The one rule
  # for S3 and for `EhOsContract.ScenarioCase`, which dates its givens by it.
  @spec moments([map()]) :: [DateTime.t() | {:unfit, String.t()}]
  def moments(givens) do
    {moments, _last} =
      Enum.map_reduce(givens, nil, fn given, last ->
        case Map.get(given, :at) do
          nil ->
            at = if last, do: DateTime.add(last, 60), else: @epoch
            {at, at}

          written ->
            case DateTime.from_iso8601(written) do
              {:ok, at, _offset} -> {at, at}
              {:error, _} -> {{:unfit, hd(Data.problems(:timestamp, written))}, last}
            end
        end
      end)

    moments
  end

  @doc false
  # S3 over the givens of one scenario, contract's or process module's alike.
  @spec dated(String.t(), [map()]) :: [DslRules.violation()]
  def dated(where, givens) do
    {violations, _last} =
      givens
      |> Enum.zip(moments(givens))
      |> Enum.reduce({[], nil}, fn
        {given, {:unfit, problem}}, {acc, last} ->
          {[{"S3: #{where}: given #{inspect(given.event)}, at: #{problem}", given} | acc], last}

        {given, at}, {acc, last} ->
          if last && DateTime.compare(at, last) == :lt,
            do:
              {[
                 {"S3: #{where}: given #{inspect(given.event)} happened at " <>
                    "#{DateTime.to_iso8601(at)}, before the given before it " <>
                    "(#{DateTime.to_iso8601(last)}); a log holds events in the order they " <>
                    "happened, so list them so, and a given without at: comes a minute " <>
                    "after the one before it", given}
                 | acc
               ], at},
            else: {acc, at}
      end)

    Enum.reverse(violations) ++ undated_first(where, givens)
  end

  # An undated given before a dated one would happen on 1 January 2026, the default,
  # whatever the dated ones say, so a window could open months before the author meant.
  defp undated_first(where, givens) do
    case Enum.split_while(givens, &(Map.get(&1, :at) == nil)) do
      {[_ | _] = undated, [dated | _]} ->
        for given <- undated do
          {"S3: #{where}: given #{inspect(given.event)} has no at:, and comes before given " <>
             "#{inspect(dated.event)}, which has one; it would happen on " <>
             "#{DateTime.to_iso8601(@epoch)}, so date it too", given}
        end

      _ ->
        []
    end
  end

  defp dated(scenario), do: dated(~s|scenario "#{scenario.description}"|, scenario.given)

  # --- S3: data -----------------------------------------------------------------------

  defp data(where, declaration, what, fields, unit, opts) do
    required? = Keyword.fetch!(opts, :required)
    identity = if unit, do: unit.identity, else: []
    declared = Map.new(fields, &{&1.name, &1})
    data = Keyword.get_lazy(opts, :data, fn -> declaration.data end)

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

    invariants =
      for unit <- d.units,
          invariant <- unit.invariants,
          not MapSet.member?(rejected, {unit.name, invariant.name}) do
        {"S8: invariant #{inspect(invariant.name)} of #{kind(unit.kind)} #{inspect(unit.name)} has " <>
           "no scenario in which a command is rejected on it", invariant}
      end

    # A command's constraint, by that command (plan EL2).
    refused =
      for scenario <- d.scenarios,
          scenario.rejected != nil,
          %{kind: :command, name: command} <- scenario.trigger,
          into: MapSet.new(),
          do: {command, scenario.rejected}

    constraints =
      for unit <- d.units,
          command <- unit.commands,
          constraint <- command.constraints,
          not MapSet.member?(refused, {command.name, constraint.name}) do
        {"S8: constraint #{inspect(constraint.name)} of command #{inspect(command.name)} has no " <>
           "scenario in which the command is rejected on it", constraint}
      end

    invariants ++ constraints
  end
end
