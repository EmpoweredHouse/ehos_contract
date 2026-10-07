defmodule EhOsContract.Report do
  @moduledoc """
  The conformance report for a period — four questions, one page.

  The engine writes its own sentences in English and passes the contract's `label`
  through untouched, so a declaration written in the reader's language stays in it.
  The engine translates its own words and never somebody else's.

  **The scaffolding is English; the contract's own labels are not translated.**
  `from_label`, `to_label` and a process's `label` print exactly as the contract
  declares them — TaxVision's are Polish, a future contract's might not be. The
  engine writes its own sentences in one language; it still does not decide what
  language the client wrote their labels in.

  What is **not** here: declarations the process owner has not confirmed. The filter
  lives in `EhOsContract.Conformance`, not here, because it is a rule about evidence
  rather than about formatting — the consequence is visible right here: an unconfirmed
  `deadline` never reaches `render/1`'s input.
  """

  # Rendered here rather than in the application, which reversed an earlier decision:
  # the sentences used to be built client-side, on the argument that the engine cannot
  # know what language its reader speaks. What the report leaves out stayed as it was
  # before the move.

  alias EhOsContract.Report.Sentence

  @doc """
  The report for one contract over a period, as text to print; or for one process
  module, its deployment and its process section.
  """
  # A process module's report: plan DD, P2d (#213).
  @spec render(map()) :: String.t()
  def render(%{process: _} = report) do
    [
      header(report),
      process_deployment(report.deployment),
      Enum.map(report.processes, &process/1)
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  def render(report) do
    [
      header(report),
      deployment(report.deployment, report.wiring),
      steps(report.activity, report.paths),
      Enum.map(report.processes, &process/1),
      Enum.map(Map.get(report, :lifecycles, []), &lifecycle/1),
      scenarios(report.scenarios),
      drift(report.drift)
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  @spec header(map()) :: [String.t()]
  defp header(report) do
    [
      "CONFORMANCE REPORT — #{period(report.period)}",
      "Whether the deployed code does what the agreed process says.",
      # A property of the whole artifact, not of the contract block below it —
      # which is also why `deployment/1` stays untouched. What counts as drift has
      # moved more than once, so a number without the engine that produced it is
      # not reproducible evidence.
      "Computed by EhOsContract #{report.engine}.",
      ""
    ]
  end

  @spec period(map()) :: String.t()
  defp period(%{since: nil, until: nil}), do: "the whole log"
  defp period(%{since: since, until: nil}), do: "since #{day(since)}"
  defp period(%{since: nil, until: until}), do: "until #{day(until)}"
  defp period(%{since: since, until: until}), do: "#{day(since)} – #{day(until)}"

  @spec day(DateTime.t()) :: String.t()
  defp day(at), do: at |> DateTime.to_date() |> Date.to_string()

  @spec deployment(map(), map()) :: [String.t()]
  defp deployment(deployment, wiring) do
    since =
      case deployment.deployed.since do
        nil -> "nothing has happened under this version yet"
        at -> "in force since #{day(at)}"
      end

    change =
      case deployment.changed do
        nil ->
          []

        c ->
          [
            "  Since the previous version: " <>
              "events added #{length(c.events_added)}, removed #{length(c.events_removed)}, " <>
              "paths added #{length(c.paths_added)}, removed #{length(c.paths_removed)}."
          ] ++ declarations_changed(c.declarations)
      end

    earlier =
      if deployment.from_earlier_versions > 0 do
        [
          "  Events from earlier contract versions: #{deployment.from_earlier_versions}. " <>
            "This is legitimate history, not drift."
        ]
      else
        []
      end

    # A contract's wiring is the code's half of what is deployed, so it is named.
    wired =
      case wiring do
        %{version: version} when is_binary(version) -> ["  Wiring #{version}."]
        _not_recorded -> []
      end

    # Plan DD, P1a (#183): named by its id, so a report of several contracts tells them apart.
    [
      "CONTRACT: #{deployment.contract}",
      "  Version #{deployment.deployed.contract_version}, #{since}."
    ] ++
      wired ++ change ++ earlier ++ [""]
  end

  # A process module's version, in force since the deployment that carries it was first
  # recorded: no event is stamped with it.
  @spec process_deployment(map()) :: [String.t()]
  defp process_deployment(deployment) do
    since =
      case deployment.deployed.since do
        nil -> "not recorded as deployed"
        at -> "deployed since #{day(at)}"
      end

    change =
      case deployment.changed do
        nil ->
          []

        c ->
          [
            "  Since the previous version: " <>
              "events added #{length(c.events_added)}, removed #{length(c.events_removed)}."
          ] ++ declarations_changed(c.declarations)
      end

    [
      "PROCESS MODULE: #{deployment.process}",
      "  Version #{deployment.deployed.version}, #{since}."
    ] ++
      change ++ [""]
  end

  # The line events and paths could never carry: a promise whose window moved, or an
  # event whose field became `personal:`, adds and removes nothing. Named rather than counted,
  # because "2 declarations changed" sends the reader looking and the names end the
  # search.
  @spec declarations_changed(map() | :not_recorded) :: [String.t()]
  defp declarations_changed(:not_recorded) do
    [
      "  What the declarations said under the previous version was not recorded, " <>
        "so it cannot be compared."
    ]
  end

  defp declarations_changed(%{added: [], removed: [], changed: []}), do: []

  defp declarations_changed(d) do
    moved = d.changed ++ d.added ++ d.removed

    [
      "  Declarations changed: #{length(moved)} (#{Enum.join(moved, ", ")})."
    ]
  end

  @spec accountable(String.t() | nil) :: [String.t()]
  defp accountable(role) do
    case Sentence.accountable(role) do
      nil -> []
      line -> ["  " <> line]
    end
  end

  @spec duration(map() | nil) :: [String.t()]
  defp duration(d) do
    case Sentence.duration(d) do
      [] -> []
      # The second line is indented further because it qualifies the first, the same
      # way a step qualifies the heading above it.
      [judged] -> ["  " <> judged]
      [judged, still_open] -> ["  " <> judged, "    " <> still_open]
    end
  end

  @spec process(map()) :: [String.t()]
  defp process(p) do
    ["PROCESS: #{p.label}"] ++
      accountable(p.accountable) ++
      ["  Runs in this period: #{p.runs}."] ++
      declarations(p.declarations) ++
      duration(p.duration) ++
      assertions(p.promises) ++
      [""]
  end

  # Plan DD, P1a (#183): the contract's steps, whether or not it has a process.
  @spec steps(map(), map()) :: [String.t()]
  defp steps(activity, p) do
    ["STEPS", "  " <> Sentence.activity(activity)] ++ paths(activity, p) ++ [""]
  end

  # Confirmed declarations only. The 25-day deadline will not appear here until
  # somebody confirms it.
  @spec declarations([map()]) :: [String.t()]
  defp declarations(declared), do: for(d <- declared, do: "  " <> Sentence.declaration(d))

  # What waits has a heading of its own, never the list of what nobody did, and
  # "carried out" is said only when nothing waits either — a branch is several steps,
  # and only its head waits in a queue. With no event recorded nothing is judged
  # untraversed, and what waits and what fails is still said.
  @spec paths(map(), map()) :: [String.t()]
  defp paths(_activity, %{steps: []}), do: ["  " <> Sentence.no_steps()]

  defp paths(activity, p) do
    untraversed =
      case {activity.events, p.untraversed, p.in_flight, p.failing} do
        {0, _, [], []} ->
          ["  " <> Sentence.no_activity()]

        {0, _, _waiting, _failing} ->
          []

        {_, [], [], _} ->
          ["  " <> Sentence.all_steps_carried_out()]

        {_, [], _waiting, _} ->
          []

        {_, steps, _waiting, _} ->
          ["  Agreed steps that were never carried out:"] ++
            for s <- steps, do: "    · " <> Sentence.step(s)
      end

    waiting =
      case p.in_flight do
        [] ->
          []

        steps ->
          ["  Agreed steps in progress:"] ++
            for(s <- steps, do: "    · " <> Sentence.step_in_flight(s))
      end

    untraversed ++ waiting ++ failing(p.failing)
  end

  defp failing([]), do: []

  defp failing(steps) do
    ["  Agreed steps that are attempted and fail:"] ++
      for s <- steps, do: "    · " <> Sentence.step_failing(s)
  end

  # Plan LC3: an aggregate's lifecycle, under the same two questions as a process's
  # paths — what was declared and never taken, what was taken and never declared.
  @spec lifecycle(map()) :: [String.t()]
  defp lifecycle(l) do
    taken =
      case {l.aggregates, l.untraversed} do
        {0, _} ->
          ["  " <> Sentence.no_aggregates()]

        {_, []} when l.pending == [] ->
          ["  " <> Sentence.all_transitions_taken()]

        {_, []} ->
          []

        {_, transitions} ->
          ["  Declared transitions never taken:"] ++
            for t <- transitions, do: "    · " <> Sentence.transition(t)
      end

    pending =
      case {l.aggregates, l.pending} do
        {0, _} ->
          []

        {_, []} ->
          []

        {_, transitions} ->
          ["  Not taken yet — an aggregate still stands where they can happen:"] ++
            for t <- transitions, do: "    · " <> Sentence.transition(t)
      end

    undeclared =
      case l.undeclared do
        [] ->
          []

        moves ->
          ["  Happened, though the lifecycle does not allow it there:"] ++
            for m <- moves, do: "    · " <> Sentence.transition_undeclared(m)
      end

    ["LIFECYCLE: #{l.label}", "  Aggregates with an event in this period: #{l.aggregates}."] ++
      taken ++ pending ++ undeclared ++ [""]
  end

  @spec assertions([map()]) :: [String.t()]
  defp assertions(list) do
    Enum.flat_map(list, fn a -> ["  " <> Sentence.rule(a), "    " <> Sentence.outcome(a)] end)
  end

  @spec scenarios(map()) :: [String.t()]
  defp scenarios(s) do
    never =
      case s.never_observed do
        [] -> []
        descriptions -> ["  Never observed:"] ++ for(d <- descriptions, do: ~s(    · "#{d}"))
      end

    undeclared =
      case s.undeclared_outcomes do
        [] ->
          []

        outcomes ->
          ["  Outcomes no scenario declares:"] ++
            for(o <- outcomes, do: "    · " <> Sentence.outcome_undeclared(o))
      end

    ["SCENARIOS", "  " <> Sentence.scenarios_observed(s)] ++ never ++ undeclared ++ [""]
  end

  @spec drift([map()]) :: [String.t()]
  defp drift([]), do: ["DRIFT", "  " <> Sentence.no_drift(), ""]

  defp drift(edges) do
    ["DRIFT — happened, though it was not agreed:"] ++
      for(e <- edges, do: "  · " <> Sentence.drift(e)) ++ [""]
  end
end
