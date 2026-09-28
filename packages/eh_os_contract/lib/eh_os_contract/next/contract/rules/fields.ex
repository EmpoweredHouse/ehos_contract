defmodule EhOsContract.Next.Contract.Rules.Fields do
  @moduledoc """
  F1–F6 of v2 §6: the fields of every struct a contract declares — a unit's or a
  process manager's state, a command, an event, a read model's row, a query's
  parameters, and a published event this contract consumes.

  - **F1.** Field names are unique within a struct, and none starts with `__`,
    which the generated structs keep for themselves (`__meta__`).
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
  """

  alias EhOsContract.Domain
  alias EhOsContract.DslRules
  alias EhOsContract.Next.Contract.Rules

  require EhOsContract.Domain.Rules

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

    structs ++ returns ++ outside_the_log(declarations)
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

    reserved ++ twice ++ redeclared ++ types ++ defaults ++ correlation ++ personal
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
