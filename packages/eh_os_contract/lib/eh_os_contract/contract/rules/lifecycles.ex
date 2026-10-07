defmodule EhOsContract.Contract.Rules.Lifecycles do
  # T1–T4 (plan LC1, #99): an aggregate's lifecycle, and the commands it lets in.
  #
  # - **T1.** An aggregate declares `lifecycle` at most once; one has a status and an
  #   `initial`, and names each status once, in snake_case. Its state and identity have
  #   no field `:status`, which the engine fills with the status (plan LC2).
  # - **T2.** `initial` and `transition` name statuses of the lifecycle and events of
  #   the aggregate; a transition leaves at least one status. The status an event moves the aggregate to is one: one `initial`
  #   per event, and one transition per status and event.
  # - **T3.** Every status is reached from an `initial`; a `final:` status has no
  #   transition out, and every other status has one, since an aggregate stuck in a
  #   status nobody called final is a lifecycle missing a transition.
  # - **T4.** A command's `from:` names statuses of its aggregate's lifecycle and comes
  #   with `or_rejects:`, an invariant of the unit in the command's `rejects:`, and the
  #   other way round; no command is issued from a final status. A command that
  #   `creates:` its aggregate emits one of its initial events and has no `from:`, since
  #   a new aggregate has no status yet. An event the command emits that a transition
  #   names leaves at least one status in `from:`, or emitting it could only ever be a
  #   defect. A status in `from:` that no event of the command leaves is where the
  #   decision refuses, on a rule finer than the status, so `rejects:` names one besides
  #   `or_rejects:`.
  #   A boundary's command has no `from:` at all (L1): a boundary has no lifecycle.
  #
  # An event no transition names moves nothing: it is allowed in every status that is
  # not final, once an initial event has started the aggregate. Whether the run of the process ends with the aggregate's life is not
  # checked here: `terminal:` on an event ends a run, and a run may be correlated by
  # other fields than the aggregate's identity.
  @moduledoc false

  alias EhOsContract.DslRules
  alias EhOsContract.Contract.Rules

  @doc false
  @spec check(map()) :: [DslRules.violation()]
  def check(declarations) do
    Enum.flat_map(declarations.units, fn unit ->
      where = "#{unit.kind} #{inspect(unit.name)}"

      case unit.lifecycle do
        [] -> preconditions(unit, where, nil)
        [lifecycle | again] -> lifecycle(unit, where, lifecycle, again)
      end
    end)
  end

  defp lifecycle(unit, where, lifecycle, again) do
    shape(unit, where, lifecycle, again) ++
      references(unit, where, lifecycle) ++
      reach(where, lifecycle) ++ preconditions(unit, where, lifecycle)
  end

  # --- T1 -------------------------------------------------------------------------

  defp shape(unit, where, lifecycle, again) do
    twice =
      for second <- again,
          do: {"T1: #{where} declares lifecycle twice; one holds all its statuses", second}

    empty =
      Enum.concat([
        if(lifecycle.statuses == [],
          do: [{"T1: the lifecycle of #{where} has no status", lifecycle}],
          else: []
        ),
        if(lifecycle.initials == [],
          do: [
            {"T1: the lifecycle of #{where} has no initial, so no aggregate would ever have a " <>
               "status; write `initial :status, on: :event`", lifecycle}
          ],
          else: []
        )
      ])

    names =
      for status <- lifecycle.statuses, not DslRules.name?(status.name) do
        {"T1: status #{inspect(status.name)} of #{where} is not snake_case", status}
      end

    repeated =
      for status <- DslRules.duplicates(lifecycle.statuses, & &1.name) do
        {"T1: status #{inspect(status.name)} of #{where} is declared twice", status}
      end

    twice ++ empty ++ names ++ repeated ++ status_field(where, unit)
  end

  # The engine puts the status into the state (plan LC2), so a field of that name
  # would be overwritten, or would take the place of the status.
  defp status_field(where, unit) do
    fields =
      for field <- Rules.state_fields(unit.state), field.name == :status do
        {"T1: #{where} declares a state field :status, which its lifecycle's status takes; " <>
           "drop it, or rename it", field}
      end

    identity =
      if :status in List.wrap(unit.identity),
        do: [{"T1: #{where} is identified by :status, which its lifecycle's status takes", unit}],
        else: []

    fields ++ identity
  end

  # --- T2 -------------------------------------------------------------------------

  defp references(unit, where, lifecycle) do
    statuses = Enum.map(lifecycle.statuses, & &1.name)
    events = Enum.map(Rules.events(unit), & &1.name)

    status = fn name, what, declaration ->
      if name in statuses,
        do: [],
        else: [
          {"T2: #{what} names status #{inspect(name)}, which the lifecycle of #{where} does " <>
             "not declare#{did_you_mean(name, statuses)}", declaration}
        ]
    end

    event = fn name, what, declaration ->
      if name in events,
        do: [],
        else: [
          {"T2: #{what} names #{inspect(name)}, which is not an event of " <>
             "#{where}#{did_you_mean(name, events)}", declaration}
        ]
    end

    initials =
      Enum.flat_map(lifecycle.initials, fn initial ->
        what = "initial #{inspect(initial.status)}"
        status.(initial.status, what, initial) ++ event.(initial.on, what, initial)
      end)

    transitions =
      Enum.flat_map(lifecycle.transitions, fn t ->
        what = "transition #{inspect(t.from)} --#{t.event}--> #{inspect(t.to)}"

        # An empty `from:` passes Spark's schema and would leave the transition out of
        # the model without a word, the event then moving nothing.
        nowhere =
          if t.from == [],
            do: [{"T2: #{what} leaves no status; name the statuses it moves out of", t}],
            else: []

        nowhere ++
          Enum.flat_map(t.from, &status.(&1, what, t)) ++
          status.(t.to, what, t) ++ event.(t.event, what, t)
      end)

    started =
      for initial <- DslRules.duplicates(lifecycle.initials, & &1.on) do
        if Enum.count(lifecycle.initials, &(&1.on == initial.on and &1.status == initial.status)) >
             1,
           do:
             {"T2: initial #{inspect(initial.status)} on #{inspect(initial.on)} of #{where} is " <>
                "declared twice", initial},
           else:
             {"T2: event #{inspect(initial.on)} starts #{where} in two statuses; an initial " <>
                "event starts it in one", initial}
      end

    pairs = for t <- lifecycle.transitions, from <- Enum.uniq(t.from), do: {{from, t.event}, t}

    moved =
      for {{from, event}, t} <- DslRules.duplicates(pairs, &elem(&1, 0)) do
        {"T2: event #{inspect(event)} moves #{where} out of #{inspect(from)} twice; one status " <>
           "and one event lead to one status", t}
      end

    initials ++ transitions ++ started ++ moved
  end

  defp did_you_mean(name, names) do
    case DslRules.closest(name, names) do
      nil -> ""
      close -> "; did you mean #{inspect(close)}?"
    end
  end

  # --- T3 -------------------------------------------------------------------------

  defp reach(where, lifecycle) do
    edges = for t <- lifecycle.transitions, from <- t.from, do: {from, t.to}
    reached = reached(Enum.map(lifecycle.initials, & &1.status), edges, MapSet.new())
    # A transition back into the same status leads nowhere: it neither gets the
    # aggregate out of a status nor out of a final one.
    leaving = for {from, to} <- edges, from != to, into: MapSet.new(), do: from

    Enum.flat_map(Enum.uniq_by(lifecycle.statuses, & &1.name), fn status ->
      name = inspect(status.name)

      Enum.concat([
        if(MapSet.member?(reached, status.name),
          do: [],
          else: [
            {"T3: status #{name} of #{where} is reached from no initial status, so no " <>
               "aggregate could ever be in it", status}
          ]
        ),
        cond do
          status.final and MapSet.member?(leaving, status.name) ->
            [{"T3: status #{name} of #{where} is final, and a transition leaves it", status}]

          not status.final and not MapSet.member?(leaving, status.name) ->
            [
              {"T3: status #{name} of #{where} has no transition out; mark it final: true " <>
                 "if the aggregate's life ends there", status}
            ]

          true ->
            []
        end
      ])
    end)
  end

  defp reached([], _edges, seen), do: seen

  defp reached([status | rest], edges, seen) do
    if MapSet.member?(seen, status) do
      reached(rest, edges, seen)
    else
      next = for {^status, to} <- edges, do: to
      reached(next ++ rest, edges, MapSet.put(seen, status))
    end
  end

  # --- T4 -------------------------------------------------------------------------

  defp preconditions(unit, where, lifecycle) do
    Enum.flat_map(unit.commands, fn command ->
      what = "command #{inspect(command.name)}"

      cond do
        # The one way a new aggregate gets a status is an initial event, and a command
        # that creates it is the one that decides its first.
        command.creates and lifecycle != nil and
            not Enum.any?(lifecycle.initials, &(&1.on in command.emits)) ->
          [
            {"T4: #{what} creates: its aggregate, and emits none of its lifecycle's initial " <>
               "events, so the aggregate it makes would have no status", command}
          ] ++ precondition_if_declared(unit, where, lifecycle, command, what)

        command.from == [] and command.or_rejects == nil ->
          []

        command.from == [] ->
          [
            {"T4: #{what} has or_rejects: without from:; name the statuses it may be issued " <>
               "in", command}
          ]

        lifecycle == nil ->
          [{"T4: #{what} has from:, and #{where} declares no lifecycle", command}]

        true ->
          precondition(unit, where, lifecycle, command, what)
      end
    end)
  end

  defp precondition_if_declared(_unit, _where, _lifecycle, %{from: [], or_rejects: nil}, _what),
    do: []

  defp precondition_if_declared(unit, where, lifecycle, command, what),
    do: precondition(unit, where, lifecycle, command, what)

  defp precondition(unit, where, lifecycle, command, what) do
    statuses = Enum.map(lifecycle.statuses, & &1.name)
    invariants = Enum.map(unit.invariants, & &1.name)
    # An initial event moves the aggregate too, out of no status: issued from one, it
    # would be a defect.
    moved_by =
      MapSet.new(
        Enum.map(lifecycle.transitions, & &1.event) ++ Enum.map(lifecycle.initials, & &1.on)
      )

    allowed =
      for t <- lifecycle.transitions, from <- t.from, into: MapSet.new(), do: {from, t.event}

    moving = Enum.filter(command.emits, &MapSet.member?(moved_by, &1))

    Enum.concat([
      for status <- command.from, status not in statuses do
        {"T4: #{what} is issued from status #{inspect(status)}, which the lifecycle of " <>
           "#{where} does not declare#{did_you_mean(status, statuses)}", command}
      end,
      for status <- lifecycle.statuses, status.final, status.name in command.from do
        {"T4: #{what} is issued from #{inspect(status.name)}, which is final: nothing is " <>
           "decided once the aggregate's life has ended", command}
      end,
      refusal(command, what, invariants),
      if(command.creates,
        do: [
          {"T4: #{what} creates: its aggregate, which has no status before it, so it has no " <>
             "from:", command}
        ],
        else: []
      ),
      graph(command, what, where, lifecycle.statuses, allowed, moving)
    ])
  end

  # Whether the graph lets the command's events out of the statuses it is issued in:
  # each event a transition names leaves at least one of them. A status in `from:`
  # that none of the events can leave is where the decision only refuses (plan LC4a,
  # AppUnite's `:for_sale_not_issued`), so it needs a rule of its own in `rejects:`.
  # Checked only once every status in `from:` is a declared one that is not final,
  # which the checks above report.
  defp graph(command, what, where, statuses, allowed, moving) do
    final = for s <- statuses, s.final, do: s.name
    names = Enum.map(statuses, & &1.name)

    if Enum.all?(command.from, &(&1 in names and &1 not in final)) and not command.creates do
      dead =
        for event <- moving,
            not Enum.any?(command.from, &MapSet.member?(allowed, {&1, event})) do
          {"T4: #{what} emits #{inspect(event)}, and no transition moves #{where} with it out " <>
             "of #{inspect(command.from)}", command}
        end

      # A status none of the events leaves is where the decision refuses, so it needs
      # a rule to refuse on besides `or_rejects:`, which the engine has already applied.
      finer? = Enum.any?(command.rejects, &(&1 != command.or_rejects))

      stuck =
        for status <- command.from,
            dead == [],
            not finer?,
            command.emits -- moving == [],
            not Enum.any?(moving, &MapSet.member?(allowed, {status, &1})) do
          {"T4: #{what} is issued from #{inspect(status)}, which no event it emits leaves, " <>
             "and rejects: names no rule but its or_rejects: to refuse on there", command}
        end

      dead ++ stuck
    else
      []
    end
  end

  defp refusal(command, what, invariants) do
    cond do
      command.or_rejects == nil ->
        [
          {"T4: #{what} has from: without or_rejects:; name the invariant it is refused on in " <>
             "any other status", command}
        ]

      command.or_rejects not in invariants ->
        [
          {"T4: #{what} or_rejects: #{inspect(command.or_rejects)}, which is not an invariant " <>
             "of its unit", command}
        ]

      command.or_rejects not in command.rejects ->
        [
          {"T4: #{what} or_rejects: #{inspect(command.or_rejects)}, which is not in its " <>
             "rejects:; add it there", command}
        ]

      true ->
        []
    end
  end
end
