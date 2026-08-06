defmodule Taxvision.Report do
  @moduledoc """
  The conformance report for a period — four questions, one page, in Polish.

  **Rendering is the client's job, not the engine's, and that is not a detail.**
  `PNS.Conformance.report/2` produces the data; this module turns it into
  sentences. The engine cannot know what language its reader speaks — and this
  report is read by an accountant, not a programmer. If the package generated the
  headings, they would be English beside Polish labels from the contract, that is,
  the evidence artifact would be bilingual for no reason.

  This is why this module is the one place where output strings are Polish. Every
  identifier, comment and doc here is English like the rest of the codebase; only
  what the accountant reads is not.

  What is **not** here: declarations the process owner has not confirmed. The
  filter lives in `PNS.Conformance`, not here, because it is a rule about evidence
  rather than about formatting — but the consequence is visible right here: in the
  July report you will not find the 25-day deadline, because nobody from TaxVision
  confirmed it.
  """

  use Boundary, deps: [PNS], exports: []

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
      "RAPORT ZGODNOŚCI — #{period(report.period)}",
      "Czy wdrożony kod robi to, co mówi ustalony proces.",
      ""
    ]
  end

  @spec period(map()) :: String.t()
  defp period(%{since: nil, until: nil}), do: "cały log"
  defp period(%{since: since, until: nil}), do: "od #{day(since)}"
  defp period(%{since: nil, until: until}), do: "do #{day(until)}"
  defp period(%{since: since, until: until}), do: "#{day(since)} – #{day(until)}"

  @spec day(DateTime.t()) :: String.t()
  defp day(at), do: at |> DateTime.to_date() |> Date.to_string()

  @spec deployment(map()) :: [String.t()]
  defp deployment(deployment) do
    since =
      case deployment.deployed.since do
        nil -> "nic jeszcze nie zaszło pod tą wersją"
        at -> "obowiązuje od #{day(at)}"
      end

    change =
      case deployment.changed do
        nil ->
          []

        c ->
          [
            "  Od poprzedniej wersji: " <>
              "nowych zdarzeń #{length(c.events_added)}, usuniętych #{length(c.events_removed)}, " <>
              "nowych ścieżek #{length(c.paths_added)}, usuniętych #{length(c.paths_removed)}."
          ]
      end

    earlier =
      if deployment.from_earlier_versions > 0 do
        [
          "  Zdarzeń z wcześniejszych wersji ustaleń: #{deployment.from_earlier_versions}. " <>
            "To legalna historia, nie rozbieżność."
        ]
      else
        []
      end

    ["USTALENIA", "  Wersja ustaleń #{deployment.deployed.contract_version}, #{since}."] ++
      change ++ earlier ++ [""]
  end

  @spec process(map()) :: [String.t()]
  defp process(p) do
    ["PROCES: #{p.label}", "  Przebiegów w tym okresie: #{p.runs}."] ++
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
        :cadence -> "  Należny: co #{amount(value)}."
        :deadline -> "  Termin: #{amount(value)} od rozpoczęcia."
      end
    end
  end

  @spec amount({pos_integer(), atom()}) :: String.t()
  defp amount({1, :month}), do: "miesiąc"
  defp amount({n, :month}), do: "#{n} miesiące"
  defp amount({1, :day}), do: "dzień"
  defp amount({n, :day}), do: "#{n} dni"
  defp amount({n, unit}), do: "#{n} #{unit}"

  @spec paths(map()) :: [String.t()]
  defp paths(%{runs: 0}) do
    ["  Ustalonych kroków nie da się ocenić: w tym okresie nie było ani jednego przebiegu."]
  end

  defp paths(p) do
    untraversed =
      case p.untraversed do
        [] ->
          ["  Wszystkie ustalone kroki zostały w tym okresie wykonane."]

        steps ->
          ["  Ustalone kroki, których nie wykonano ani razu:"] ++
            for s <- steps, do: "    · #{step(s)}"
      end

    waiting =
      for s <- p.in_flight do
        "    · #{step(s)} — w trakcie, #{s.in_flight} w kolejce"
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
          ["  Ustalone kroki, które są próbowane i się nie udają:"] ++
            for s <- steps, do: "    · #{step(s)} — nie udało się w #{runs(s.failing)}"
      end

    untraversed ++ waiting ++ failing
  end

  @spec runs(pos_integer()) :: String.t()
  defp runs(1), do: "1 przebiegu"
  defp runs(n), do: "#{n} przebiegach"

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
  # technical name is all that could be printed — and a report for an accountant
  # that says `month_opens_or_is_blocked` does not meet the "readable without
  # explanation" criterion.
  @spec assertion(map()) :: [String.t()]
  defp assertion(a) do
    alternative = if a.or_else_label, do: ", albo „#{a.or_else_label}”", else: ""
    window = if a.within, do: " w ciągu #{amount(a.within)}", else: ""

    [
      "  Ustalenie: po „#{a.from_label}”#{window} następuje „#{a.eventually_label}”#{alternative}.",
      "    #{outcome(a)}"
    ]
  end

  @spec outcome(map()) :: String.t()
  defp outcome(a) do
    via =
      if a.satisfied_via_or_else > 0 do
        " (w tym #{a.satisfied_via_or_else} przez drugie z tych zakończeń, co jest zgodne z ustaleniem)"
      else
        ""
      end

    state =
      cond do
        a.instances == 0 -> "W tym okresie nie było przebiegu, na którym dałoby się to sprawdzić."
        a.violated > 0 -> "NIEDOTRZYMANE w #{a.violated} z #{a.instances} przebiegów."
        a.pending > 0 -> "Dotrzymane w #{a.satisfied} z #{a.instances}, #{a.pending} jeszcze w toku."
        true -> "Dotrzymane we wszystkich #{a.instances} przebiegach."
      end

    state <> via <> suspended(a)
  end

  # Named as somebody else's outage, not as the client's problem, and **not** counted among
  # the breaches. This is the whole value of the fourth verdict: without it these runs read
  # as "you broke your own agreement" when what happened is that a system you depend on
  # stopped answering.
  @spec suspended(map()) :: String.t()
  defp suspended(%{suspended: 0}), do: ""

  defp suspended(a) do
    " Zawieszone: #{runs(a.suspended)} — w oknie ustalenia zależność zewnętrzna była " <>
      "niedostępna, więc to nie jest niedotrzymanie po stronie klienta."
  end

  @spec drift([map()]) :: [String.t()]
  defp drift([]), do: ["ROZBIEŻNOŚCI", "  Brak: nic nie zaszło poza ustaleniami.", ""]

  defp drift(edges) do
    ["ROZBIEŻNOŚCI — zaszło, choć nie było ustalone:"] ++
      (for e <- edges do
         "  · #{e.from_label || e.from} → #{e.to_label || e.to}  (#{e.count}x)"
       end) ++ [""]
  end
end
