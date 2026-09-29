defmodule EhOsContract.Contract.Rules.Consumers do
  @moduledoc """
  P1–P5 of v2 §6: what reacts to events, and what is read.

  - **P1.** A policy, and an effect, handles events of this contract or events it
    consumes; a policy issues commands of this contract only.
  - **P2.** An effect that `calls:` an external system cannot run
    `:in_transaction`: the call cannot be rolled back with the append.
  - **P3.** A policy or an effect delivered `:at_least_once` names its
    `idempotency`, what makes a second delivery harmless. A process manager does
    not: its commands and timers take keys the library derives from the run, so a
    replay or a second delivery repeats nothing (v2 §17). v2 §4.6 writes one
    without `idempotency`, and this is why it compiles.
  - **P4.** A process manager starts on at least one event and correlates on at
    least one field: with none, every run would share one record, one state and
    one set of timers, and the first ending would end it for all. Its triggers are
    events or its own timers; its `sets:` and `cancels:` name its own timers; a
    timer fires after `wait:` or `at:` a `:timestamp` field of the state, exactly
    one of them; what it issues is a command of this contract; it is delivered
    `:at_least_once`, since it runs from the log in order.
  - **P5.** A read model projects events of this contract or events it consumes; a
    query reads a read model of this contract.
  """

  alias EhOsContract.DslRules
  alias EhOsContract.Contract.Rules

  @doc false
  @spec check(map()) :: [DslRules.violation()]
  def check(declarations) do
    events =
      MapSet.new(
        Enum.map(Rules.local_events(declarations), & &1.name) ++
          Enum.map(Rules.consumed(declarations), &elem(&1, 0))
      )

    commands = MapSet.new(Rules.commands(declarations), & &1.name)
    read_models = MapSet.new(declarations.read_models, & &1.name)

    Enum.concat([
      Enum.flat_map(declarations.policies, &policy(&1, events, commands)),
      Enum.flat_map(declarations.effects, &effect(&1, events)),
      Enum.flat_map(declarations.process_managers, &process_manager(&1, events, commands)),
      Enum.flat_map(declarations.read_models, &read_model(&1, events)),
      Enum.flat_map(declarations.queries, &query(&1, read_models))
    ])
  end

  defp policy(policy, events, commands) do
    where = "policy #{inspect(policy.name)}"

    handles(where, policy, policy.handles, events) ++
      issues("P1", where, policy, policy.issues, commands) ++ idempotent(where, policy)
  end

  defp effect(effect, events) do
    where = "effect #{inspect(effect.name)}"

    in_transaction =
      if effect.calls != [] and effect.delivery == :in_transaction,
        do: [
          {"P2: #{where} calls #{inspect(effect.calls)}, so it cannot run :in_transaction: an " <>
             "external call is not rolled back with the append", effect}
        ],
        else: []

    handles(where, effect, effect.handles, events) ++ in_transaction ++ idempotent(where, effect)
  end

  defp process_manager(pm, events, commands) do
    where = "process manager #{inspect(pm.name)}"
    timers = MapSet.new(pm.timers, & &1.name)
    state = Map.new(Rules.state_fields(pm.state), &{&1.name, &1})

    starts =
      if pm.starts_on == [],
        do: [{"P4: #{where} starts on no event", pm}],
        else: []

    uncorrelated =
      if pm.correlate == [],
        do: [{"P4: #{where} correlates on no field, so every run would share one record", pm}],
        else: []

    triggers =
      for(s <- pm.starts_on, not MapSet.member?(events, s.event), do: {s, s.event, "starts on"}) ++
        for(e <- pm.ends_on, not MapSet.member?(events, e.event), do: {e, e.event, "ends on"}) ++
        for o <- pm.on,
            not MapSet.member?(events, o.event) and not MapSet.member?(timers, o.event),
            do: {o, o.event, "reacts on"}

    triggers =
      for {declaration, event, verb} <- triggers do
        {"P4: #{where} #{verb} #{inspect(event)}, which is neither an event of this contract, " <>
           "one it consumes, nor a timer of its own", declaration}
      end

    references =
      for declaration <- pm.starts_on ++ pm.on,
          {verb, names} <- [sets: declaration.sets, cancels: Map.get(declaration, :cancels, [])],
          name <- names,
          not MapSet.member?(timers, name) do
        {"P4: #{where} #{verb} #{inspect(name)}, which is not a timer of its own", declaration}
      end

    timer_shape = Enum.flat_map(pm.timers, &timer(where, &1, state))

    issued =
      for declaration <- pm.starts_on ++ pm.on ++ pm.timers,
          violation <- issues("P4", where, declaration, declaration.issues, commands) do
        violation
      end

    # Fed from the log in order, one step a transaction (v2 §12): there is no inline
    # process manager, and one declared so would run as if it were not.
    delivery =
      if pm.delivery == :in_transaction,
        do: [
          {"P4: #{where} is fed from the log in order, after the transaction; it cannot run " <>
             ":in_transaction", pm}
        ],
        else: []

    starts ++ uncorrelated ++ triggers ++ references ++ timer_shape ++ issued ++ delivery
  end

  defp timer(where, timer, state) do
    what = "#{where}: timer #{inspect(timer.name)}"

    case {timer.wait, timer.at} do
      {nil, nil} ->
        [{"P4: #{what} has neither wait: nor at:; give it exactly one", timer}]

      {wait, at} when wait != nil and at != nil ->
        [{"P4: #{what} has both wait: and at:; keep one", timer}]

      {nil, at} ->
        case Map.fetch(state, at) do
          {:ok, %{type: :timestamp}} ->
            []

          {:ok, field} ->
            [
              {"P4: #{what} fires at #{inspect(at)}, which is #{inspect(field.type)}, not :timestamp",
               timer}
            ]

          :error ->
            [{"P4: #{what} fires at #{inspect(at)}, which is not a field of its state", timer}]
        end

      _wait ->
        []
    end
  end

  defp read_model(read_model, events) do
    for event <- read_model.projects, not MapSet.member?(events, event) do
      {"P5: read model #{inspect(read_model.name)} projects #{inspect(event)}, which is neither an " <>
         "event of this contract nor one it consumes", read_model}
    end
  end

  defp query(query, read_models) do
    if MapSet.member?(read_models, query.reads),
      do: [],
      else: [
        {"P5: query #{inspect(query.name)} reads #{inspect(query.reads)}, which is not a read " <>
           "model of this contract", query}
      ]
  end

  defp handles(where, declaration, handles, events) do
    for event <- handles, not MapSet.member?(events, event) do
      {"P1: #{where} handles #{inspect(event)}, which is neither an event of this contract nor " <>
         "one it consumes", declaration}
    end
  end

  defp issues(rule, where, declaration, issues, commands) do
    for command <- issues, not MapSet.member?(commands, command) do
      {"#{rule}: #{where} issues #{inspect(command)}, which is not a command of this contract",
       declaration}
    end
  end

  defp idempotent(where, %{delivery: :at_least_once, idempotency: nil} = declaration) do
    [
      {"P3: #{where} is delivered :at_least_once, so it names its idempotency: what makes a " <>
         "second delivery harmless", declaration}
    ]
  end

  defp idempotent(_where, _declaration), do: []
end
