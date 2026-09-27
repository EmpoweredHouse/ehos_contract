defmodule EhOsContract.Next.Contract.Rules.Units do
  @moduledoc """
  A1–A5 and C1 of v2 §6: what a unit decides, and who can ask it to.

  - **A1.** A command emits something, and only events of its own unit.
  - **A2.** Every event is emitted by a command of its unit, or declares
    `recorded_by:` (D6). Stricter than ESDM on purpose: in an event-sourced log,
    an event nothing produces can never occur.
  - **A3.** A command rejects only invariants of its own unit.
  - **A4.** A dynamic consistency boundary consults at least one event; each one
    is an event of this log — its own or a sibling contract's, not one received from
    another application (D12) — and says which by `match:`
    or `where:`; `match:` names fields of the boundary's identity, which a local
    consulted event carries as required, non-personal `:id` fields — its unit's
    identity, or fields of its own. Only such fields are tags of an appended event,
    and a boundary finds what it consults by its tags. For an event consumed from a
    sibling contract the same is X6's, where the sibling is known.
  - **A5.** A unit, or a process manager, declares its state at most once.
  - **A6** (plan EM3). An aggregate whose identity is `generated:` has one identity
    field, and at least one command that `creates:` it, since nothing else could make
    a new one; `creates:` belongs only to such an aggregate's commands.
  - **C1.** A command can be issued: it names actors in `by:`, or a policy or a
    process manager of this contract issues it.
  """

  alias EhOsContract.DslRules
  alias EhOsContract.Next.Contract.Rules

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
          invariant <- command.rejects,
          not MapSet.member?(invariants, invariant) do
        {"A3: command #{inspect(command.name)} rejects #{inspect(invariant)}, which is not an " <>
           "invariant of #{where}", command}
      end

    emits ++ unemitted ++ rejects ++ consults(unit, d) ++ generated(unit, where)
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
