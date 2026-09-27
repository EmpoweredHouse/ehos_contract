defmodule EhOsContract.Next.Contract.Rules.Names do
  @moduledoc """
  N1 and N2 of v2 §6: names.

  **N1.** Every name is snake_case, and unique within its namespace. Commands,
  events, timers and consumed events share one namespace, because each becomes a
  callback of the same implementation: an aggregate has one per command, a process
  manager one per event and timer (v2 §5). Units are one namespace, whether
  aggregate or boundary; so is each other kind of declaration. A query does not
  take a command's name, since both become a capability `<domain>.<name>` (D14). Invariants and stage
  groups are unique within their unit, and the process's stages and promises within
  the process. A domain service's functions are unique within it, and a function's
  rules within the function.

  **N2.** No name is a word Elixir reserves, and none becomes a callback that
  clashes with a `Kernel` function or special form of the same arity (v2 §4.4): a
  command called `:send` would define `send/2`. Commands and queries are called
  with two arguments; events, timers and consumed events are handled with one or
  with two, depending on who handles them, so both arities are checked. `evolve` is
  the callback every unit has already, so no command or event may take it. Nor may
  a command, an event, a consumed event or a query be called `state` or `row`: an
  implementation aliases its struct by its name, and `State` and `Row` are taken.
  A domain service's function is defined, with its arguments' arity, both by the
  implementation and by the module the contract generates to call it, which is also
  a behaviour: `behaviour_info/1`, `module_info/0,1` and `__info__/1` are taken there,
  and `evolve` is not.
  """

  alias EhOsContract.DslRules
  alias EhOsContract.Next.Contract.Rules

  @reserved ~w(do end fn and or not in when catch rescue after else true false nil)a
  @taken [:evolve]
  @module_functions [behaviour_info: 1, module_info: 0, module_info: 1, __info__: 1]
  @aliases [:state, :row]

  @doc false
  @spec check(map()) :: [DslRules.violation()]
  def check(declarations) do
    snake_case(declarations) ++ unique(declarations) ++ callbacks(declarations)
  end

  # --- N1: snake_case ---------------------------------------------------------------

  defp snake_case(d) do
    for {kind, name, declaration} <- named(d), not snake_case?(name) do
      {"N1: #{kind} #{inspect(name)} is not snake_case", declaration}
    end
  end

  defp snake_case?(name), do: is_atom(name) and Atom.to_string(name) =~ ~r/^[a-z][a-z0-9_]*$/

  # Every declared name, with what it names.
  defp named(d) do
    process = List.first(d.processes)

    Enum.concat([
      for(u <- d.units, do: {unit_kind(u), u.name, u}),
      for(u <- d.units, i <- u.invariants, do: {"invariant", i.name, i}),
      for(u <- d.units, s <- u.stages, do: {"stage", s.name, s}),
      for(c <- Rules.commands(d), do: {"command", c.name, c}),
      for(c <- Rules.commands(d), k <- c.constraints, do: {"constraint", k.name, k}),
      for(q <- d.queries, k <- q.constraints, do: {"constraint", k.name, k}),
      for(e <- Rules.local_events(d), do: {"event", e.name, e}),
      for(p <- d.policies, do: {"policy", p.name, p}),
      for(e <- d.effects, do: {"effect", e.name, e}),
      for(pm <- d.process_managers, do: {"process manager", pm.name, pm}),
      for(pm <- d.process_managers, t <- pm.timers, do: {"timer", t.name, t}),
      for(r <- d.read_models, do: {"read model", r.name, r}),
      for(q <- d.queries, do: {"query", q.name, q}),
      for(s <- d.domain_services, do: {"domain service", s.name, s}),
      for(s <- d.domain_services, f <- s.functions, do: {"function", f.name, f}),
      for(s <- d.domain_services, f <- s.functions, r <- f.rules, do: {"rule", r.name, r}),
      for(
        s <- d.domain_services,
        f <- s.functions,
        a <- f.arguments,
        do: {"argument", a.name, a}
      ),
      for(p <- d.publishes, do: {"publication", p.name, p}),
      for({as, consumes} <- Rules.consumed(d), do: {"consumed event", as, consumes}),
      for(p <- d.processes, do: {"process", p.name, p}),
      if(process, do: for(s <- process.stages, do: {"stage", s.name, s}), else: []),
      if(process, do: for(p <- process.promises, do: {"promise", p.name, p}), else: [])
    ])
  end

  defp unit_kind(%{kind: :aggregate}), do: "aggregate"
  defp unit_kind(%{kind: :dcb}), do: "dcb"

  # --- N1: unique per namespace -----------------------------------------------------

  defp unique(d) do
    process = List.first(d.processes)

    kinds =
      [
        {"units", d.units},
        {"policies", d.policies},
        {"effects", d.effects},
        {"process managers", d.process_managers},
        {"read models", d.read_models},
        {"queries", d.queries},
        {"domain services", d.domain_services},
        {"publications", d.publishes}
      ]
      |> Enum.flat_map(fn {kind, list} ->
        for duplicate <- DslRules.duplicates(list, & &1.name) do
          {"N1: two #{kind} are named #{inspect(duplicate.name)}", duplicate}
        end
      end)

    per_unit =
      Enum.flat_map(d.units, fn unit ->
        invariants =
          for i <- DslRules.duplicates(unit.invariants, & &1.name) do
            {"N1: #{unit_kind(unit)} #{inspect(unit.name)} has two invariants named #{inspect(i.name)}",
             i}
          end

        stages =
          for s <- DslRules.duplicates(unit.stages, & &1.name) do
            {"N1: #{unit_kind(unit)} #{inspect(unit.name)} groups stage #{inspect(s.name)} twice",
             s}
          end

        invariants ++ stages
      end)

    # Plan EL2: a command's constraints, and a query's, are named once each.
    constraints =
      for {kind, owner} <-
            Enum.map(Rules.commands(d), &{"command", &1}) ++ Enum.map(d.queries, &{"query", &1}),
          k <- DslRules.duplicates(owner.constraints, & &1.name) do
        {"N1: #{kind} #{inspect(owner.name)} has two constraints named #{inspect(k.name)}", k}
      end

    in_process =
      if process do
        for(
          s <- DslRules.duplicates(process.stages, & &1.name),
          do: {"N1: process #{inspect(process.name)} has two stages named #{inspect(s.name)}", s}
        ) ++
          for p <- DslRules.duplicates(process.promises, & &1.name),
              do:
                {"N1: process #{inspect(process.name)} has two promises named #{inspect(p.name)}",
                 p}
      else
        []
      end

    per_service =
      for s <- d.domain_services,
          violation <-
            for(
              f <- DslRules.duplicates(s.functions, & &1.name),
              do:
                {"N1: domain service #{inspect(s.name)} has two functions named #{inspect(f.name)}",
                 f}
            ) ++
              for(
                f <- s.functions,
                r <- DslRules.duplicates(f.rules, & &1.name),
                do: {"N1: function #{inspect(f.name)} has two rules named #{inspect(r.name)}", r}
              ),
          do: violation

    kinds ++
      per_unit ++
      per_service ++
      callback_namespace(d) ++ capability_namespace(d) ++ in_process ++ constraints
  end

  # A command and a query are both capabilities, named `<domain>.<name>` (D14), so a
  # query may not take a command's name. Unique across the whole application is the
  # Mix compiler's to check, since it sees every contract (L3).
  defp capability_namespace(d) do
    commands = MapSet.new(Rules.commands(d), & &1.name)

    for q <- d.queries, MapSet.member?(commands, q.name) do
      {"N1: query #{inspect(q.name)} has the name of a command; both are capabilities named " <>
         "<domain>.#{q.name} (D14)", q}
    end
  end

  # Commands, events, timers and consumed events: one namespace. A duplicate is
  # reported at the later declaration, with what the name already belongs to.
  defp callback_namespace(d) do
    entries = callback_entries(d)

    for {name, kind, declaration} = entry <- DslRules.duplicates(entries, &elem(&1, 0)) do
      {_, first, _} = Enum.find(entries, &(elem(&1, 0) == name and &1 != entry))

      {"N1: #{kind} #{inspect(name)} has the name of #{article(first)} #{first}; commands, events, " <>
         "timers and consumed events share one namespace", declaration}
    end
  end

  defp article("event"), do: "an"
  defp article(_), do: "a"

  defp callback_entries(d) do
    Enum.concat([
      for(c <- Rules.commands(d), do: {c.name, "command", c}),
      for(e <- Rules.local_events(d), do: {e.name, "event", e}),
      for(pm <- d.process_managers, t <- pm.timers, do: {t.name, "timer", t}),
      for({as, consumes} <- Rules.consumed(d), do: {as, "consumed event", consumes})
    ])
  end

  # --- N2: reserved words and Kernel clashes ----------------------------------------

  defp callbacks(d) do
    arities =
      Enum.concat([
        for(c <- Rules.commands(d), do: {"command", c.name, [2], c}),
        for(q <- d.queries, do: {"query", q.name, [2], q}),
        for(e <- Rules.local_events(d), do: {"event", e.name, [1, 2], e}),
        for(pm <- d.process_managers, t <- pm.timers, do: {"timer", t.name, [1, 2], t}),
        for({as, consumes} <- Rules.consumed(d), do: {"consumed event", as, [1, 2], consumes}),
        for(
          s <- d.domain_services,
          f <- s.functions,
          do: {"function", f.name, [length(f.arguments)], f}
        )
      ])

    for {kind, name, arities, declaration} <- arities,
        is_atom(name),
        violation <- clash(kind, name, arities, declaration) ++ aliased(kind, name, declaration) do
      violation
    end
  end

  # An implementation aliases each struct it touches by its name, and a unit's state
  # and a read model's row as `State` and `Row` (`EhOsContract.Implementation`).
  defp aliased(kind, name, declaration)
       when kind not in ["timer", "function"] and name in @aliases do
    alias = name |> Atom.to_string() |> Macro.camelize()

    [
      {"N2: #{kind} #{inspect(name)} would be aliased #{alias} in an implementation, which is " <>
         "the alias of a #{if name == :state, do: "unit's state", else: "read model's row"}",
       declaration}
    ]
  end

  defp aliased(_kind, _name, _declaration), do: []

  defp clash(kind, name, arities, declaration) do
    cond do
      name in @reserved ->
        [{"N2: #{kind} #{inspect(name)} is a word Elixir reserves", declaration}]

      # A function is defined in the module the contract generates for its service,
      # which is a behaviour: Elixir defines these there already.
      kind == "function" and {name, hd(arities)} in @module_functions ->
        [
          {"N2: #{kind} #{inspect(name)} would define #{name}/#{hd(arities)}, which every " <>
             "module defines already", declaration}
        ]

      # `evolve/2` is a unit's, and a service's module has none.
      name in @taken and kind != "function" ->
        [
          {"N2: #{kind} #{inspect(name)} would clash with evolve/2, which every unit defines",
           declaration}
        ]

      clash = Enum.find(arities, &kernel?(name, &1)) ->
        [
          {"N2: #{kind} #{inspect(name)} would define #{name}/#{clash}, which clashes with " <>
             "#{kernel_module(name, clash)}.#{name}/#{clash}", declaration}
        ]

      true ->
        []
    end
  end

  @doc false
  # What a function `name/arity` would clash with where a module defines it, for a
  # rule outside the contract's: a domain value's check (D9, plan EL2b). `nil` when
  # nothing.
  @spec elixir_clash(atom(), arity()) :: String.t() | nil
  def elixir_clash(name, arity) do
    cond do
      name in @reserved ->
        "is a word Elixir reserves"

      {name, arity} in @module_functions ->
        "would define #{name}/#{arity}, which every module defines already"

      kernel?(name, arity) ->
        "would define #{name}/#{arity}, which clashes with #{kernel_module(name, arity)}." <>
          "#{name}/#{arity}"

      true ->
        nil
    end
  end

  # Read once, when this module compiles: `{name, arity} => "Kernel"`.
  @kernel for module <- [Kernel.SpecialForms, Kernel],
              export <- module.__info__(:functions) ++ module.__info__(:macros),
              into: %{},
              do: {export, inspect(module)}

  defp kernel?(name, arity), do: Map.has_key?(@kernel, {name, arity})

  defp kernel_module(name, arity), do: Map.get(@kernel, {name, arity})
end
