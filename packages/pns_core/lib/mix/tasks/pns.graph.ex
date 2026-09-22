defmodule Mix.Tasks.Pns.Graph do
  @shortdoc "The event graph: static, and with --overlay laid over the log"

  @moduledoc """
  The static graph comes from the registry, that is, from the binary that runs.
  With `--overlay` it gains the counters from the log and the edge states.

  `--mermaid` prints a diagram. This is the seed of the dashboard — data without a
  screen, deliberately in that order: first check whether the difference is
  signal, then draw it.

  ## `--process` draws something else, for somebody else

      mix pns.graph --mermaid --process clinical_visit --output visit.mmd

  The two pictures above are **for the team**: what the binary wires together, and
  what the log says actually ran. `--process` draws one process's **declared
  shape** — stages as lanes, how it can end, each assertion as an arrow carrying
  its window — for the process owner, before anything is built.

  It is per process and never global on purpose. The default inventory this task
  prints is 33 events from four contracts in one flat list, which is useful to
  nobody outside the team and is the counter-example ADR §9 had in mind with
  *navigation is per-process, never global*.

  Use `--output`: Erlang keeps stdout in latin1 when it is not a terminal, and
  every node on this diagram is written in the client's language.
  """

  use Boundary, classify_to: PNS
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    # Erlang keeps stdout in latin1 when the output is not a terminal, so
    # `mix pns.graph > graph.txt` truncates every codepoint to a byte. Event
    # labels come from the contract and are written in the client's language.
    :io.setopts(:standard_io, encoding: :unicode)

    {opts, _} =
      OptionParser.parse!(args,
        strict: [
          overlay: :boolean,
          mermaid: :boolean,
          since: :string,
          output: :string,
          process: :string
        ]
      )

    if opts[:overlay] do
      Mix.Task.run("app.start")
    else
      Mix.Task.run("compile")
      Application.load(:pns)
    end

    PNS.Registry.load!()

    cond do
      opts[:process] -> declared(opts)
      opts[:overlay] -> overlay(opts)
      true -> static(opts)
    end
  end

  # The declared shape of one process, for a person who has not read the module.
  # Deliberately per process rather than global: ADR §9 says navigation is per
  # process and never global, and the flat inventory this task prints by default
  # is the counter-example — 33 events from four contracts in one list, useful to
  # nobody outside the team.
  defp declared(opts) do
    name = String.to_atom(opts[:process])

    contract =
      Enum.find(PNS.Registry.contracts(), fn c ->
        Enum.any?(c.processes(), &(&1.name == name))
      end)

    unless contract do
      known =
        PNS.Registry.contracts()
        |> Enum.flat_map(fn c -> Enum.map(c.processes(), & &1.name) end)
        |> Enum.sort()
        |> Enum.join(", ")

      Mix.raise("no process #{inspect(name)}. Declared: #{known}")
    end

    if opts[:mermaid] do
      emit_output(PNS.Graph.declared_to_mermaid(contract, name), opts)
    else
      Mix.raise("--process draws a diagram; pass --mermaid (and --output to keep the accents)")
    end
  end

  # Erlang switches stdout to latin1 when the output is not a terminal, so
  # `mix pns.graph --mermaid > file.mmd` corrupts every non-ASCII character:
  # U+0142 comes out as byte 0x42. Event labels are written in the client's
  # language, so this is not cosmetic. `--output` writes through `File.write!`,
  # which always writes UTF-8.
  defp emit_output(text, opts) do
    case opts[:output] do
      nil ->
        Mix.shell().info(text)

      path ->
        File.write!(path, text)
        Mix.shell().info("written: #{path}")
    end
  end

  defp static(opts) do
    graph = PNS.Graph.static()

    Mix.shell().info("Declared events: #{length(graph.nodes)}")
    Mix.shell().info("Edges from the handler registry: #{length(graph.edges)}\n")

    if opts[:mermaid] do
      edges =
        for edge <- graph.edges do
          arrow = if edge.async, do: "-. async .->", else: "-->"
          "    #{edge.from} #{arrow} #{edge.to}"
        end

      emit_output(Enum.join(["flowchart LR" | edges], "\n"), opts)
    else
      for node <- graph.nodes do
        marks = [node.terminal? && "terminal", node.depends_on && "depends on #{node.depends_on}"]
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
    since =
      opts[:since] && NaiveDateTime.from_iso8601!(opts[:since]) |> DateTime.from_naive!("Etc/UTC")

    overlay = PNS.Graph.overlay(since: since)

    if opts[:mermaid] do
      emit_output(PNS.Graph.to_mermaid(overlay), opts)
    else
      versions()
      Mix.shell().info("\nDeclared versus observed overlay:\n")
      Mix.shell().info(PNS.Graph.to_text(overlay))

      paths(since)

      dead = PNS.Graph.declared_never_observed(since: since)

      if dead != [] do
        Mix.shell().info("\nDeclared, never observed:")

        for event <- dead do
          window =
            if event.cadence,
              do: "cycle #{inspect(event.cadence)}",
              else: "no cadence — window guessed"

          Mix.shell().info("  #{event.event}  — #{event.label}  [#{window}]")
        end
      end
    end
  end

  # The fourth of the screen's four questions: which version is deployed, since
  # when, which versions the log holds, and what changed.
  defp versions do
    for contract <- PNS.Registry.contracts() do
      r = PNS.Deployment.report(contract)

      since =
        if r.deployed.since,
          do: DateTime.to_iso8601(r.deployed.since),
          else: "nothing emitted yet"

      Mix.shell().info("#{inspect(contract)}")

      Mix.shell().info(
        "  contract #{r.deployed.contract_version}, wiring " <>
          "#{r.deployed.wiring_version || "not recorded"} — since #{since}"
      )

      case r.in_log do
        [] ->
          Mix.shell().info("  log empty")

        in_log ->
          Mix.shell().info(
            "  versions in the log: #{length(in_log)}, " <>
              "events from versions other than the deployed one: #{r.from_earlier_versions}"
          )
      end

      case r.changed do
        nil ->
          Mix.shell().info("  one recorded deployment — nothing to compare against")

        change ->
          Mix.shell().info(
            "  last change: events +#{length(change.events_added)}/-#{length(change.events_removed)}, " <>
              "paths +#{length(change.paths_added)}/-#{length(change.paths_removed)}"
          )
      end
    end
  end

  # The first of the screen's four questions, counted **per run**: which declared
  # paths no run has taken.
  defp paths(since) do
    for report <- PNS.Conformance.untraversed_paths(since: since) do
      Mix.shell().info("\nUntraversed paths — process #{inspect(report.process)}:")

      case report do
        %{basis: :no_paths} ->
          # Staying silent about such a process would be silence pretending to be
          # health.
          Mix.shell().info("  the contract declares no path at all for this process")

        %{basis: :no_runs} ->
          # Zero runs is no basis, neither a green nor a red report.
          Mix.shell().info("  no runs in the log — nothing to judge")

        %{untraversed: [], in_flight: []} ->
          Mix.shell().info("  all #{report.paths} paths traversed (#{report.instances} runs)")

        %{untraversed: untraversed} ->
          Mix.shell().info(
            "  #{length(untraversed)} of #{report.paths} untraversed, " <>
              "#{report.instances} runs in the log"
          )

          for edge <- untraversed do
            Mix.shell().info("    #{edge.from} -> #{edge.to}   (#{inspect(edge.handler)})")
          end

          for edge <- report.in_flight do
            Mix.shell().info(
              "    #{edge.from} -> #{edge.to}   — #{edge.in_flight} queued, so not yet"
            )
          end
      end
    end
  end
end
