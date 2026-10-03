defmodule EhOsContract.Contract.Rules.Fields do
  @moduledoc """
  F1–F9 of v2 §6: the fields of every struct a contract declares — a unit's or a
  process manager's state, a command, an event, a read model's row, a query's
  parameters, and a published event this contract consumes.

  - **F1.** Field names are unique within a struct, and none starts with `__`,
    which the generated structs keep for themselves (`__meta__`). Since the review
    of the domain's names, a field's name is snake_case, as every other name is
    (N1): it is a key of the struct, of the JSON Schema and the payload, a column of
    a read model's row, and a label on the unit's graph, where `:"a|b"` broke the
    edge it named. A unit's `identity` is held to the same, named once, since it is
    a field of the unit's state, commands and events.
  - **F2.** A type is well formed: a built-in type, `{:list, type}`, a non-empty
    `{:enum, members}` with no member twice, the name of a domain value, or
    `{:id, entity}`, the identifier of a domain entity. Whether that value or entity
    exists is the domain's to say, and a Mix compiler checks it (L3, X3).
  - **F3.** Only a state gives a field a `default:`.
  - **F4.** A field that tells which run an event belongs to — named in the
    process's `correlate`, or in the `correlate` of a process manager handling the
    event — is neither `optional:` nor `personal:`. Identity fields are injected
    required and not personal, so they satisfy this by construction.
  - **F5.** `personal: f` names `f`, a required, non-personal `:id` field of the
    same struct that declares `subject:`. Whether the subject exists is X3's.
  - **F6.** A unit's identity is injected into its state, commands and events;
    declaring one of those fields there again is an error.
  - **F7.** A field whose value the library keeps outside the log is not personal,
    since erasure reaches only what the log encrypts (v2 §14): a process manager's
    state, stored in `eh_os_contract_process_managers`, and a query's or a command's
    `scope` field, whose value goes into every authorization decision. A parameter
    takes no `personal:` at all, so here F7 refuses only a manager's state; a
    domain value holding personal data in either place is the domain's to see (L3).
  - **F8** (issue #96). A field a run or a process manager's record is told by — an
    event's field F4 names, and a process manager's state field its `correlate` names —
    is an `:id`, `{:id, entity}` or a domain value resting on `:id`. Its value goes into
    an index (`eh_os_contract_event_runs`, the process managers' primary key), and only
    an `:id` has a length bound, 255 bytes. Here a built-in type or a list is refused;
    a domain value is checked between modules, where the domain is known (L3).
  - **F9** (issue #96). A unit's identity, a process's `correlate` and a process
    manager's `correlate` each have at most `EhOsContract.Key.max_fields/0` fields: the
    key they make is one btree entry, and seven `:id` fields at their bound overflow it.
  """

  alias EhOsContract.Domain
  alias EhOsContract.DslRules
  alias EhOsContract.Contract.Rules

  require EhOsContract.Domain.Rules

  @built_in Domain.Rules.built_in_types()

  @doc false
  @spec check(map()) :: [DslRules.violation()]
  def check(declarations) do
    correlated = correlated(declarations)

    structs =
      for {where, fields, injected, kind} <- structs(declarations),
          violation <- struct_violations(where, fields, injected, kind, correlated) do
        violation
      end

    returns =
      for {where, function} <- returns(declarations),
          problem <-
            if(function.returns,
              do: type_problems(function.returns.type),
              else: ["nothing: say what it returns with `returns type`"]
            ) do
        {"F2: #{where} returns #{problem}", function.returns || function}
      end

    structs ++
      returns ++
      identities(declarations) ++
      outside_the_log(declarations) ++ correlation_types(declarations) ++ keys(declarations)
  end

  @doc """
  Every field a run or a process manager's record is told by, as `{where, field}`: an
  event's field that the process's `correlate`, or the `correlate` of a process manager
  handling the event, names, and a process manager's state field its own `correlate`
  names. F8 holds each to `:id`, here and, for a domain value, between modules (L3).
  """
  @spec correlation_fields(map()) :: [{String.t(), struct()}]
  def correlation_fields(d) do
    correlated = correlated(d)

    events =
      for u <- d.units,
          e <- Rules.events(u),
          f <- e.fields,
          {name, by} <- Map.get(correlated, e.name, []),
          f.name == name do
        {"event #{inspect(e.name)}, field #{inspect(f.name)} tells which run of #{by} the " <>
           "event belongs to", f}
      end
      # The process and a manager may both name a field: one finding for it.
      |> Enum.uniq_by(fn {_where, f} -> f end)

    managers =
      for pm <- d.process_managers, f <- Rules.state_fields(pm.state), f.name in pm.correlate do
        {"process manager #{inspect(pm.name)}, state, field #{inspect(f.name)} is what it " <>
           "correlates on", f}
      end

    events ++ managers
  end

  # A domain value is the domain's to say, between modules; any other type is known here.
  defp correlation_types(d) do
    for {where, field} <- correlation_fields(d),
        not Domain.Rules.is_id(field.type),
        not (is_atom(field.type) and field.type not in @built_in) do
      {"F8: #{where}, so its value is part of an index key, and it is #{inspect(field.type)}; " <>
         "correlate only on an :id, whose length is bounded", field}
    end
  end

  defp keys(d) do
    max = EhOsContract.Key.max_fields()

    keyed =
      for(u <- d.units, do: {"#{u.kind} #{inspect(u.name)}: identity", u.identity, u}) ++
        for(p <- d.processes, do: {"process #{inspect(p.name)}: correlate", p.correlate, p}) ++
        for pm <- d.process_managers,
            do: {"process manager #{inspect(pm.name)}: correlate", pm.correlate, pm}

    for {where, fields, at} <- keyed, length(fields) > max do
      {"F9: #{where} has #{length(fields)} fields, and a key has at most #{max}: it is one " <>
         "index entry, which more fields of an :id at its bound would overflow", at}
    end
  end

  # A unit's identity is a field injected into its state, commands and events, so its
  # names are held to what a declared field's are (F1), at the unit.
  defp identities(d) do
    for u <- d.units, violation <- identity_violations(u), do: violation
  end

  defp identity_violations(unit) do
    where = "F1: #{unit.kind} #{inspect(unit.name)}: identity"

    form =
      for name <- unit.identity do
        cond do
          is_atom(name) and String.starts_with?(Atom.to_string(name), "__") ->
            {"#{where} #{inspect(name)} starts with __, which the generated struct keeps for " <>
               "itself", unit}

          not DslRules.name?(name) ->
            {"#{where} #{inspect(name)} is not snake_case", unit}

          true ->
            nil
        end
      end

    twice =
      for name <- DslRules.duplicates(unit.identity, & &1),
          do: {"#{where} names #{inspect(name)} twice", unit}

    Enum.reject(form, &is_nil/1) ++ twice
  end

  @doc """
  Every function of a domain service, as `{where, function}`, for the type it
  returns: F2 here, X3 between modules.
  """
  @spec returns(map()) :: [{String.t(), struct()}]
  def returns(d) do
    for s <- d.domain_services,
        f <- s.functions,
        do: {"domain service #{inspect(s.name)}, function #{inspect(f.name)}", f}
  end

  @doc """
  The fields F7 keeps from being personal, as `{where, field, why}`: every field of a
  process manager's state, and every query's `scope` parameter. The rules between
  modules read it too, for a domain value that holds personal data (L3).
  """
  @spec outside_the_log(map(), :fields) :: [{String.t(), struct(), String.t()}]
  def outside_the_log(d, :fields) do
    managers =
      for pm <- d.process_managers, f <- Rules.state_fields(pm.state) do
        {"process manager #{inspect(pm.name)}, state, field #{inspect(f.name)}", f,
         "a process manager's state is stored outside the log"}
      end

    scopes =
      for q <- d.queries,
          Map.get(q, :scope) != nil,
          f <- q.params,
          f.name == q.scope do
        {"query #{inspect(q.name)}, parameter #{inspect(f.name)}", f,
         "it is the query's scope, whose value is written with every authorization decision"}
      end

    # A command's scope field, the same way (plan E9c). Its identity fields are
    # injected non-personal, so only a declared field can be one.
    commands =
      for u <- d.units,
          c <- u.commands,
          c.scope != nil,
          f <- c.fields,
          f.name == c.scope do
        {"command #{inspect(c.name)}, field #{inspect(f.name)}", f,
         "it is the command's scope, whose value is written with every authorization decision"}
      end

    managers ++ scopes ++ commands
  end

  defp outside_the_log(d) do
    for {where, field, why} <- outside_the_log(d, :fields), Map.get(field, :personal) != nil do
      {"F7: #{where} is personal, and #{why}, where erasure cannot reach it", field}
    end
  end

  @doc """
  Every struct a contract declares, as `{where, declared fields, injected names,
  kind}`: the one list of them, which the rules between modules read too (X3).
  """
  @spec structs(map()) :: [{String.t(), [struct()], [atom()], term()}]
  def structs(d) do
    Enum.concat([
      for(
        u <- d.units,
        do:
          {"#{u.kind} #{inspect(u.name)}, state", Rules.state_fields(u.state), u.identity, :state}
      ),
      for(
        u <- d.units,
        c <- u.commands,
        do: {"command #{inspect(c.name)}", c.fields, u.identity, :command}
      ),
      for(
        u <- d.units,
        e <- Rules.events(u),
        do: {"event #{inspect(e.name)}", e.fields, u.identity, {:event, e.name}}
      ),
      for(
        pm <- d.process_managers,
        do:
          {"process manager #{inspect(pm.name)}, state", Rules.state_fields(pm.state), [], :state}
      ),
      for(r <- d.read_models, do: {"read model #{inspect(r.name)}", r.fields, [], :row}),
      for(q <- d.queries, do: {"query #{inspect(q.name)}", q.params, [], :params}),
      for(
        s <- d.domain_services,
        f <- s.functions,
        do:
          {"domain service #{inspect(s.name)}, function #{inspect(f.name)}", f.arguments, [],
           :arguments}
      ),
      for(
        c <- d.consumes,
        is_binary(c.from),
        do: {"consumed event #{inspect(c.from)}", c.fields, [], :consumed}
      )
    ])
  end

  # For each local event, the correlation fields that apply to it and who names them.
  defp correlated(d) do
    process =
      for p <- d.processes, name <- p.correlate, e <- Rules.local_events(d), into: [] do
        {e.name, name, "process #{inspect(p.name)}"}
      end

    managers =
      for pm <- d.process_managers,
          event <- handled(pm),
          name <- pm.correlate,
          into: [] do
        {event, name, "process manager #{inspect(pm.name)}"}
      end

    Enum.group_by(process ++ managers, &elem(&1, 0), &Tuple.delete_at(&1, 0))
  end

  defp handled(pm) do
    Enum.map(pm.starts_on, & &1.event) ++
      Enum.map(pm.on, & &1.event) ++ Enum.map(pm.ends_on, & &1.event)
  end

  defp struct_violations(where, fields, injected, kind, correlated) do
    by_name = Map.new(fields, &{&1.name, &1})

    reserved =
      for f <- fields, is_atom(f.name), String.starts_with?(Atom.to_string(f.name), "__") do
        {"F1: #{where}: field #{inspect(f.name)} starts with __, which the generated struct keeps " <>
           "for itself", f}
      end

    # A domain service's argument is a name N1 refuses already, as an argument.
    form =
      for f <- fields,
          kind != :arguments,
          not (is_atom(f.name) and String.starts_with?(Atom.to_string(f.name), "__")),
          not DslRules.name?(f.name) do
        {"F1: #{where}: field #{inspect(f.name)} is not snake_case", f}
      end

    twice =
      for f <- DslRules.duplicates(fields, & &1.name) do
        {"F1: #{where} declares field #{inspect(f.name)} twice", f}
      end

    redeclared =
      for f <- fields, f.name in injected do
        {"F6: #{where} declares #{inspect(f.name)}, which the unit's identity already injects", f}
      end

    types =
      for f <- fields, problem <- type_problems(f.type) do
        {"F2: #{where}, field #{inspect(f.name)}: #{problem}", f}
      end

    defaults =
      for f <- fields, kind != :state, Map.get(f, :default) != nil do
        {"F3: #{where}, field #{inspect(f.name)} has a default, which only a state may have", f}
      end

    correlation =
      case kind do
        {:event, event} ->
          for {name, by} <- Map.get(correlated, event, []),
              f = Map.get(by_name, name),
              f != nil and (f.optional or f.personal != nil) do
            {"F4: #{where}, field #{inspect(name)} tells which run of #{by} the event belongs to, " <>
               "so it cannot be #{if f.optional, do: "optional", else: "personal"}", f}
          end

        _ ->
          []
      end

    personal = for f <- fields, v <- personal_violations(where, f, by_name), do: v

    reserved ++ form ++ twice ++ redeclared ++ types ++ defaults ++ correlation ++ personal
  end

  defp personal_violations(where, field, by_name) do
    case Map.get(field, :personal) do
      nil ->
        []

      target ->
        where = "#{where}, field #{inspect(field.name)}"

        case Map.fetch(by_name, target) do
          :error ->
            [
              {"F5: #{where} is personal to #{inspect(target)}, which is not a field declared here",
               field}
            ]

          {:ok, %{optional: true}} ->
            [{"F5: #{where} is personal to #{inspect(target)}, which is optional", field}]

          {:ok, %{type: type, subject: subject, personal: nil}}
          when subject != nil and Domain.Rules.is_id(type) ->
            []

          {:ok, _} ->
            [
              {"F5: #{where} is personal to #{inspect(target)}, which is not an :id field " <>
                 "declaring a subject", field}
            ]
        end
    end
  end

  @doc """
  What is wrong with a field's type, as far as a contract can tell on its own: any
  atom may be a domain value, and only the domain can say which are (X3).
  """
  @spec type_problems(term()) :: [String.t()]
  def type_problems(type) when is_atom(type) and type not in [nil, true, false], do: []

  def type_problems({:id, entity}) when is_atom(entity) and entity not in [nil, true, false],
    do: []

  def type_problems({:list, inner}), do: type_problems(inner)
  def type_problems({:enum, _} = enum), do: Domain.Rules.type_problems(enum, MapSet.new())
  def type_problems(other), do: ["#{inspect(other)} is not a type"]
end
