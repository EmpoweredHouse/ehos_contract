defmodule Mix.Tasks.EhOsContract.Graph do
  @shortdoc "The event graph: static, and with --overlay laid over the log"

  @moduledoc """
  The static graph comes from the registry, that is, from the binary that runs.
  With `--overlay` it gains the counters from the log and the edge states.

  `--mermaid` prints a diagram. This is the seed of the dashboard — data without a
  screen, deliberately in that order: first check whether the difference is
  signal, then draw it.

  ## `--process` draws something else, for somebody else

      mix eh_os_contract.graph --mermaid --process clinical_visit --output visit.mmd

  The two pictures above are **for the team**: what the binary wires together, and
  what the log says actually ran. `--process` draws one process's **declared
  shape** — stages as lanes, how it can end, each assertion as an arrow carrying
  its window — for the process owner, before anything is built.

  **A v2 contract's process** has the same declared shape. With `--overlay` it is
  drawn as its contract's full graph instead, with the log laid over it (below).

  ## `--contract` and `--unit`: a v2 contract, whole or one unit of it

      mix eh_os_contract.graph --contract Rehmed.Contracts.VisitSettlement --output settlement.mmd
      mix eh_os_contract.graph --contract Rehmed.Contracts.VisitSettlement --overlay --output settlement.mmd
      mix eh_os_contract.graph --contract Rehmed.Contracts.VisitSettlement --unit visit_settlement --output unit.mmd

  `--contract` draws the contract's full graph (plan EG1,
  `EhOsContract.Graph.contract_to_mermaid/2`): commands, events, the consumers
  between them and timers, each kind in its Event Storming colour, and the actors,
  read models, queries and external systems around them. `--overlay` lays the log
  over its steps — runs per step, and what waits or fails there. `--unit` draws one
  unit instead (`EhOsContract.Graph.unit_to_mermaid/2`): its state, commands, events,
  invariants, and how many scenarios pin each path. Both are Mermaid, so `--mermaid`
  is not needed.

  ## `--map` and `--system`: a domain

      mix eh_os_contract.graph --map rehmed --output map.mmd
      mix eh_os_contract.graph --system rehmed --overlay --output system.mmd

  `--map` draws the domain's context map (plan EG2,
  `EhOsContract.Graph.context_map_to_mermaid/1`): subdomains, their contexts, the
  external systems and the relations between them. `--system` draws its v2
  contracts in their contexts and what one consumes from another
  (`EhOsContract.Graph.system_to_mermaid/3`); `--overlay` lays the log over it —
  runs per contract, and per edge the consumed events and what waits or fails at
  the consumer. Both take the domain's `name:`.

  A process's picture is per process and never global on purpose. The default
  inventory this task prints is 33 events from four contracts in one flat list,
  which is useful to nobody outside the team and is the counter-example ADR §9 had
  in mind with *navigation is per-process, never global*. The system is not that
  list: it draws contracts and what flows between them, and leaves each contract's
  own steps to `--contract`.

  Use `--output`: Erlang keeps stdout in latin1 when it is not a terminal, and
  every node on this diagram is written in the client's language.
  """

  use Boundary, classify_to: EhOsContract
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    # Erlang keeps stdout in latin1 when the output is not a terminal, so
    # `mix eh_os_contract.graph > graph.txt` truncates every codepoint to a byte. Event
    # labels come from the contract and are written in the client's language.
    :io.setopts(:standard_io, encoding: :unicode)

    {opts, _} =
      OptionParser.parse!(args,
        strict: [
          overlay: :boolean,
          mermaid: :boolean,
          since: :string,
          output: :string,
          process: :string,
          contract: :string,
          unit: :string,
          map: :string,
          system: :string
        ]
      )

    refuse_ignored!(opts)

    if opts[:overlay] do
      Mix.Task.run("app.start")
    else
      Mix.Task.run("compile")
      Application.load(:eh_os_contract)
    end

    EhOsContract.Registry.load!()

    cond do
      opts[:map] -> domain_picture(opts[:map], &EhOsContract.Graph.context_map_to_mermaid/1, opts)
      opts[:system] -> domain_picture(opts[:system], &system(&1, opts), opts)
      opts[:contract] -> contract(opts)
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
      Enum.find(EhOsContract.Registry.contracts(), fn c ->
        Enum.any?(EhOsContract.Model.processes(c), &(&1.name == name))
      end)

    v2 =
      Enum.find(EhOsContract.Registry.v2_contracts(), fn c ->
        match?(%{process: %{name: ^name}}, EhOsContract.Model.fetch(c))
      end)

    cond do
      not opts[:mermaid] ->
        Mix.raise("--process draws a diagram; pass --mermaid (and --output to keep the accents)")

      contract ->
        emit_output(EhOsContract.Graph.declared_to_mermaid(contract, name), opts)

      v2 && opts[:overlay] ->
        emit_output(
          EhOsContract.Graph.contract_to_mermaid(v2, overlay: true, since: since(opts)),
          opts
        )

      v2 ->
        emit_output(EhOsContract.Graph.declared_to_mermaid(v2, name), opts)

      true ->
        known =
          (Enum.flat_map(EhOsContract.Registry.contracts(), fn c ->
             Enum.map(EhOsContract.Model.processes(c), & &1.name)
           end) ++
             for(
               c <- EhOsContract.Registry.v2_contracts(),
               %{process: %{name: n}} <- [EhOsContract.Model.fetch(c)],
               do: n
             ))
          |> Enum.sort()
          |> Enum.join(", ")

        Mix.raise("no process #{inspect(name)}. Declared: #{known}")
    end
  end

  # A flag the picture asked for would not use is refused rather than dropped: a unit
  # draws no log, and a contract and a process are two different pictures.
  defp refuse_ignored!(opts) do
    pictures = for key <- [:map, :system, :contract, :process], opts[key], do: "--#{key}"

    cond do
      opts[:unit] && !opts[:contract] ->
        Mix.raise("--unit names a unit of a contract; pass --contract too")

      opts[:unit] && (opts[:overlay] || opts[:since]) ->
        Mix.raise("--unit draws the declarations only; --overlay and --since apply to --contract")

      opts[:map] && (opts[:overlay] || opts[:since]) ->
        Mix.raise(
          "--map draws the domain's declarations only; --overlay and --since apply to --system"
        )

      length(pictures) > 1 ->
        Mix.raise("#{Enum.join(pictures, " and ")} draw different pictures; pass one of them")

      true ->
        :ok
    end
  end

  # A picture of the domain named `name`, drawn by `draw` from its module.
  defp domain_picture(name, draw, opts) do
    domains = EhOsContract.Registry.domains()
    domain = Enum.find(domains, &(Atom.to_string(EhOsContract.Model.fetch(&1).name) == name))

    unless domain do
      known = domains |> Enum.map(&EhOsContract.Model.fetch(&1).name) |> Enum.sort()
      Mix.raise("no domain #{name}. Registered: #{Enum.join(known, ", ")}")
    end

    emit_output(draw.(domain), opts)
  end

  defp system(domain, opts) do
    EhOsContract.Graph.system_to_mermaid(domain, EhOsContract.Registry.v2_contracts(),
      overlay: opts[:overlay] || false,
      since: since(opts)
    )
  end

  # A v2 contract's full graph, or one of its units.
  defp contract(opts) do
    contracts = EhOsContract.Registry.v2_contracts()
    contract = Enum.find(contracts, &(inspect(&1) == opts[:contract]))

    unless contract do
      known = contracts |> Enum.map(&inspect/1) |> Enum.sort() |> Enum.join(", ")
      Mix.raise("no v2 contract #{opts[:contract]}. Registered: #{known}")
    end

    text =
      case opts[:unit] do
        nil ->
          EhOsContract.Graph.contract_to_mermaid(contract,
            overlay: opts[:overlay] || false,
            since: since(opts)
          )

        unit ->
          units = Enum.map(EhOsContract.Model.fetch(contract).units, &Atom.to_string(&1.name))

          unless unit in units,
            do:
              Mix.raise(
                "#{opts[:contract]} has no unit #{unit}. Units: #{Enum.join(units, ", ")}"
              )

          EhOsContract.Graph.unit_to_mermaid(contract, String.to_existing_atom(unit))
      end

    emit_output(text, opts)
  end

  defp since(opts),
    do:
      opts[:since] && NaiveDateTime.from_iso8601!(opts[:since]) |> DateTime.from_naive!("Etc/UTC")

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
    graph = EhOsContract.Graph.static()

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
    since = since(opts)
    overlay = EhOsContract.Graph.overlay(since: since)

    if opts[:mermaid] do
      emit_output(EhOsContract.Graph.to_mermaid(overlay), opts)
    else
      versions()
      Mix.shell().info("\nDeclared versus observed overlay:\n")
      Mix.shell().info(EhOsContract.Graph.to_text(overlay))

      paths(since)

      dead = EhOsContract.Graph.declared_never_observed(since: since)

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
    for contract <- EhOsContract.Registry.contracts() do
      r = EhOsContract.Deployment.report(contract)

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
    for report <- EhOsContract.Conformance.untraversed_paths(since: since) do
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
