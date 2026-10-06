defmodule EhOsContract.Contract.Rules.Process do
  @moduledoc """
  R1–R6 of v2 §6: the one process a contract describes.

  - **R1.** Exactly one `process`: one contract, one process (v2 §3).
  - **R2.** The process correlates on at least one field, and every such field is
    in every local event, where a unit's identity counts as declared. With no field
    every event of the contract would land in one run named after the process.
  - **R3.** Stages are all or nothing. When the process declares stages, every
    local event sits in a stage group of its unit, every `include` in a stage, and
    a stage group names a stage the process declares. When it declares none, there
    are no groups.
  - **R4.** `include` places events consumed from a sibling contract; a local event
    is placed by its unit's stage group, and an event received from another
    application is not in this log at all (D12).
  - **R5.** A promise's `from`, `eventually` and `or_else` are events of the run:
    local events, and consumed events the process includes.
  - **R6.** `within` and `deadline` count a non-negative number of a fixed unit
    (`EhOsContract.Duration`), since the report measures elapsed time against them;
    a timer's `wait` and `cadence` may also count weeks, months and years — a timer
    by the calendar, the user's choice of 27 September 2026 (plan EM3), and
    `cadence` because nothing computes a deadline from it.
  """

  alias EhOsContract.DslRules
  alias EhOsContract.Duration
  alias EhOsContract.Contract.{Dsl, Rules}

  @calendar Duration.calendar_units()

  @doc false
  @spec check(map()) :: [DslRules.violation()]
  def check(%{processes: [process | again]} = declarations) do
    twice =
      for p <- again,
          do: {"R1: a contract describes one process; #{inspect(p.name)} is a second", p}

    twice ++
      correlation(process, declarations) ++
      stages(process, declarations) ++
      includes(process, declarations) ++
      promises(process, declarations) ++ durations(process, declarations)
  end

  # Pointed at the first declaration there is, or at nothing when the contract is
  # empty; the error then names the module without a line.
  def check(%{processes: []} = declarations) do
    anchor =
      declarations
      |> Map.delete(:module)
      |> Map.values()
      |> List.flatten()
      |> Enum.min_by(&line/1, fn -> %Dsl.ProcessDeclaration{} end)

    [{"R1: a contract describes one process, and this one declares none", anchor}]
  end

  defp line(declaration) do
    case Spark.Dsl.Entity.anno(declaration) do
      nil -> :infinity
      anno -> :erl_anno.line(anno)
    end
  end

  defp correlation(%{correlate: []} = process, _d) do
    [
      {"R2: process #{inspect(process.name)} correlates on no field, so every event of it " <>
         "would belong to one run; name the fields that tell one run from another", process}
    ]
  end

  defp correlation(process, d) do
    for unit <- d.units,
        event <- Rules.events(unit),
        names = MapSet.new(unit.identity ++ Enum.map(event.fields, & &1.name)),
        field <- process.correlate,
        not MapSet.member?(names, field) do
      {"R2: event #{inspect(event.name)} has no field #{inspect(field)}, which process " <>
         "#{inspect(process.name)} correlates on", event}
    end
  end

  defp stages(process, d) do
    where = "process #{inspect(process.name)}"
    declared = MapSet.new(process.stages, & &1.name)

    if process.stages == [] do
      for unit <- d.units, group <- unit.stages do
        {"R3: #{where} declares no stages, so #{unit.kind} #{inspect(unit.name)} cannot group " <>
           "events into stage #{inspect(group.name)}", group}
      end
    else
      ungrouped =
        for unit <- d.units, event <- unit.events do
          {"R3: #{where} declares stages, so event #{inspect(event.name)} has to sit in a stage " <>
             "group of #{unit.kind} #{inspect(unit.name)}", event}
        end

      unknown =
        for unit <- d.units, group <- unit.stages, not MapSet.member?(declared, group.name) do
          {"R3: #{unit.kind} #{inspect(unit.name)} groups events into stage #{inspect(group.name)}, " <>
             "which #{where} does not declare", group}
        end

      unplaced =
        for include <- process.includes do
          {"R3: #{where} declares stages, so include #{inspect(include.event)} has to sit in one " <>
             "of them", include}
        end

      ungrouped ++ unknown ++ unplaced
    end
  end

  defp includes(process, d) do
    consumed = MapSet.new(Rules.consumed(d), &elem(&1, 0))
    received = Rules.received(d)
    local = MapSet.new(Rules.local_events(d), & &1.name)

    for include <- all_includes(process),
        MapSet.member?(received, include.event) or not MapSet.member?(consumed, include.event) do
      why =
        cond do
          MapSet.member?(local, include.event) ->
            "a local event is placed by its unit's stage group"

          MapSet.member?(received, include.event) ->
            "it arrives from another application into an inbox, not into this log (D12); " <>
              "a run across applications is assembled by EHOS"

          true ->
            "it is not an event this contract consumes"
        end

      {"R4: process #{inspect(process.name)} includes #{inspect(include.event)}, but #{why}",
       include}
    end
  end

  defp all_includes(process),
    do: process.includes ++ Enum.flat_map(process.stages, & &1.includes)

  defp promises(process, d) do
    run =
      MapSet.new(
        Enum.map(Rules.local_events(d), & &1.name) ++ Enum.map(all_includes(process), & &1.event)
      )

    for promise <- process.promises,
        {key, event} <- [
          from: promise.from,
          eventually: promise.eventually,
          or_else: promise.or_else
        ],
        event != nil,
        not MapSet.member?(run, event) do
      {"R5: promise #{inspect(promise.name)}: #{key} #{inspect(event)} is not an event of the run " <>
         "of process #{inspect(process.name)}", promise}
    end
  end

  defp durations(process, d) do
    fixed =
      for(
        p <- process.promises,
        p.within != nil,
        do: {"promise #{inspect(p.name)}: within", p.within, p}
      ) ++
        for(
          dl <- process.deadline,
          do: {"process #{inspect(process.name)}: deadline", dl.within, dl}
        )

    calendar =
      for(c <- process.cadence, do: {"process #{inspect(process.name)}: cadence", c.every, c}) ++
        for pm <- d.process_managers, t <- pm.timers, t.wait != nil do
          {"timer #{inspect(t.name)}: wait", t.wait, t}
        end

    for(
      {what, duration, declaration} <- fixed,
      problem <- problems(duration, Duration.units()),
      do: {"R6: #{what} #{problem}", declaration}
    ) ++
      for {what, duration, declaration} <- calendar,
          problem <- problems(duration, Duration.units() ++ @calendar) do
        {"R6: #{what} #{problem}", declaration}
      end ++ once(process)
  end

  defp once(process) do
    for {key, [_ | again]} <- [cadence: process.cadence, deadline: process.deadline],
        x <- again do
      {"R6: process #{inspect(process.name)} declares #{key} twice", x}
    end
  end

  defp problems({n, unit}, units) do
    count =
      if is_integer(n) and n >= 0,
        do: [],
        else: ["counts #{inspect(n)}, which is not a non-negative integer"]

    unit =
      cond do
        unit in units ->
          []

        unit in @calendar ->
          [
            "is in #{inspect(unit)}, a calendar unit, which only a timer's wait and cadence may use"
          ]

        true ->
          ["is in #{inspect(unit)}, which is not one of #{inspect(units)}"]
      end

    count ++ unit
  end

  defp problems(other, _units), do: ["is #{inspect(other)}, which is not {count, unit}"]
end
