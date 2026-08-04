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
    {opts, _} = OptionParser.parse!(args, strict: [overlay: :boolean, mermaid: :boolean, since: :string])

    if opts[:overlay] do
      Mix.Task.run("app.start")
    else
      Mix.Task.run("compile")
      Application.load(:pns_prototype)
    end

    PNS.Registry.load!()

    if opts[:overlay], do: overlay(opts), else: static(opts)
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

      Mix.shell().info(Enum.join(["flowchart LR" | edges], "\n"))
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
      Mix.shell().info(PNS.Graph.to_mermaid(overlay))
    else
      Mix.shell().info("Nakładka declared vs observed:\n")
      Mix.shell().info(PNS.Graph.to_text(overlay))

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
end
