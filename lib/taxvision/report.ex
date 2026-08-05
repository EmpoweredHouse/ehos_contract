defmodule Taxvision.Report do
  @moduledoc """
  Raport zgodności za okres — cztery pytania, jedna strona, po polsku.

  **Renderowanie jest po stronie klienta, nie silnika, i to nie jest detal.**
  `PNS.Conformance.report/2` produkuje dane; ten moduł zamienia je w zdania.
  Silnik nie może wiedzieć, w jakim języku czyta jego odbiorca — a ten raport
  czyta księgowa, nie programista. Gdyby nagłówki generował pakiet, byłyby po
  angielsku obok polskich etykiet z kontraktu, czyli artefakt dowodowy byłby
  dwujęzyczny bez powodu.

  Jedyne polskie zdania w danych to `label` z kontraktu i one są tu treścią:
  „Potwierdzono komplet danych historycznych", nie `data_completeness_confirmed`.
  Kryterium odbioru brzmi „czytelny bez tłumaczenia, co znaczą kolumny", więc
  nazwa techniczna pojawia się wyłącznie jako dopisek, nigdy sama.

  Czego tu **nie ma**: deklaracji, których nie potwierdził process owner. Filtr
  jest w `PNS.Conformance`, nie tutaj, bo to reguła o dowodzie, a nie o
  formatowaniu — ale konsekwencja jest widoczna właśnie tutaj: w raporcie za
  lipiec nie znajdziesz terminu 25 dni, bo nikt z TaxVision go nie potwierdził.
  """

  use Boundary, deps: [PNS], exports: []

  @doc "Raport dla jednego kontraktu za okres, jako tekst do wypisania."
  @spec render(map()) :: String.t()
  def render(report) do
    [
      naglowek(report),
      wdrozenie(report.deployment),
      Enum.map(report.processes, &proces/1),
      drift(report.drift)
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp naglowek(report) do
    [
      "RAPORT ZGODNOŚCI — #{okres(report.period)}",
      "Czy wdrożony kod robi to, co mówi ustalony proces.",
      ""
    ]
  end

  defp okres(%{since: nil, until: nil}), do: "cały log"
  defp okres(%{since: since, until: nil}), do: "od #{dzien(since)}"
  defp okres(%{since: nil, until: until}), do: "do #{dzien(until)}"
  defp okres(%{since: since, until: until}), do: "#{dzien(since)} – #{dzien(until)}"

  defp dzien(at), do: at |> DateTime.to_date() |> Date.to_string()

  defp wdrozenie(deployment) do
    od =
      case deployment.deployed.since do
        nil -> "nic jeszcze nie zaszło pod tą wersją"
        at -> "obowiązuje od #{dzien(at)}"
      end

    zmiana =
      case deployment.changed do
        nil ->
          []

        z ->
          [
            "  Od poprzedniej wersji: " <>
              "nowych zdarzeń #{length(z.events_added)}, usuniętych #{length(z.events_removed)}, " <>
              "nowych ścieżek #{length(z.paths_added)}, usuniętych #{length(z.paths_removed)}."
          ]
      end

    starsze =
      if deployment.from_earlier_versions > 0 do
        [
          "  Zdarzeń z wcześniejszych wersji ustaleń: #{deployment.from_earlier_versions}. " <>
            "To legalna historia, nie rozbieżność."
        ]
      else
        []
      end

    ["USTALENIA", "  Wersja ustaleń #{deployment.deployed.contract_version}, #{od}."] ++
      zmiana ++ starsze ++ [""]
  end

  defp proces(p) do
    ["PROCES: #{p.label}", "  Przebiegów w tym okresie: #{p.runs}."] ++
      deklaracje(p.declarations) ++
      sciezki(p) ++
      assercje(p.assertions) ++
      [""]
  end

  # Tylko potwierdzone. Termin 25 dni tu nie wystąpi, dopóki go nikt nie potwierdzi.
  defp deklaracje([]), do: []

  defp deklaracje(declarations) do
    for %{key: key, value: value} <- declarations do
      case key do
        :cadence -> "  Należny: co #{ilosc(value)}."
        :deadline -> "  Termin: #{ilosc(value)} od rozpoczęcia."
      end
    end
  end

  defp ilosc({1, :month}), do: "miesiąc"
  defp ilosc({n, :month}), do: "#{n} miesiące"
  defp ilosc({1, :day}), do: "dzień"
  defp ilosc({n, :day}), do: "#{n} dni"
  defp ilosc({n, unit}), do: "#{n} #{unit}"

  defp sciezki(%{runs: 0}) do
    ["  Ustalonych kroków nie da się ocenić: w tym okresie nie było ani jednego przebiegu."]
  end

  defp sciezki(p) do
    nieprzejechane =
      case p.untraversed do
        [] ->
          ["  Wszystkie ustalone kroki zostały w tym okresie wykonane."]

        kroki ->
          ["  Ustalone kroki, których nie wykonano ani razu:"] ++
            for k <- kroki, do: "    · #{krok(k)}"
      end

    czekajace =
      for k <- p.in_flight do
        "    · #{krok(k)} — w trakcie, #{k.in_flight} w kolejce"
      end

    nieprzejechane ++ czekajace
  end

  # Etykiety biznesowe, nazwa techniczna tylko jako dopisek. Kryterium odbioru:
  # czytelne bez tłumaczenia, co znaczą kolumny.
  defp krok(k), do: "#{k.from_label} → #{k.to_label}"

  defp assercje([]), do: []

  defp assercje(assertions) do
    Enum.flat_map(assertions, &assercja/1)
  end

  # Zdanie, nie nazwa. `trace` jest jedyną deklaracją bez `label`, więc nazwa
  # techniczna byłaby wszystkim, co można by wypisać — a raport dla księgowej,
  # który mówi `month_opens_or_is_blocked`, nie spełnia kryterium „czytelny bez
  # tłumaczenia".
  defp assercja(a) do
    albo = if a.or_else_label, do: ", albo „#{a.or_else_label}”", else: ""
    okno = if a.within, do: " w ciągu #{ilosc(a.within)}", else: ""

    [
      "  Ustalenie: po „#{a.from_label}”#{okno} następuje „#{a.eventually_label}”#{albo}.",
      "    #{wynik(a)}"
    ]
  end

  defp wynik(a) do
    droga =
      if a.satisfied_via_or_else > 0 do
        " (w tym #{a.satisfied_via_or_else} przez drugie z tych zakończeń, co jest zgodne z ustaleniem)"
      else
        ""
      end

    stan =
      cond do
        a.instances == 0 -> "W tym okresie nie było przebiegu, na którym dałoby się to sprawdzić."
        a.violated > 0 -> "NIEDOTRZYMANE w #{a.violated} z #{a.instances} przebiegów."
        a.pending > 0 -> "Dotrzymane w #{a.satisfied} z #{a.instances}, #{a.pending} jeszcze w toku."
        true -> "Dotrzymane we wszystkich #{a.instances} przebiegach."
      end

    stan <> droga
  end

  defp drift([]), do: ["ROZBIEŻNOŚCI", "  Brak: nic nie zaszło poza ustaleniami.", ""]

  defp drift(edges) do
    ["ROZBIEŻNOŚCI — zaszło, choć nie było ustalone:"] ++
      (for e <- edges do
         "  · #{e.from_label || e.from} → #{e.to_label || e.to}  (#{e.count}x)"
       end) ++ [""]
  end
end
