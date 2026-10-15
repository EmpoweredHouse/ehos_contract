defmodule EhOsContract.View do
  # A domain as a tree, for a terminal (ESDM's `view`; plan EL2): the domain, its
  # contexts, the contracts in each, and in each contract its units with their
  # commands and events, its consumers, read models, queries and domain services.
  # `mix eh_os_contract.view` prints it.
  #
  # ESDM's tree goes domain → context → unit; here a contract stands between the
  # context and its units, since a contract is what a context holds (v2 §4.1). Each
  # row is a kind, a name and what connects it: `→` what it produces or reads, `←`
  # what it is produced by or takes. `details: true` adds what a row declares
  # underneath it — identity, fields, invariants, constraints.
  #
  # The domain's process modules follow its contexts (plan DD, P2e, #220): each with its
  # stages in order and, in each, the events it includes, by the contract that declares
  # them. A process crosses contexts, so it hangs under the domain, not under one.
  #
  # Everything comes in declaration order, as every reader of the model prints
  # (v2 §9); labels are the client's, printed as declared.
  @moduledoc false

  @typep tree :: {String.t(), [String.t()], [tree()]}

  @doc """
  The tree of `domain`, a domain module or its model, with `modules`, the v2
  contract modules and process modules naming it, or their models. `details: true`
  adds each row's declarations; `path:` keeps one branch, `[context]` or
  `[context, unit]`, and leaves the process modules out.
  """
  @spec render(module() | map(), [module() | map()], keyword()) :: String.t()
  def render(domain, modules, opts \\ []) do
    domain = EhOsContract.Model.fetch(domain)

    {processes, contracts} =
      modules
      |> Enum.map(&EhOsContract.Model.fetch/1)
      |> Enum.filter(&(&1.domain == domain.module))
      |> Enum.split_with(&(&1.kind == :process))

    details? = Keyword.get(opts, :details, false)

    {context_filter, unit_filter} =
      case Keyword.get(opts, :path, []) do
        [] -> {nil, nil}
        [context] -> {context, nil}
        [context, unit | _] -> {context, unit}
      end

    types = Map.new(domain.subdomains, &{&1.name, &1.type})
    known!(domain, contracts, context_filter, unit_filter)

    contexts =
      for context <- domain.contexts, context_filter in [nil, context.name] do
        mine = Enum.filter(contracts, &(&1.context == context.name))

        count =
          case length(mine) do
            0 -> "no contract"
            1 -> "1 contract"
            n -> "#{n} contracts"
          end

        subdomain = "subdomain #{context.subdomain} (#{Map.get(types, context.subdomain)})"

        {"context #{context.name}  #{context.label} · #{subdomain} · #{count}", [],
         Enum.map(mine, &contract(&1, unit_filter, details?))}
      end

    processes = if context_filter == nil, do: processes, else: []

    root =
      {"domain #{domain.name}  #{plural(length(domain.contexts), "context")} · " <>
         plural(length(contracts), "contract") <> processes_count(processes), [],
       contexts ++ Enum.map(processes, &process(&1, details?))}

    root |> lines("", "") |> Enum.join("\n")
  end

  defp processes_count([]), do: ""
  defp processes_count(processes), do: " · " <> plural(length(processes), "process")

  # A process module: what tells its runs apart, then each stage with what it includes;
  # with details, what ends a run, its deadline and its promises.
  defp process(model, details?) do
    p = EhOsContract.Model.process(model)
    events = EhOsContract.Model.process_events(model)

    details =
      if details? do
        ends = for e <- events, e.terminal, do: e.name

        if(ends == [], do: [], else: ["ends on #{list(ends)}"]) ++
          if(p.deadline, do: ["deadline #{duration(p.deadline)}"], else: []) ++
          for pr <- p.promises do
            within = if pr.within, do: " within #{duration(pr.within)}", else: ""
            or_else = if pr.or_else, do: ", or else #{pr.or_else}", else: ""

            "promise #{pr.name}  #{pr.from} → #{pr.eventually}#{within}#{or_else}" <>
              unverified(pr)
          end
      else
        []
      end

    stages =
      for stage <- p.stages do
        included =
          events
          |> Enum.filter(&(&1.stage == stage.name))
          |> Enum.chunk_by(& &1.contract)
          |> Enum.map_join("; ", fn [first | _] = group ->
            "#{inspect(first.contract)}: #{Enum.map_join(group, ", ", & &1.name)}"
          end)

        {"stage #{stage.name}  ← #{included}", [], []}
      end

    {"process #{p.name}  #{p.label} · one per #{list(p.correlate)} · " <>
       plural(length(p.stages), "stage"), details, stages}
  end

  defp duration(%{amount: amount, unit: unit} = d),
    do: "#{amount} #{if amount == 1, do: unit, else: "#{unit}s"}" <> unverified(d)

  defp unverified(%{unverified: true}), do: " (unverified)"
  defp unverified(_declaration), do: ""

  defp contract(model, unit_filter, details?) do
    children =
      for {name, node} <- declarations(model, details?), unit_filter in [nil, name], do: node

    {"contract #{inspect(model.module)}", [], children}
  end

  # Each row under a contract with the name `path:` keeps it by.
  defp declarations(model, details?) do
    Enum.map(model.units, &{&1.name, unit(model, &1, details?)}) ++
      Enum.map(model.policies, &{&1.name, policy(&1, details?)}) ++
      Enum.map(model.effects, &{&1.name, effect(&1, details?)}) ++
      Enum.map(model.process_managers, &{&1.name, process_manager(&1, details?)}) ++
      Enum.map(model.read_models, &{&1.name, read_model(&1, details?)}) ++
      Enum.map(model.queries, &{&1.name, query(&1, details?)}) ++
      Enum.map(model.domain_services, &{&1.name, domain_service(&1, details?)})
  end

  # A path naming nothing is refused rather than printed as an empty branch.
  defp known!(_domain, _contracts, nil, nil), do: :ok

  defp known!(domain, contracts, context, unit) do
    unless Enum.any?(domain.contexts, &(&1.name == context)),
      do: raise(ArgumentError, "#{inspect(domain.module)} has no context #{inspect(context)}")

    names =
      for c <- contracts, c.context == context, {name, _node} <- declarations(c, false), do: name

    if unit != nil and unit not in names,
      do:
        raise(
          ArgumentError,
          "context #{inspect(context)} has no unit or other declaration #{inspect(unit)}; " <>
            "it has #{inspect(names)}"
        )

    :ok
  end

  defp unit(model, unit, details?) do
    commands = Enum.filter(model.commands, &(&1.unit == unit.name))
    events = Enum.filter(model.events, &(&1.unit == unit.name))

    details =
      if details? do
        ["identity: #{Enum.join(unit.identity, ", ")}"] ++
          Enum.map(unit.consults, &"consults #{&1.event}#{consults(&1)}") ++
          Enum.map(unit.invariants, &"invariant #{&1.name} — #{&1.label}")
      else
        []
      end

    command_rows =
      for command <- commands do
        {"command #{command.name}  → #{Enum.join(command.emits, ", ")}",
         if(details?, do: fields(command.fields) ++ constraints(command), else: []), []}
      end

    event_rows =
      for event <- events do
        by = for c <- commands, event.name in c.emits, do: c.name
        recorded = for actor <- event.recorded_by, do: "recorded by #{actor}"
        from = Enum.join(Enum.map(by, &"#{&1}") ++ recorded, ", ")

        {"event #{event.name}  ← #{from}", if(details?, do: fields(event.fields), else: []), []}
      end

    {"#{unit.kind} #{unit.name}  #{plural(length(commands), "cmd")} · " <>
       plural(length(events), "evt"), details, command_rows ++ event_rows}
  end

  defp consults(%{match: [_ | _] = match}), do: " by #{Enum.join(match, ", ")}"
  defp consults(%{where: where}) when is_binary(where), do: " where #{where}"
  defp consults(_consults), do: ""

  # A reaction's rules (plan EP2) are its details, as a command's constraints are.
  defp policy(policy, details?),
    do:
      {"policy #{policy.name}  ← #{list(policy.handles)} → #{list(policy.issues)}",
       if(details?, do: constraints(policy), else: []), []}

  defp effect(effect, details?) do
    calls = if effect.calls in [nil, []], do: "", else: " → #{list(effect.calls)}"

    {"effect #{effect.name}  ← #{list(effect.handles)}#{calls}",
     if(details?, do: constraints(effect), else: []), []}
  end

  defp process_manager(pm, details?) do
    starts = Enum.map(pm.starts_on, & &1.event)
    ends = if pm.ends_on == [], do: "", else: " · ends on #{list(pm.ends_on)}"
    invariants = for i <- Map.get(pm, :invariants, []), do: "invariant #{i.name} — #{i.label}"

    {"process manager #{pm.name}  ← #{list(starts)}#{ends}",
     if(details?, do: invariants ++ constraints(pm), else: []), []}
  end

  defp read_model(read_model, details?) do
    {"read model #{read_model.name}  ← #{list(read_model.projects)}",
     if(details?, do: fields(read_model.fields), else: []), []}
  end

  defp query(query, details?) do
    {"query #{query.name}  → #{query.reads}",
     if(details?, do: fields(query.params) ++ constraints(query), else: []), []}
  end

  defp domain_service(service, details?) do
    functions =
      for f <- service.functions do
        {"function #{f.name}",
         if(details?, do: Enum.map(f.rules, &"rule #{&1.name} — #{&1.label}"), else: []), []}
      end

    {"domain service #{service.name}  #{plural(length(service.functions), "fn")}", [], functions}
  end

  defp constraints(declaration),
    do: for(c <- Map.get(declaration, :constraints, []), do: "constraint #{c.name} — #{c.label}")

  defp fields(fields), do: for(f <- fields, do: "#{f.name}: #{type(f)}")

  defp type(%{refers_to: entity} = field) when entity != nil,
    do: "#{inspect(field.type)} of #{entity}#{issued(field)}#{optional(field)}"

  defp type(field), do: "#{inspect(field.type)}#{issued(field)}#{optional(field)}"

  defp issued(%{issued_by: external}), do: ", issued by #{external}"
  defp issued(_field), do: ""

  defp optional(%{optional: true}), do: " (optional)"
  defp optional(_field), do: ""

  defp list(names), do: names |> List.wrap() |> Enum.join(", ")

  defp plural(1, word), do: "1 #{word}"
  defp plural(n, "process"), do: "#{n} processes"
  defp plural(n, word), do: "#{n} #{word}s"

  @spec lines(tree(), String.t(), String.t()) :: [String.t()]
  defp lines({line, details, children}, prefix, child_prefix) do
    detail_prefix = if children == [], do: child_prefix <> "   ", else: child_prefix <> "│  "

    [prefix <> line] ++
      Enum.map(details, &(detail_prefix <> &1)) ++
      (children
       |> Enum.with_index(1)
       |> Enum.flat_map(fn {child, index} ->
         last? = index == length(children)
         branch = if last?, do: "└─ ", else: "├─ "
         continue = if last?, do: "   ", else: "│  "
         lines(child, child_prefix <> branch, child_prefix <> continue)
       end))
  end
end
