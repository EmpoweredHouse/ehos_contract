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

  @spec process(map()) :: [String.t()]
  defp process(p) do
    ["PROCESS: #{p.label}", "  Runs in this period: #{p.runs}."] ++
      declarations(p.declarations) ++
      paths(p) ++
      assertions(p.assertions) ++
      [""]
  end

  # Confirmed declarations only. The 25-day deadline will not appear here until
  # somebody confirms it.
  @spec declarations([map()]) :: [String.t()]
  defp declarations([]), do: []

  defp declarations(declared) do
    for %{key: key, value: value} <- declared do
      case key do
        :cadence -> "  Due: every #{amount(value)}."
        :deadline -> "  Deadline: #{amount(value)} from the start."
      end
    end
  end

  # Delegated to `PNS.Duration`, which already owns everything else about units.
  # The hand-listed plurals that used to sit here covered `:month` and `:day` and
  # let every other unit through as "24 hour".
  @spec amount({pos_integer(), atom()}) :: String.t()
  defp amount(duration), do: PNS.Duration.humanize(duration)

  @spec paths(map()) :: [String.t()]
  defp paths(%{runs: 0}) do
    ["  The agreed steps cannot be judged: there was not a single run in this period."]
  end

  defp paths(p) do
    untraversed =
      case p.untraversed do
        [] ->
          ["  All agreed steps were carried out in this period."]

        steps ->
          ["  Agreed steps that were never carried out:"] ++
            for s <- steps, do: "    · #{step(s)}"
      end

    waiting =
      for s <- p.in_flight do
        "    · #{step(s)} — in progress, #{s.in_flight} queued"
      end

    # Separate from "never done", because it is a different finding for a different
    # reader: there the question is whether the step is still agreed, here it is that
    # the code is broken. Merging them puts a bug in front of the client as a
    # question about their process.
    failing =
      case p.failing do
        [] ->
          []

        steps ->
          ["  Agreed steps that are attempted and fail:"] ++
            for s <- steps, do: "    · #{step(s)} — failed in #{runs(s.failing)}"
      end

    untraversed ++ waiting ++ failing
  end

  @spec runs(pos_integer()) :: String.t()
  defp runs(1), do: "1 run"
  defp runs(n), do: "#{n} runs"

  # Business labels, with the technical name only as an aside. The acceptance
  # criterion: readable without explaining what the columns mean.
  @spec step(map()) :: String.t()
  defp step(s), do: "#{s.from_label} → #{s.to_label}"

  @spec assertions([map()]) :: [String.t()]
  defp assertions([]), do: []

  defp assertions(list) do
    Enum.flat_map(list, &assertion/1)
  end

  # A sentence, not a name. `trace` is the one declaration without a `label`, so a
  # technical name is all that could be printed — and a report that says
  # `month_opens_or_is_blocked` does not meet the "readable without explanation"
  # criterion.
  @spec assertion(map()) :: [String.t()]
  defp assertion(a) do
    alternative = if a.or_else_label, do: ", or else \"#{a.or_else_label}\"", else: ""
    window = if a.within, do: " within #{amount(a.within)}", else: ""

    [
      "  Rule: after \"#{a.from_label}\"#{window}, \"#{a.eventually_label}\" follows#{alternative}.",
      "    #{outcome(a)}"
    ]
  end

  @spec outcome(map()) :: String.t()
  defp outcome(a) do
    via =
      if a.satisfied_via_or_else > 0 do
        " (including #{a.satisfied_via_or_else} via the fallback ending, which conforms to the rule)"
      else
        ""
      end

    state =
      cond do
        # Two different sentences, and conflating them would be the same error this
        # report keeps being corrected for. "Nothing to judge" is an absence; "every
        # run here predates the current rule" is a fact about which promise was in
        # force, and the runs did happen.
        a.instances == 0 and a.under_earlier_declaration > 0 ->
          "No run in this period was judged under the rule as it now stands."

        a.instances == 0 ->
          "There was no run in this period on which this could be judged."

        a.violated > 0 ->
          "BREACHED in #{a.violated} of #{a.instances} runs."

        a.pending > 0 ->
          "Met in #{a.satisfied} of #{a.instances}, #{a.pending} still in progress."

        true ->
          "Met in all #{a.instances} runs."
      end

    state <> via <> suspended(a) <> earlier_declaration(a)
  end

  # The counts above describe runs judged under the rule as declared today. Runs
  # that began before it last changed were judged under a different promise, and
  # folding them in would let an edit to `within` retroactively turn a year of
  # conforming runs into breaches with nothing in the report to say why.
  #
  # Counted, not listed, and the date is given so a reader can narrow the period
  # themselves — which until now was the only way to get this truth at all, and
  # required already knowing the date.
  @spec earlier_declaration(map()) :: String.t()
  defp earlier_declaration(%{under_earlier_declaration: 0}), do: ""

  defp earlier_declaration(a) do
    " #{runs(a.under_earlier_declaration)} began before this rule was last changed " <>
      "(#{day(a.declaration_changed_at)}) and are not counted here — they were judged " <>
      "under a different promise."
  end

  # Named as somebody else's outage, not as the client's problem, and **not** counted among
  # the breaches. This is the whole value of the fourth verdict: without it these runs read
  # as "you broke your own agreement" when what happened is that a system you depend on
  # stopped answering.
  @spec suspended(map()) :: String.t()
  defp suspended(%{suspended: 0}), do: ""

  defp suspended(a) do
    " Suspended: #{runs(a.suspended)} — an external dependency was unavailable within the " <>
      "rule's window, so this is not a breach on the client's side."
  end

  @spec drift([map()]) :: [String.t()]
  defp drift([]), do: ["DRIFT", "  None: nothing happened outside the agreement.", ""]

  defp drift(edges) do
    ["DRIFT — happened, though it was not agreed:"] ++
      (for e <- edges do
         "  · #{e.from_label || e.from} → #{e.to_label || e.to}  (#{e.count}x)"
       end) ++ [""]
  end
end
