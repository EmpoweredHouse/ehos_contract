defmodule EhOsContract.Contract.Doc do
  @moduledoc """
  The documentation a generated behaviour carries (plan EP3): what the contract says of
  each callback, where whoever writes the implementation reads it — `h`, the editor,
  and a model generating the code.

  A callback's `@doc` gives its declaration's label and source, what it may produce
  (the events a command emits, the commands a reaction issues), the rules that hold
  there and the scenarios it runs. Each rule says which rung of the contract's ladder
  it stands on: a scenario shows it (it refuses on it, or it `illustrates:` it), or it
  is prose alone. A behaviour's `@moduledoc` adds the declaration's label, source and
  rules to the sentence that says how it is bound.

  The text is built from the contract's model, and only from it, so the contract stays
  the one place each sentence is written. Labels are quoted as declared, in the
  client's language; the sentences around them are the engine's, in English.
  """

  @doc """
  The `@moduledoc` of the behaviour of the declaration `name` of `kind`: `intro`,
  the sentence the generator writes, then the declaration's label, source and rules.
  """
  @spec moduledoc(map(), atom(), atom(), String.t()) :: String.t()
  def moduledoc(model, kind, name, intro) do
    declaration = declaration(model, kind, name)

    paragraphs([
      intro,
      labelled(kind, declaration),
      rules_section("Rules", rules(model, kind, declaration))
    ])
  end

  @doc """
  The `@doc` of the callback `callback` of the declaration `name` of `kind`.
  """
  @spec callback(map(), atom(), atom(), atom()) :: String.t()
  def callback(model, kind, name, callback) when kind in [:aggregate, :dcb] do
    command = Enum.find(model.commands, &(&1.unit == name and &1.name == callback))
    unit = declaration(model, kind, name)
    own = for s <- model.scenarios, s.trigger.kind == :command, s.trigger.name == callback, do: s

    paragraphs([
      "Decides command `#{command.name}`#{label(command)}#{source(command)}.",
      list("Emits, when it accepts", Enum.map(command.emits, &event_line(model, &1))),
      rules_section("Refuses with `reject/1` on", command_rules(model, kind, unit, command)),
      scenarios(own)
    ])
  end

  def callback(model, kind, name, callback) when kind in [:policy, :process_manager] do
    declaration = declaration(model, kind, name)
    timer? = kind == :process_manager and Enum.any?(declaration.timers, &(&1.name == callback))

    issues =
      issued(kind, declaration, callback)
      |> Enum.map(&command_line(model, &1))

    paragraphs([
      if(timer?,
        do:
          "Fires on timer `#{callback}`#{timer_source(declaration, callback)} of #{word(kind)} " <>
            "`#{name}`#{label(declaration)}#{source(declaration)}.",
        else:
          "Reacts to `#{callback}`#{event_label(model, callback)}, for #{word(kind)} " <>
            "`#{name}`#{label(declaration)}#{source(declaration)}."
      ),
      list("May issue", issues),
      unless(timer?, do: idempotency(declaration)),
      rules_section("Keeps", rules(model, kind, declaration)),
      scenarios(
        for s <- model.scenarios,
            s.target == %{kind: kind, name: name},
            s.trigger.name == callback,
            do: s
      )
    ])
  end

  def callback(model, :effect, name, callback) do
    effect = declaration(model, :effect, name)
    calls = Enum.map(List.wrap(effect.calls), &"`#{&1}`")

    paragraphs([
      "Reacts to `#{callback}`#{event_label(model, callback)}, for effect " <>
        "`#{name}`#{label(effect)}#{source(effect)}.",
      if(calls != [], do: "Calls #{Enum.join(calls, ", ")}."),
      idempotency(effect),
      rules_section("Keeps", rules(model, :effect, effect))
    ])
  end

  def callback(model, :read_model, name, callback) do
    read_model = declaration(model, :read_model, name)

    "Projects `#{callback}`#{event_label(model, callback)} into read model " <>
      "`#{name}`#{label(read_model)}#{source(read_model)}."
  end

  def callback(model, :query, name, _callback) do
    query = declaration(model, :query, name)

    paragraphs([
      "Answers query `#{name}`#{label(query)}#{source(query)}, from read model `#{query.reads}`.",
      rules_section("Keeps", rules(model, :query, query)),
      scenarios(for s <- model.scenarios, s.target == %{kind: :query, name: name}, do: s)
    ])
  end

  def callback(model, :domain_service, name, callback) do
    service = declaration(model, :domain_service, name)
    function = Enum.find(service.functions, &(&1.name == callback))

    paragraphs([
      "Function `#{callback}`#{label(function)} of domain service `#{name}`.",
      rules_section("Keeps", for(r <- function.rules, do: {"rule", r, examples(r)}))
    ])
  end

  @doc """
  What a reaction's `idempotency` asks of its code (plan EP4): who keeps a second
  delivery harmless, and on what key; `nil` for a reaction without one. The same
  sentence is the reaction's page's.
  """
  @spec idempotency(map()) :: String.t() | nil
  def idempotency(%{idempotency: %{key: key, owner: owner}}) do
    "A second delivery is harmless on `#{key}`: " <>
      case owner do
        :self -> "this code keys what it writes by it."
        :downstream -> "the system it calls is given the key and ignores a repeat."
        :infrastructure -> "the engine keys what it does by it, with no code here."
      end
  end

  def idempotency(_reaction), do: nil

  @doc """
  The `@doc` of `evolve/2` of a declaration of `kind`: which events it folds into
  the state, and what reads it next.
  """
  @spec evolve(atom(), [atom()]) :: String.t()
  def evolve(kind, events) do
    next = if kind == :process_manager, do: "reaction", else: "decision"

    "Folds an event into the state, so the next #{next} sees it: " <>
      Enum.map_join(events, ", ", &"`#{&1}`") <> "."
  end

  # --- the parts --------------------------------------------------------------------

  defp declaration(model, kind, name) when kind in [:aggregate, :dcb],
    do: Enum.find(model.units, &(&1.name == name and &1.kind == kind))

  defp declaration(model, kind, name),
    do: Enum.find(Map.fetch!(model, collection(kind)), &(&1.name == name))

  defp collection(:policy), do: :policies
  defp collection(:effect), do: :effects
  defp collection(:process_manager), do: :process_managers
  defp collection(:read_model), do: :read_models
  defp collection(:query), do: :queries
  defp collection(:domain_service), do: :domain_services

  defp word(:dcb), do: "dynamic consistency boundary"
  defp word(kind), do: kind |> Atom.to_string() |> String.replace("_", " ")

  defp labelled(kind, declaration),
    do:
      "#{String.capitalize(word(kind))} `#{declaration.name}`#{label(declaration)}#{source(declaration)}."

  defp timer_source(pm, name) do
    case Enum.find(pm.timers, &(&1.name == name)) do
      %{source: source} when is_binary(source) -> " (source: #{source})"
      _ -> ""
    end
  end

  # The rules of a declaration, each with the rung it stands on (plan EP2): a unit's
  # invariants are refused on in a scenario (S8); a reaction's and a query's rules are
  # illustrated by one, or are prose alone; an effect's are prose alone, since no
  # scenario runs an effect.
  #
  # An invariant is shown by any scenario of the unit refused on it, whichever command
  # it runs (S8); a command's constraint by that command's (EP3 review: a callback's doc
  # and the moduledoc read the same rung).
  defp rules(model, kind, unit) when kind in [:aggregate, :dcb] do
    invariants =
      for i <- unit.invariants, do: {"invariant", i, refused_in(model, kind, unit, nil, i)}

    constraints =
      for c <- model.commands,
          c.unit == unit.name,
          k <- Map.get(c, :constraints, []),
          do: {"constraint", k, "of command `#{c.name}`, " <> refused_in(model, kind, unit, c, k)}

    invariants ++ constraints
  end

  defp rules(_model, :effect, effect) do
    for c <- Map.get(effect, :constraints, []),
        do: {"constraint", c, "prose alone: no scenario runs an effect"}
  end

  defp rules(model, kind, declaration) when kind in [:policy, :process_manager, :query] do
    for {word, rule} <- EhOsContract.Contract.Rules.Scenarios.illustratable(kind, declaration) do
      illustrated =
        for s <- model.scenarios,
            s.target == %{kind: kind, name: declaration.name},
            rule.name in Map.get(s, :illustrates, []),
            do: s.description

      {word, rule, shown(illustrated, "illustrated by")}
    end
  end

  defp rules(_model, _kind, _declaration), do: []

  defp command_rules(model, kind, unit, command) do
    for(
      i <- unit.invariants,
      i.name in command.rejects,
      do: {"invariant", i, refused_in(model, kind, unit, nil, i)}
    ) ++
      for k <- Map.get(command, :constraints, []),
          do: {"constraint", k, refused_in(model, kind, unit, command, k)}
  end

  defp refused_in(model, kind, unit, command, rule) do
    model.scenarios
    |> Enum.filter(&(&1.target == %{kind: kind, name: unit.name} and &1.rejected == rule.name))
    |> Enum.filter(&(command == nil or &1.trigger.name == command.name))
    |> Enum.map(& &1.description)
    |> shown("refused in")
  end

  defp shown([], _verb), do: "prose alone: no scenario shows it yet"

  defp shown(descriptions, verb),
    do: "#{verb} " <> Enum.map_join(descriptions, ", ", &~s|"#{&1}"|)

  defp rules_section(_title, []), do: nil

  defp rules_section(title, rules) do
    lines =
      for {word, rule, rung} <- rules,
          do: "- #{word} `#{rule.name}`#{label(rule)}#{source(rule)} — #{rung}"

    Enum.join(["#{title}:" | lines], "\n")
  end

  defp issued(:policy, policy, _callback), do: List.wrap(policy.issues)

  defp issued(:process_manager, pm, callback) do
    (Enum.filter(pm.starts_on ++ pm.on, &(&1.event == callback)) ++
       Enum.filter(pm.timers, &(&1.name == callback)))
    |> Enum.flat_map(&List.wrap(Map.get(&1, :issues, [])))
    |> Enum.uniq()
  end

  defp scenarios([]), do: nil

  defp scenarios(scenarios),
    do:
      Enum.join(
        ["Scenarios:" | Enum.map(scenarios, &~s|- "#{&1.description}"#{outcome(&1)}|)],
        "\n"
      )

  defp outcome(s) do
    parts =
      [
        if(s.rejected, do: "rejected on `#{s.rejected}`"),
        if(Map.get(s, :expect, []) != [], do: "emits " <> names(s.expect, :event)),
        if(Map.get(s, :issues, []) != [], do: "issues " <> names(s.issues, :command)),
        if(Map.get(s, :sets, []) != [], do: "sets " <> Enum.map_join(s.sets, ", ", &"`#{&1}`")),
        if(Map.get(s, :cancels, []) != [],
          do: "cancels " <> Enum.map_join(s.cancels, ", ", &"`#{&1}`")
        ),
        if(Map.get(s, :ended), do: "ends the run"),
        if(Map.has_key?(s, :answers), do: "answers #{length(List.wrap(s.answers))} row(s)"),
        if(Map.has_key?(s, :state), do: "holds " <> fields(s.state))
      ]
      |> Enum.reject(&is_nil/1)

    if parts == [], do: "", else: ": " <> Enum.join(parts, ", ")
  end

  defp fields(data), do: data |> Map.keys() |> Enum.sort() |> Enum.map_join(", ", &"`#{&1}`")

  defp names(items, key), do: Enum.map_join(items, ", ", &"`#{Map.fetch!(&1, key)}`")

  defp event_line(model, name), do: "`#{name}`#{event_label(model, name)}"

  defp command_line(model, name) do
    case Enum.find(model.commands, &(&1.name == name)) do
      nil -> "`#{name}`"
      command -> "`#{name}`#{label(command)}"
    end
  end

  # A local event's label; a consumed one's label is the sibling's or the other
  # application's, which a contract does not compile against, so it says where the
  # event comes from instead.
  defp event_label(model, name) do
    case Enum.find(model.events, &(&1.name == name)) do
      nil -> consumed_from(model, name)
      event -> label(event)
    end
  end

  defp consumed_from(model, name) do
    case EhOsContract.Model.consumed(model, name) do
      {:contract, sibling, _original} ->
        " (consumed from `#{inspect(sibling)}`)"

      {:published, _fields} ->
        from =
          Enum.find_value(model.consumes, &(&1.kind == :published and &1.as == name and &1.from))

        " (received from another application as `#{from}`)"

      nil ->
        ""
    end
  end

  defp examples(rule) do
    case length(Map.get(rule, :examples, [])) do
      1 -> "1 example, which is a test"
      n -> "#{n} examples, each a test"
    end
  end

  defp label(%{label: label}) when is_binary(label), do: ~s| — "#{label}"|
  defp label(_), do: ""

  defp source(declaration) do
    case Map.get(declaration, :source) do
      nil -> ""
      source -> " (source: #{source})"
    end
  end

  defp list(_title, []), do: nil
  defp list(title, items), do: Enum.join(["#{title}:" | Enum.map(items, &"- #{&1}")], "\n")

  defp paragraphs(parts), do: parts |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join("\n\n")
end
