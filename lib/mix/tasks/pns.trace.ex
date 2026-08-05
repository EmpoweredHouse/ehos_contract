defmodule Mix.Tasks.Pns.Trace do
  @shortdoc "Ocena assercji `trace` z logu, per przebieg"

  @moduledoc """
  Wypisuje werdykty assercji z kontraktów przeciw temu, co jest w logu.

  Domyślnie **liczby, nie lista przebiegów** — bo raport odpowiada na pytanie o
  assercję, a nie o konkretną firmę. `--instances` włącza widok pojedynczych
  przebiegów, który notatki §9 przewidują do debugowania („co się stało z
  fakturą 4712"), nie do raportu dowodowego.
  """

  use Boundary, classify_to: PNS
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    # Erlang trzyma stdout w latin1, kiedy wyjście nie jest terminalem.
    :io.setopts(:standard_io, encoding: :unicode)

    {opts, _} = OptionParser.parse!(args, strict: [instances: :boolean, since: :string])

    Mix.Task.run("app.start")
    PNS.Registry.load!()

    since = opts[:since] && parse_since(opts[:since])

    for %{contract: contract, trace: name, verdicts: verdicts} <-
          PNS.Trace.evaluate_all(since: since) do
      raport(contract, name, verdicts, opts)
    end
  end

  defp raport(contract, name, verdicts, opts) do
    s = PNS.Trace.summary(verdicts)
    trace = Enum.find(contract.traces(), &(&1.name == name))

    Mix.shell().info("\n#{name}  (#{inspect(contract)})")
    Mix.shell().info("  po #{trace.from} → #{trace.eventually}#{okno(trace)}#{albo(trace)}")

    if s.instances == 0 do
      # Zero przebiegów to **brak podstawy do orzekania**, nie zero naruszeń.
      # Odwrotny odczyt zamieniłby niezaimplementowany proces w zielony raport.
      Mix.shell().info("  brak przebiegów, w których doszło do #{trace.from} — nie ma czego oceniać")
    else
      Mix.shell().info(
        "  spełniona #{s.satisfied}/#{s.instances}" <>
          " (#{s.satisfied_via_eventually} przez eventually, #{s.satisfied_via_or_else} przez or_else)" <>
          ", naruszona #{s.violated}, w toku #{s.pending}"
      )
    end

    if opts[:instances] do
      for w <- verdicts do
        droga = if w.via, do: " przez #{w.via}", else: ""
        Mix.shell().info("    #{String.pad_trailing(to_string(w.verdict), 10)}#{droga}  #{w.instance_id}")
      end
    end
  end

  defp okno(%{within: nil}), do: ""
  defp okno(%{within: {n, unit}}), do: " w ciągu #{n} #{unit}"

  defp albo(%{or_else: nil}), do: ""
  defp albo(%{or_else: event}), do: ", albo #{event}"

  defp parse_since(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _} -> at
      _ -> Mix.raise("--since wymaga daty ISO8601, np. 2026-07-01T00:00:00Z")
    end
  end
end
