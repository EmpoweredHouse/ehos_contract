defmodule EhosContract.Contract.Rules.Consumers do
  # P1–P5 of v2 §6: what reacts to events, and what is read.
  #
  # - **P1.** A policy, and an effect, handles events of this contract or events it
  #   consumes, at least one; a policy issues commands of this contract only.
  # - **P2.** An effect that `calls:` an external system cannot run
  #   `:in_transaction`: the call cannot be rolled back with the append.
  # - **P3.** A policy or an effect delivered `:at_least_once` names its
  #   `idempotency`, what makes a second delivery harmless. A process manager does
  #   not: its commands and timers take keys the library derives from the run, so a
  #   replay or a second delivery repeats nothing (v2 §17). v2 §4.6 writes one
  #   without `idempotency`, and this is why it compiles. `idempotency` names its
  #   `key` and its `owner` (plan EP4), and only an effect's owner is `:downstream`:
  #   a policy and a process manager issue commands to this engine, never to a
  #   system that could keep a key. An effect's owner is never `:infrastructure`:
  #   the engine keys the commands a reaction issues, by the event's id, and an
  #   effect's call is not one — so `:infrastructure` also keys on `:event_id`.
  # - **P4.** A process manager starts on at least one event and correlates on at
  #   least one field, each named once: with none, every run would share one record,
  #   one state and one set of timers, and the first ending would end it for all. Its triggers are
  #   events or its own timers; its `sets:` and `cancels:` name its own timers; a
  #   timer fires after `wait:` or `at:` a `:timestamp` field of the state, exactly
  #   one of them; what it issues is a command of this contract; it is delivered
  #   `:at_least_once`, since it runs from the log in order.
  # - **P5.** A read model projects events of this contract or events it consumes; a
  #   query reads a read model of this contract.
  # - **P6.** A read model that names its `table:` names its `key:` too, and only one
  #   that does (#472): the key is the primary key of the schema its `Row` becomes, and
  #   what a projection's `on_conflict` targets, so a second delivery or a rebuild
  #   writes no second row. The key's fields are row fields, each named once, never
  #   optional, personal or a list: a key a row may lack, one an erasure blanks, or
  #   one that is no single column cannot tell rows apart. A table is a plain SQL
  #   name of at most 63 bytes, not the engine's or Oban's, and no two read models of
  #   a contract share one; two of different contracts are the links'. That a key field's domain
  #   value is one value, not one made of fields, needs the domain and is the links'.
  @moduledoc false

  alias EhosContract.DslRules
  alias EhosContract.Contract.Rules

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
      Enum.flat_map(declarations.read_models, &table/1),
      shared_tables(declarations.read_models),
      Enum.flat_map(declarations.queries, &query(&1, read_models))
    ])
  end

  defp policy(policy, events, commands) do
    where = "policy #{inspect(policy.name)}"

    handles(where, policy, policy.handles, events) ++
      issues("P1", where, policy, policy.issues, commands) ++
      idempotent(where, policy) ++ not_downstream(where, policy)
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

    handles(where, effect, effect.handles, events) ++
      in_transaction ++ idempotent(where, effect) ++ not_infrastructure(where, effect)
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

    # Plan DD, C1 (#304): as a process module's (R2), a run's key names each field once.
    repeated =
      for field <- pm.correlate |> DslRules.duplicates(& &1) |> Enum.uniq() do
        {"P4: #{where} correlates on #{inspect(field)} twice; a run's key names each field once",
         pm}
      end

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

    starts ++
      uncorrelated ++
      repeated ++
      triggers ++ references ++ timer_shape ++ issued ++ delivery ++ not_downstream(where, pm)
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

  defp table(%{table: nil, key: []}), do: []

  defp table(%{table: nil} = read_model) do
    [
      {"P6: read model #{inspect(read_model.name)} declares key: #{inspect(read_model.key)} " <>
         "and no table:; a key is the primary key of the table its rows are kept in", read_model}
    ]
  end

  defp table(%{key: []} = read_model) do
    [
      {"P6: read model #{inspect(read_model.name)} keeps its rows in table " <>
         "#{inspect(read_model.table)} and declares no key:; name the row fields that make a " <>
         "row unique", read_model}
      | table_name(read_model)
    ]
  end

  defp table(read_model), do: table_name(read_model) ++ key(read_model)

  # Postgres cuts a name longer than 63 bytes short without a word, so two long
  # names could be one table; and a read model's `reset/0` deletes every row of its
  # table, so it never names the engine's own, the log among them, or Oban's.
  @max_table 63
  @reserved ~w(schema_migrations oban_jobs oban_peers)

  defp table_name(%{table: table} = read_model) do
    where = "P6: read model #{inspect(read_model.name)} keeps its rows in table #{inspect(table)}"

    cond do
      not Regex.match?(~r/\A[A-Za-z_][A-Za-z0-9_]*\z/, table) ->
        [
          {"#{where}, which is not a table name: letters, digits and _, not starting with a " <>
             "digit", read_model}
        ]

      byte_size(table) > @max_table ->
        [
          {"#{where}, longer than the #{@max_table} bytes Postgres keeps of a name", read_model}
        ]

      String.starts_with?(String.downcase(table), "ehos_contract_") or
          String.downcase(table) in @reserved ->
        [
          {"#{where}, which is the engine's or Oban's; a read model's reset/0 would delete " <>
             "its rows", read_model}
        ]

      true ->
        []
    end
  end

  defp key(%{key: key} = read_model) do
    where = "read model #{inspect(read_model.name)}"
    fields = Map.new(read_model.fields, &{&1.name, &1})

    twice =
      for {name, count} <- Enum.frequencies(key), count > 1 do
        {"P6: #{where} names #{inspect(name)} twice in its key", read_model}
      end

    unfit =
      for name <- Enum.uniq(key) do
        case Map.fetch(fields, name) do
          :error ->
            {"P6: #{where} has #{inspect(name)} in its key, which is not a field of its row",
             read_model}

          {:ok, field} ->
            case unfit_key(field) do
              nil -> nil
              why -> {"P6: #{where} has #{inspect(name)} in its key, #{why}", field}
            end
        end
      end

    twice ++ Enum.reject(unfit, &is_nil/1)
  end

  defp unfit_key(%{optional: true}), do: "which is optional; every row has its key"

  defp unfit_key(%{personal: personal}) when personal not in [nil, false],
    do: "which is personal; an erasure would leave rows no key tells apart"

  defp unfit_key(%{type: {:list, _}}), do: "which is a list; a key field is one value"
  defp unfit_key(_field), do: nil

  defp shared_tables(read_models) do
    for {table, [_, _ | _] = sharing} <-
          read_models |> Enum.filter(& &1.table) |> Enum.group_by(& &1.table),
        read_model <- tl(sharing) do
      {"P6: read model #{inspect(read_model.name)} keeps its rows in table #{inspect(table)}, " <>
         "as read model #{inspect(hd(sharing).name)} does; each read model has a table of its own",
       read_model}
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

  # Plan DD, C1 (#304): `handles: []` meets `required:`, and a policy or an effect that
  # handles nothing never runs; a policy's `issues:` would be permitted all the same.
  defp handles(where, declaration, [], _events) do
    [
      {"P1: #{where} handles no event, so it never runs; name the events it reacts to",
       declaration}
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

  defp not_downstream(where, %{idempotency: idempotency} = declaration) do
    case idempotency && {idempotency[:owner], idempotency[:key]} do
      {:downstream, _key} ->
        [
          {"P3: #{where} issues commands to this engine, so no system downstream keeps its " <>
             "idempotency; its owner is :self or :infrastructure", declaration}
        ]

      {:infrastructure, key} when key != :event_id ->
        [
          {"P3: #{where} is kept idempotent by the engine, which keys what it issues by the " <>
             "event's id; its key is :event_id, not #{inspect(key)}", declaration}
        ]

      _ ->
        []
    end
  end

  # The engine keys only the commands a reaction issues (`Consumer.reaction_key/5`);
  # an effect's call goes to a system the engine knows nothing of.
  defp not_infrastructure(where, %{idempotency: idempotency} = declaration) do
    if idempotency[:owner] == :infrastructure,
      do: [
        {"P3: #{where} calls outside the engine, which keys only the commands a reaction " <>
           "issues; its owner is :self or :downstream", declaration}
      ],
      else: []
  end
end
