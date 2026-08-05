defmodule Mix.Tasks.Pns.Graph do
  @shortdoc "Graf zdarzeń: statyczny, a z --overlay nałożony na log"

  @moduledoc """
  Graf statyczny pochodzi z rejestru, czyli z binarki, która działa.
  Z `--overlay` dochodzą liczniki z logu i stany krawędzi.

  `--mermaid` wypisuje diagram. To jest zarodek dashboardu — dane bez ekranu,
  celowo w tej kolejności: najpierw sprawdzić, czy różnica jest sygnałem, potem
  ją rysować.
  """

  use Boundary, classify_to: PNS
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    # Erlang trzyma stdout w latin1, kiedy wyjście nie jest terminalem, więc
    # `mix pns.check > raport.txt` przycina każdy kodepoint do bajtu: `ł` wychodzi
    # jako `B`. Etykiety zdarzeń są po polsku, bo to język klienta.
    :io.setopts(:standard_io, encoding: :unicode)

    {opts, _} =
      OptionParser.parse!(args,
        strict: [overlay: :boolean, mermaid: :boolean, since: :string, output: :string]
      )

    if opts[:overlay] do
      Mix.Task.run("app.start")
    else
      Mix.Task.run("compile")
      Application.load(:pns_prototype)
    end

    PNS.Registry.load!()

    if opts[:overlay], do: overlay(opts), else: static(opts)
  end

  # Erlang przestawia stdout na latin1, kiedy wyjście nie jest terminalem, więc
  # `mix pns.graph --mermaid > plik.mmd` psuje każdy polski znak: `ł` (U+0142)
  # wychodzi jako `B` (0x42). Nazwy zdarzeń są po polsku, bo to język klienta,
  # więc to nie jest kosmetyka. `--output` pisze plik przez `File.write!`, które
  # zawsze zapisuje UTF-8.
  defp emit_output(text, opts) do
    case opts[:output] do
      nil ->
        Mix.shell().info(text)

      path ->
        File.write!(path, text)
        Mix.shell().info("zapisano: #{path}")
    end
  end

  defp static(opts) do
    graph = PNS.Graph.static()

    Mix.shell().info("Zdarzenia zadeklarowane: #{length(graph.nodes)}")
    Mix.shell().info("Krawędzie z rejestru handlerów: #{length(graph.edges)}\n")

    if opts[:mermaid] do
      edges =
        for edge <- graph.edges do
          arrow = if edge.async, do: "-. async .->", else: "-->"
          "    #{edge.from} #{arrow} #{edge.to}"
        end

      emit_output(Enum.join(["flowchart LR" | edges], "\n"), opts)
    else
      for node <- graph.nodes do
        marks = [node.terminal? && "terminalne", node.depends_on && "zależy od #{node.depends_on}"]
        suffix = marks |> Enum.filter(& &1) |> Enum.join(", ")
        suffix = if suffix == "", do: "", else: "  [#{suffix}]"
        Mix.shell().info("  #{node.event}  — #{node.label}#{suffix}")
      end

      Mix.shell().info("")

      for edge <- graph.edges do
        mode = if edge.async, do: "async", else: "sync "
        Mix.shell().info("  #{mode}  #{edge.from} -> #{edge.to}  (#{inspect(edge.handler)})")
      end
    end
  end

  defp overlay(opts) do
    since = opts[:since] && NaiveDateTime.from_iso8601!(opts[:since]) |> DateTime.from_naive!("Etc/UTC")
    overlay = PNS.Graph.overlay(since: since)

    if opts[:mermaid] do
      emit_output(PNS.Graph.to_mermaid(overlay), opts)
    else
      Mix.shell().info("Nakładka declared vs observed:\n")
      Mix.shell().info(PNS.Graph.to_text(overlay))

      paths(since)

      dead = PNS.Graph.declared_never_observed(since: since)

      if dead != [] do
        Mix.shell().info("\nZadeklarowane, nigdy nie zaobserwowane:")

        for event <- dead do
          window = if event.cadence, do: "cykl #{inspect(event.cadence)}", else: "brak cadence — okno zgadywane"
          Mix.shell().info("  #{event.event}  — #{event.label}  [#{window}]")
        end
      end
    end
  end

  # Pierwsze z czterech pytań ekranu, liczone **per przebieg**: które
  # zadeklarowane ścieżki nie zostały przejechane przez żaden przebieg.
  defp paths(since) do
    for report <- PNS.Conformance.untraversed_paths(since: since) do
      Mix.shell().info("\nNieprzejechane ścieżki — proces #{inspect(report.process)}:")

      case report do
        %{basis: :no_runs} ->
          # Zero przebiegów to brak podstawy, nie zielony ani czerwony raport.
          Mix.shell().info("  brak przebiegów w logu — nie ma czego oceniać")

        %{untraversed: [], in_flight: []} ->
          Mix.shell().info("  wszystkie #{report.paths} ścieżek przejechane (#{report.instances} przebiegów)")

        %{untraversed: untraversed} ->
          Mix.shell().info("  #{length(untraversed)} z #{report.paths} nieprzejechanych, #{report.instances} przebiegów w logu")

          for edge <- untraversed do
            Mix.shell().info("    #{edge.from} -> #{edge.to}   (#{inspect(edge.handler)})")
          end

          for edge <- report.in_flight do
            Mix.shell().info("    #{edge.from} -> #{edge.to}   — #{edge.in_flight} w kolejce, czyli jeszcze nie")
          end
      end
    end
  end

end
