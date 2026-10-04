defmodule EhOsContract.Contract.Rules.Lifecycles do
  @moduledoc """
  T1–T4 (plan LC1, #99): an aggregate's lifecycle, and the commands it lets in.

  - **T1.** An aggregate declares `lifecycle` at most once; one has a status and an
    `initial`, and names each status once, in snake_case.
  - **T2.** `initial` and `transition` name statuses of the lifecycle and events of
    the aggregate; a transition leaves at least one status. The status an event moves the aggregate to is one: one `initial`
    per event, and one transition per status and event.
  - **T3.** Every status is reached from an `initial`; a `terminal:` status has no
    transition out, and every other status has one, since an aggregate stuck in a
    status nobody called final is a lifecycle missing a transition.
  - **T4.** A command's `from:` names statuses of its aggregate's lifecycle and comes
    with `or_rejects:`, an invariant of the unit in the command's `rejects:`, and the
    other way round; a command that `creates:` its aggregate has no `from:`, since a
    new aggregate has no status yet, and no command is issued from a terminal status. An event the command emits that a transition
    names leaves at least one status in `from:`, and every status in `from:` lets at
    least one of the command's events in, or the decision could only ever be a defect.

  An event no transition names moves nothing: it is allowed in every status that is
  not terminal. Whether the run of the process ends with the aggregate's life is not
  checked here: `terminal:` on an event ends a run, and a run may be correlated by
  other fields than the aggregate's identity.
  """

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
    shape(where, lifecycle, again) ++
      references(unit, where, lifecycle) ++
      reach(where, lifecycle) ++ preconditions(unit, where, lifecycle)
  end

  # --- T1 -------------------------------------------------------------------------

  defp shape(where, lifecycle, again) do
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

    twice ++ empty ++ names ++ repeated
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
        {"T2: event #{inspect(initial.on)} starts #{where} in two statuses; an initial event " <>
           "starts it in one", initial}
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
    leaving = MapSet.new(edges, &elem(&1, 0))

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
          status.terminal and MapSet.member?(leaving, status.name) ->
            [{"T3: status #{name} of #{where} is terminal, and a transition leaves it", status}]

          not status.terminal and not MapSet.member?(leaving, status.name) ->
            [
              {"T3: status #{name} of #{where} has no transition out; mark it terminal: true " <>
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
        command.from == [] and command.or_rejects == nil ->
          []

        command.from == [] ->
          [
            {"T4: #{what} has or_rejects: without from:; name the statuses it may be issued " <>
               "in", command}
          ]

        lifecycle == nil ->
          [
            {"T4: #{what} has from:, and #{where} declares no lifecycle#{boundary(unit)}",
             command}
          ]

        true ->
          precondition(unit, where, lifecycle, command, what)
      end
    end)
  end

  defp boundary(%{kind: :dcb}), do: "; a boundary spans streams, so it has no status"
  defp boundary(_aggregate), do: ""

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
      for status <- lifecycle.statuses, status.terminal, status.name in command.from do
        {"T4: #{what} is issued from #{inspect(status.name)}, which is terminal: nothing is " <>
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

  # Whether the graph lets the command's decision in. Checked only once every status
  # in `from:` is a declared one that is not terminal, which the checks above report,
  # and an event that leaves none of them is reported before a status that lets none
  # of the events out, which it usually is the cause of.
  defp graph(command, what, where, statuses, allowed, moving) do
    terminal = for s <- statuses, s.terminal, do: s.name
    names = Enum.map(statuses, & &1.name)

    if Enum.all?(command.from, &(&1 in names and &1 not in terminal)) and not command.creates do
      dead =
        for event <- moving,
            not Enum.any?(command.from, &MapSet.member?(allowed, {&1, event})) do
          {"T4: #{what} emits #{inspect(event)}, and no transition moves #{where} with it out " <>
             "of #{inspect(command.from)}", command}
        end

      stuck =
        for status <- command.from,
            command.emits -- moving == [],
            not Enum.any?(moving, &MapSet.member?(allowed, {status, &1})) do
          {"T4: #{what} is issued from #{inspect(status)}, and no event it emits has a " <>
             "transition out of it", command}
        end

      if dead == [], do: stuck, else: dead
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
