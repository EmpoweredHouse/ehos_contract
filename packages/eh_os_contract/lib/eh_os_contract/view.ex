defmodule EhOsContract.View do
  @moduledoc """
  A domain as a tree, for a terminal (ESDM's `view`; plan EL2): the domain, its
  contexts, the contracts in each, and in each contract its units with their
  commands and events, its consumers, read models, queries and domain services.
  `mix eh_os_contract.view` prints it.

  ESDM's tree goes domain → context → unit; here a contract stands between the
  context and its units, since a contract is what a context holds (v2 §4.1). Each
  row is a kind, a name and what connects it: `→` what it produces or reads, `←`
  what it is produced by or takes. `details: true` adds what a row declares
  underneath it — identity, fields, invariants, projections.

  Everything comes in declaration order, as every reader of the model prints
  (v2 §9); labels are the client's, printed as declared.
  """

  @typep tree :: {String.t(), [String.t()], [tree()]}

  @doc """
  The tree of `domain`, a domain module or its model, with `contracts`, the v2
  contract modules or models naming it. `details: true` adds each row's
  declarations; `path:` keeps one branch, `[context]` or `[context, unit]`.
  """
  @spec render(module() | map(), [module() | map()], keyword()) :: String.t()
  def render(domain, contracts, opts \\ []) do
    domain = EhOsContract.Model.fetch(domain)

    contracts =
      contracts
      |> Enum.map(&EhOsContract.Model.fetch/1)
      |> Enum.filter(&(&1.domain == domain.module))

    details? = Keyword.get(opts, :details, false)

    {context_filter, unit_filter} =
      case Keyword.get(opts, :path, []) do
        [] -> {nil, nil}
        [context] -> {context, nil}
        [context, unit | _] -> {context, unit}
      end

    contexts =
      for context <- domain.contexts, context_filter in [nil, context.name] do
        mine = Enum.filter(contracts, &(&1.context == context.name))

        count =
          case length(mine) do
            0 -> "no contract"
            1 -> "1 contract"
            n -> "#{n} contracts"
          end

        {"context #{context.name}  #{context.label} · #{context.subdomain} · #{count}", [],
         Enum.map(mine, &contract(&1, unit_filter, details?))}
      end

    root =
      {"domain #{domain.name}  #{plural(length(domain.contexts), "context")} · " <>
         plural(length(contracts), "contract"), [], contexts}

    root |> lines("", "") |> Enum.join("\n")
  end

  defp contract(model, unit_filter, details?) do
    process = if model.process, do: "  process #{model.process.name}", else: ""

    children =
      Enum.filter(
        Enum.map(model.units, &unit(model, &1, details?)) ++
          Enum.map(model.policies, &policy/1) ++
          Enum.map(model.effects, &effect/1) ++
          Enum.map(model.process_managers, &process_manager/1) ++
          Enum.map(model.read_models, &read_model(&1, details?)) ++
          Enum.map(model.queries, &query(&1, details?)) ++
          Enum.map(model.domain_services, &domain_service(&1, details?)),
        fn {_line, _details, _children} = node ->
          unit_filter == nil or named?(node, unit_filter)
        end
      )

    {"contract #{inspect(model.module)}#{process}", [], children}
  end

  # A branch kept by `path:` is a unit, a consumer or anything else named there.
  defp named?({line, _details, _children}, name),
    do: line |> String.split("  ") |> hd() |> String.split(" ") |> List.last() == "#{name}"

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
         if(details?, do: fields(command.fields), else: []), []}
      end

    event_rows =
      for event <- events do
        by = for c <- commands, event.name in c.emits, do: c.name
        recorded = for actor <- event.recorded_by, do: "recorded by #{actor}"
        from = Enum.join(Enum.map(by, &"#{&1}") ++ recorded, ", ")
        stage = if event.stage, do: " · stage #{event.stage}", else: ""

        {"event #{event.name}  ← #{from}#{stage}",
         if(details?, do: fields(event.fields), else: []), []}
      end

    {"#{unit.kind} #{unit.name}  #{plural(length(commands), "cmd")} · " <>
       plural(length(events), "evt"), details, command_rows ++ event_rows}
  end

  defp consults(%{match: [_ | _] = match}), do: " by #{Enum.join(match, ", ")}"
  defp consults(%{where: where}) when is_binary(where), do: " where #{where}"
  defp consults(_consults), do: ""

  defp policy(policy),
    do: {"policy #{policy.name}  ← #{list(policy.handles)} → #{list(policy.issues)}", [], []}

  defp effect(effect) do
    calls = if effect.calls in [nil, []], do: "", else: " → #{list(effect.calls)}"
    {"effect #{effect.name}  ← #{list(effect.handles)}#{calls}", [], []}
  end

  defp process_manager(pm) do
    starts = Enum.map(pm.starts_on, & &1.event)
    ends = if pm.ends_on == [], do: "", else: " · ends on #{list(pm.ends_on)}"
    {"process manager #{pm.name}  ← #{list(starts)}#{ends}", [], []}
  end

  defp read_model(read_model, details?) do
    {"read model #{read_model.name}  ← #{list(read_model.projects)}",
     if(details?, do: fields(read_model.fields), else: []), []}
  end

  defp query(query, details?) do
    {"query #{query.name}  → #{query.reads}", if(details?, do: fields(query.params), else: []),
     []}
  end

  defp domain_service(service, details?) do
    functions =
      for f <- service.functions do
        {"function #{f.name}",
         if(details?, do: Enum.map(f.rules, &"rule #{&1.name} — #{&1.label}"), else: []), []}
      end

    {"domain service #{service.name}  #{plural(length(service.functions), "fn")}", [], functions}
  end

  defp fields(fields), do: for(f <- fields, do: "#{f.name}: #{type(f)}")

  defp type(%{refers_to: entity} = field) when entity != nil,
    do: "#{inspect(field.type)} of #{entity}#{optional(field)}"

  defp type(field), do: "#{inspect(field.type)}#{optional(field)}"

  defp optional(%{optional: true}), do: " (optional)"
  defp optional(_field), do: ""

  defp list(names), do: names |> List.wrap() |> Enum.join(", ")

  defp plural(1, word), do: "1 #{word}"
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
