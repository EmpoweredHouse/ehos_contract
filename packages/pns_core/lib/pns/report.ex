defmodule PNS.Report do
  @moduledoc """
  The conformance report for a period — four questions, one page.

  Rendered here rather than in the application, which reverses an earlier decision:
  the sentences used to be built client-side, on the argument that the engine cannot
  know what language its reader speaks. The engine now writes its own sentences in
  English and passes the contract's `label` through untouched, so a declaration
  written in the reader's language stays in it. The engine translates its own words
  and never somebody else's.

  **The scaffolding is English; the contract's own labels are not translated.**
  `from_label`, `to_label` and a process's `label` print exactly as the contract
  declares them — TaxVision's are Polish, a future contract's might not be. The
  engine writes its own sentences in one language; it still does not decide what
  language the client wrote their labels in.

  What is **not** here, unchanged from before the move: declarations the process
  owner has not confirmed. The filter lives in `PNS.Conformance`, not here, because
  it is a rule about evidence rather than about formatting — the consequence is
  visible right here: an unconfirmed `deadline` never reaches `render/1`'s input.
  """

  alias PNS.Report.Sentence

  @doc "The report for one contract over a period, as text to print."
  @spec render(map()) :: String.t()
  def render(report) do
    [
      header(report),
      deployment(report.deployment),
      Enum.map(report.processes, &process/1),
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
      "Computed by PNS #{report.engine}.",
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

  @spec deployment(map()) :: [String.t()]
  defp deployment(deployment) do
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

    ["CONTRACT", "  Version #{deployment.deployed.contract_version}, #{since}."] ++
      change ++ earlier ++ [""]
  end

  # The line events and paths could never carry: a `trace` whose window moved, or an
  # event whose `retain` moved, adds and removes nothing. Named rather than counted,
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
      paths(p) ++
      assertions(p.assertions) ++
      [""]
  end

  # Confirmed declarations only. The 25-day deadline will not appear here until
  # somebody confirms it.
  @spec declarations([map()]) :: [String.t()]
  defp declarations(declared), do: for(d <- declared, do: "  " <> Sentence.declaration(d))

  @spec paths(map()) :: [String.t()]
  defp paths(%{runs: 0}), do: ["  " <> Sentence.no_runs()]

  defp paths(p) do
    untraversed =
      case p.untraversed do
        [] ->
          ["  " <> Sentence.all_steps_carried_out()]

        steps ->
          ["  Agreed steps that were never carried out:"] ++
            for s <- steps, do: "    · " <> Sentence.step(s)
      end

    waiting = for s <- p.in_flight, do: "    · " <> Sentence.step_in_flight(s)

    failing =
      case p.failing do
        [] ->
          []

        steps ->
          ["  Agreed steps that are attempted and fail:"] ++
            for s <- steps, do: "    · " <> Sentence.step_failing(s)
      end

    untraversed ++ waiting ++ failing
  end

  @spec assertions([map()]) :: [String.t()]
  defp assertions(list) do
    Enum.flat_map(list, fn a -> ["  " <> Sentence.rule(a), "    " <> Sentence.outcome(a)] end)
  end

  @spec drift([map()]) :: [String.t()]
  defp drift([]), do: ["DRIFT", "  " <> Sentence.no_drift(), ""]

  defp drift(edges) do
    ["DRIFT — happened, though it was not agreed:"] ++
      for e <- edges do
        "  · #{e.from_label || e.from} → #{e.to_label || e.to}  (#{e.count}x)"
      end ++ [""]
  end
end
