defmodule EhOsContract.Contract.Rules.Units do
  # A1–A5 and C1 of v2 §6: what a unit decides, and who can ask it to.
  #
  # - **A1.** A command emits something, and only events of its own unit.
  # - **A2.** Every event is emitted by a command of its unit, or declares
  #   `recorded_by:` (D6). Stricter than ESDM on purpose: in an event-sourced log,
  #   an event nothing produces can never occur.
  # - **A3.** A command rejects only invariants of its own unit, and its own
  #   constraints (plan EL2).
  # - **A4.** A dynamic consistency boundary consults at least one event; each one
  #   is an event of this log — its own or a sibling contract's, not one received from
  #   another application (D12) — and says which by `match:`
  #   or `where:`; `match:` names fields of the boundary's identity, which a local
  #   consulted event carries as required, non-personal `:id` fields — its unit's
  #   identity, or fields of its own. Only such fields are tags of an appended event,
  #   and a boundary finds what it consults by its tags. For an event consumed from a
  #   sibling contract the same is X6's, where the sibling is known.
  # - **A5.** A unit, or a process manager, declares its state at most once.
  # - **A8** (plan DD, T2a, #240). What a command `reads:` is named by a field of the
  #   command typed `{:id, entity}` and required: the decision gets the row, and a
  #   command without the identifier could read nothing. Each name is given once, and
  #   no policy or process manager issues such a command: only an actor does.
  #   Whether the entity exists is D6's, where the domain is known.
  # - **A7** (plan EL2). A command's constraints are never named as an invariant of its
  #   unit, and each is in the command's `rejects:`; N1 names each once.
  # - **A6** (plan EM3). An aggregate whose identity is `generated:` has one identity
  #   field, and at least one command that `creates:` it, since nothing else could make
  #   a new one; `creates:` belongs only to such an aggregate's commands.
  # - **C1.** A command can be issued: it names actors in `by:`, or a policy or a
  #   process manager of this contract issues it.
  @moduledoc false

  alias EhOsContract.DslRules
  alias EhOsContract.Contract.Rules

  @doc false
  @spec check(map()) :: [DslRules.violation()]
  def check(declarations) do
    Enum.flat_map(declarations.units, &unit(&1, declarations)) ++
      states(declarations) ++ reachable(declarations)
  end

  defp unit(unit, d) do
    where = "#{unit.kind} #{inspect(unit.name)}"
    events = MapSet.new(Rules.events(unit), & &1.name)
    invariants = MapSet.new(unit.invariants, & &1.name)

    emits =
      Enum.flat_map(unit.commands, fn command ->
        if command.emits == [] do
          [
            {"A1: command #{inspect(command.name)} emits nothing; name the events it may produce",
             command}
          ]
        else
          for event <- command.emits, not MapSet.member?(events, event) do
            {"A1: command #{inspect(command.name)} emits #{inspect(event)}, which is not an event " <>
               "of #{where}", command}
          end
        end
      end)

    emitted = MapSet.new(Enum.flat_map(unit.commands, & &1.emits))

    unemitted =
      for event <- Rules.events(unit),
          not MapSet.member?(emitted, event.name),
          event.recorded_by == [] do
        {"A2: event #{inspect(event.name)} is emitted by no command of #{where} and declares no " <>
           "recorded_by:, so it could never occur", event}
      end

    rejects =
      for command <- unit.commands,
          constraints = MapSet.new(command.constraints, & &1.name),
          invariant <- command.rejects,
          not MapSet.member?(invariants, invariant),
          not MapSet.member?(constraints, invariant) do
        {"A3: command #{inspect(command.name)} rejects #{inspect(invariant)}, which is neither an " <>
           "invariant of #{where} nor a constraint of the command", command}
      end

    emits ++
      unemitted ++
      rejects ++
      constraints(unit, invariants) ++
      reads(unit, d) ++ consults(unit, d) ++ generated(unit, where)
  end

  defp reads(unit, d) do
    issuers = issuers(d)

    for command <- unit.commands,
        {problem, at} <-
          read_problems(command, unit) ++ read_by_reaction(command, issuers[command.name]) do
      {"A8: command #{inspect(command.name)} #{problem}", at}
    end
  end

  # The user's decision on the review of #242: a reaction's command is dispatched inside
  # the transaction that reacted, after the append lock, where the host's lookup would
  # hold up every writer, and a row not found would fail the reaction rather than answer
  # it. Only an actor issues a command that reads.
  defp read_by_reaction(%{reads: []}, _issuers), do: []
  defp read_by_reaction(_command, nil), do: []

  defp read_by_reaction(command, [first | _]) do
    [
      {"reads entities and is issued by #{first}; a command that reads is issued only by an " <>
         "actor in by:, since a reaction's would be looked up inside the transaction that " <>
         "reacted", command}
    ]
  end

  # For each command a reaction of this contract issues, who issues it, in words.
  defp issuers(d) do
    policies = for p <- d.policies, c <- p.issues, do: {c, "policy #{inspect(p.name)}"}

    managers =
      for pm <- d.process_managers,
          reaction <- pm.starts_on ++ pm.on ++ pm.timers,
          c <- reaction.issues,
          do: {c, "process manager #{inspect(pm.name)}"}

    Enum.group_by(policies ++ managers, &elem(&1, 0), &elem(&1, 1))
  end

  defp read_problems(command, unit) do
    names = Keyword.keys(command.reads)

    twice =
      for name <- Enum.uniq(names -- Enum.uniq(names)) do
        {"reads #{inspect(name)} twice; give each row its own name", command}
      end

    twice ++
      for {name, field} <- Enum.uniq(command.reads),
          problem <- read_field(command, unit, field) do
        {"reads #{inspect(name)} by #{inspect(field)}, #{problem}", command}
      end
  end

  defp read_field(command, unit, field) do
    declared = Enum.find(command.fields, &(&1.name == field))

    cond do
      declared == nil and field in List.wrap(unit.identity) ->
        [
          "a field of the unit's identity, an :id; an entity is named by a field typed {:id, entity}"
        ]

      declared == nil ->
        ["which is not one of its fields"]

      not match?({:id, entity} when is_atom(entity), declared.type) ->
        ["typed #{inspect(declared.type)}; an entity is named by a field typed {:id, entity}"]

      declared.optional ->
        ["which it declares optional; without it there is nothing to read"]

      true ->
        []
    end
  end

  # A7 (plan EL2): a command's constraints are never named as an invariant of its unit,
  # since `rejects:` and `reject/1` name both alike, and each is in `rejects:`:
  # a constraint the command cannot refuse on is one nothing checks.
  defp constraints(unit, invariants) do
    for command <- unit.commands,
        constraint <- command.constraints,
        problem <- constraint_problems(command, constraint, invariants) do
      {"A7: command #{inspect(command.name)}, constraint #{inspect(constraint.name)} #{problem}",
       constraint}
    end
  end

  # A name declared twice is N1's, reported once.
  defp constraint_problems(command, constraint, invariants) do
    Enum.concat([
      if(MapSet.member?(invariants, constraint.name),
        do: ["has the name of an invariant of the unit; give it its own"],
        else: []
      ),
      if(constraint.name in command.rejects,
        do: [],
        else: ["is not in its rejects:, so nothing checks it; add it there"]
      )
    ])
  end

  defp generated(unit, where) do
    creating = for c <- unit.commands, c.creates, do: c

    if unit.generated do
      one =
        if length(List.wrap(unit.identity)) == 1,
          do: [],
          else: [
            {"A6: #{where} is identified by #{inspect(unit.identity)}; a generated identity is one " <>
               "field", unit}
          ]

      created =
        if creating == [],
          do: [
            {"A6: #{where} has a generated identity and no command that creates: it, so none " <>
               "could ever be made", unit}
          ],
          else: []

      one ++ created
    else
      for c <- creating do
        advice =
          if unit.kind == :dcb,
            do:
              "a boundary's identity comes from its commands, so creates: belongs only to an " <>
                "aggregate's",
            else:
              "write `identity #{inspect(List.first(List.wrap(unit.identity)))}, generated: :uuid`"

        {"A6: command #{inspect(c.name)} creates: #{where}, whose identity is not generated; " <>
           advice, c}
      end
    end
  end

  defp consults(%{kind: :dcb} = unit, d) do
    where = "dcb #{inspect(unit.name)}"
    carried = tagged_fields(d)

    known =
      MapSet.new(
        Enum.map(Rules.local_events(d), & &1.name) ++ Enum.map(Rules.consumed(d), &elem(&1, 0))
      )

    none =
      if unit.consults == [],
        do: [{"A4: #{where} consults no event, so it decides over nothing", unit}],
        else: []

    each =
      Enum.flat_map(unit.consults, fn consults ->
        event = inspect(consults.event)

        unknown =
          cond do
            MapSet.member?(Rules.received(d), consults.event) ->
              [
                {"A4: #{where} consults #{event}, which arrives from another application into an " <>
                   "inbox, not into this log (D12), so no append condition can read it", consults}
              ]

            MapSet.member?(known, consults.event) ->
              []

            true ->
              [
                {"A4: #{where} consults #{event}, which is neither an event of this contract nor " <>
                   "one it consumes", consults}
              ]
          end

        criterion =
          if consults.match == [] and consults.where == nil,
            do: [{"A4: #{where} consults #{event} with neither match: nor where:", consults}],
            else: []

        outside =
          for field <- consults.match, field not in unit.identity do
            {"A4: #{where} consults #{event} matching #{inspect(field)}, which is not in its " <>
               "identity #{inspect(unit.identity)}", consults}
          end

        untagged =
          case Map.get(carried, consults.event) do
            nil ->
              []

            tagged ->
              for field <- consults.match, field in unit.identity, field not in tagged do
                {"A4: #{where} consults #{event} matching #{inspect(field)}, which the event " <>
                   "does not carry as a required, non-personal :id field, so no appended " <>
                   "#{event} is tagged with it and the boundary could never find one", consults}
              end
          end

        unknown ++ criterion ++ outside ++ untagged
      end)

    none ++ each
  end

  defp consults(_unit, _d), do: []

  # For each local event, the fields an append tags it with: its unit's identity, and
  # its own required, non-personal fields of the built-in type `:id`.
  defp tagged_fields(d) do
    for unit <- d.units, event <- Rules.events(unit), into: %{} do
      own = for f <- event.fields, EhOsContract.Key.tag_field?(f), do: f.name

      {event.name, List.wrap(unit.identity) ++ own}
    end
  end

  defp states(d) do
    units = for u <- d.units, do: {"#{u.kind} #{inspect(u.name)}", u.state}
    managers = for pm <- d.process_managers, do: {"process manager #{inspect(pm.name)}", pm.state}

    for {where, [_first | again]} <- units ++ managers, state <- again do
      {"A5: #{where} declares its state twice", state}
    end
  end

  defp reachable(d) do
    issued =
      MapSet.new(
        Enum.flat_map(d.policies, & &1.issues) ++
          Enum.flat_map(d.process_managers, fn pm ->
            Enum.flat_map(pm.starts_on, & &1.issues) ++
              Enum.flat_map(pm.on, & &1.issues) ++ Enum.flat_map(pm.timers, & &1.issues)
          end)
      )

    for command <- Rules.commands(d),
        command.by == [],
        not MapSet.member?(issued, command.name) do
      {"C1: command #{inspect(command.name)} can be issued by no one: give it by:, or have a " <>
         "policy or a process manager of this contract issue it", command}
    end
  end
end
