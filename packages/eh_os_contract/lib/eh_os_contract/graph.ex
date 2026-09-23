defmodule EhOsContract.Graph do
  @moduledoc """
  The static graph, the observed graph, and their overlay (notes §5, §9).

  Static graph = possible (a superset). Observed graph = actual (a weighted
  subset). **The join of the two is the product.**

  The overlay is not a union of two graphs. Every edge has a state and two
  independent dimensions: volume and health. An edge that fired 50 000 times and
  one that fired twice look identical in a three-state rendering — hence thickness
  separately.

  This module **does not draw a dashboard**. It produces the data a dashboard
  would stand on, which makes it possible to check whether the difference is
  signal or noise before anyone draws the first screen.
  """

  import Ecto.Query

  alias EhOsContract.{Event, Registry}

  @no_traffic %{count: 0, instances: 0}

  @doc """
  The graph from the declarations: nodes are the contracts' events, edges come
  from the handler registry. It comes from the binary that runs, not from a file
  beside it.
  """
  @spec static() :: %{nodes: [map()], edges: [map()]}
  def static do
    nodes =
      for event <- Registry.declared_events() do
        process = event.contract.process_of(event.name)

        %{
          event: event.name,
          label: event.label,
          owner: event.owner,
          contract: event.contract,
          contract_version: event.contract.version(),
          depends_on: event.depends_on,
          process: process && process.name,
          cadence: process && process.cadence,
          terminal?: event.terminal
        }
      end

    %{nodes: nodes, edges: Registry.edges()}
  end

  @doc """
  The graph from the log. An observed edge is a `causation_id` — an event that
  came out of another event. Nothing more has to be recorded to reconstruct what
  actually ran.

  Every counter has **two dimensions: occurrences and runs**. These are not the
  same number, and the difference between them is signal: an edge traversed 49
  times by one company and one traversed once by 49 companies have an identical
  occurrence count while saying opposite things. The version counting only
  occurrences hid silence exactly where there are many clients.

  `instance:` narrows to a single run — assertion evaluation uses that.
  """
  @spec observed(keyword()) :: %{nodes: map(), edges: map(), processes: map()}
  def observed(opts \\ []) do
    repo = repo()

    events = base_query(opts)

    # Grouping by the type alone rather than by the type+version pair: a run
    # spanning a deploy has events under two contract versions, so a sum of
    # `DISTINCT` per group would count it twice. Versions go into `array_agg`,
    # because they are a set rather than a grouping dimension.
    node_counts =
      events
      |> group_by([event: e], e.type)
      |> select([event: e], {
        e.type,
        count(e.id),
        count(e.instance_id, :distinct),
        fragment("array_agg(DISTINCT ?)", e.contract_version)
      })
      |> repo.all()
      |> Map.new(fn {type, count, instances, versions} ->
        {type, %{count: count, instances: instances, versions: versions}}
      end)

    edge_counts =
      events
      |> join(:inner, [event: e], parent in Event, on: e.causation_id == parent.id, as: :parent)
      |> group_by([event: e, parent: p], [p.type, e.type])
      |> select(
        [event: e, parent: p],
        {p.type, e.type, count(e.id), count(e.instance_id, :distinct)}
      )
      |> repo.all()
      |> Map.new(fn {from, to, count, instances} ->
        {{from, to}, %{count: count, instances: instances}}
      end)

    %{nodes: node_counts, edges: edge_counts, processes: process_instances(opts)}
  end

  @doc """
  How many **distinct runs** of each process the log has seen. This is the
  denominator without which a counter on an edge means nothing: "3 traversals"
  against three runs is complete, and against fifty it is the silence of
  forty-seven.

  Deliberately a **count, not a list**. Which particular runs are silent is a
  question about a specific company and belongs to the client application; EhOsContract
  answers the question about the path.
  """
  @spec process_instances(keyword()) :: %{String.t() => non_neg_integer()}
  def process_instances(opts \\ []) do
    repo = repo()

    opts
    |> base_query()
    |> where([event: e], not is_nil(e.instance_id))
    |> group_by([event: e], e.process)
    |> select([event: e], {e.process, count(e.instance_id, :distinct)})
    |> repo.all()
    |> Map.new()
  end

  @spec base_query(keyword()) :: Ecto.Query.t()
  defp base_query(opts) do
    from(e in Event, as: :event)
    |> maybe_since(Keyword.get(opts, :since))
    |> maybe_until(Keyword.get(opts, :until))
    |> maybe_instance(Keyword.get(opts, :instance))
  end

  @doc """
  The overlay. Three states plus a fourth, which is the whole reason
  `contract_version` sits on the event:

  | State | Meaning |
  |---|---|
  | `:confirmed` | declared and observed |
  | `:dead` | declared, never observed — a dead path or an untested one |
  | `:drift` | observed, not declared |
  | `:historical` | observed under a different contract version — legitimate history, **not** drift |

  Without the fourth state, every deploy that removes an event produces false
  alarms, and the dashboard stops being believed within two releases.
  """
  @spec overlay(keyword()) :: [map()]
  def overlay(opts \\ []) do
    static = static()
    observed = observed(opts)
    in_flight = in_flight_by_handler()

    declared_edges = MapSet.new(static.edges, &{to_string(&1.from), to_string(&1.to)})
    current_versions = MapSet.new(static.nodes, & &1.contract_version)
    node_of = Map.new(static.nodes, &{to_string(&1.event), &1})

    from_declared =
      for edge <- static.edges do
        key = {to_string(edge.from), to_string(edge.to)}
        %{count: count, instances: instances} = Map.get(observed.edges, key, @no_traffic)

        waiting = Map.get(in_flight, inspect(edge.handler), 0)
        node = node_of[to_string(edge.to)]

        %{
          from: edge.from,
          to: edge.to,
          handler: edge.handler,
          async: edge.async,
          # An edge's process and contract come from its **target**: that is the
          # event meant to appear, so its run is the denominator here.
          process: node && node.process,
          contract: node && node.contract,
          count: count,
          # How many runs took this edge, and how many runs there were at all. An
          # occurrence count alone does not separate "everybody went through"
          # from "one went through fifty times and the rest are silent".
          instances: instances,
          of_instances: Map.get(observed.processes, to_string(node && node.process), 0),
          in_flight: waiting,
          # A third state, not two. A job waiting in the queue looks in the log
          # exactly like a path that never works — and that is the difference
          # between "broken" and "in a moment". Without it the overlay lies on
          # every ordinary delay, and the dashboard stops being believed.
          state:
            cond do
              count > 0 -> :confirmed
              waiting > 0 -> :in_flight
              true -> :dead
            end
        }
      end

    contracts = Registry.contracts()

    from_observed =
      for {{from, to}, traffic} <- observed.edges,
          not MapSet.member?(declared_edges, {from, to}) do
        # **The question is about the edge, not about the contract version.**
        # Previously the state came from the target event's `contract_version`,
        # which is an approximation and has a hole: removing a handler changes the
        # graph without changing a single version, so a legitimately traversed
        # path came out as `:drift`. Recorded deployments answer directly: was
        # this edge ever declared.
        declared_before? =
          Enum.any?(contracts, &EhOsContract.Deployment.declared_edge?(&1, {from, to}))

        versions = get_in(observed.nodes, [to, :versions]) || []
        # A fallback for a log older than the deployments table. Explicit, not
        # silent: a report that guesses without saying so is worse than one that
        # admits the gap.
        historical? =
          declared_before? or Enum.all?(versions, &(not MapSet.member?(current_versions, &1)))

        %{
          from: from,
          to: to,
          handler: nil,
          async: nil,
          process: nil,
          contract: nil,
          count: traffic.count,
          instances: traffic.instances,
          of_instances: 0,
          in_flight: 0,
          state: if(historical?, do: :historical, else: :drift)
        }
      end

    from_declared ++ from_observed
  end

  @doc """
  Jobs waiting in the queue, per handler. The states `available`/`scheduled`/
  `executing`/`retryable` mean "not yet", not "never".
  """
  @spec in_flight_by_handler() :: %{String.t() => non_neg_integer()}
  def in_flight_by_handler do
    repo = repo()

    from(j in Oban.Job,
      where: j.state in ["available", "scheduled", "executing", "retryable"],
      group_by: fragment("?->>'handler'", j.args),
      select: {fragment("?->>'handler'", j.args), count(j.id)}
    )
    |> repo.all()
    |> Map.new()
  end

  @doc """
  Events that came out of **the same command** — a shared `correlation_id` and no
  cause.

  This is not causation and must not be mixed with the edges from `causation_id`:
  none of them caused another, the same command caused all of them. But without it
  the three events that open a month hang on the diagram unconnected and look like
  a bug to the very person this view exists for.
  """
  @spec command_siblings(keyword()) :: %{{String.t(), String.t()} => non_neg_integer()}
  def command_siblings(opts \\ []) do
    repo = repo()
    since = Keyword.get(opts, :since)

    from(e in Event, as: :event, where: is_nil(e.causation_id))
    |> maybe_since(since)
    |> select([event: e], {e.correlation_id, e.type, e.occurred_at})
    |> repo.all()
    |> Enum.group_by(fn {correlation, _type, _at} -> correlation end)
    |> Enum.flat_map(fn {_correlation, rows} ->
      rows
      |> Enum.sort_by(fn {_c, _t, at} -> at end)
      |> Enum.map(fn {_c, type, _at} -> type end)
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [from, to] -> {from, to} end)
    end)
    |> Enum.frequencies()
  end

  @doc """
  Events that are declared and were never observed.

  The window is the weak point here and it has to be said outright: properly it
  comes from the process's `cadence:` — an instance is missing once a cycle has
  passed without one, not once an arbitrary window has. A monthly closing flagged
  dead after a week is noise that kills trust in the whole view.
  """
  @spec declared_never_observed(keyword()) :: [map()]
  def declared_never_observed(opts \\ []) do
    observed = observed(opts)
    pending = pending_events()

    for node <- static().nodes,
        not Map.has_key?(observed.nodes, to_string(node.event)),
        # An event that a queued job will produce is **not** a dead path. Without
        # this the list and the edge state would say two different things about
        # the same event.
        node.event not in pending do
      %{
        event: node.event,
        label: node.label,
        contract: node.contract,
        process: node.process,
        cadence: node.cadence
      }
    end
  end

  @doc "Events that queued jobs are going to produce."
  @spec pending_events() :: [atom()]
  def pending_events do
    waiting = in_flight_by_handler()

    for handler <- Registry.handlers(),
        Map.get(waiting, inspect(handler.module), 0) > 0,
        event <- handler.publishes,
        do: event
  end

  @doc """
  The overlay as a diagram.

  **Every** node is printed, including those with no edges at all. The first
  version drew only edges and showed five of eleven declared events — so
  unimplemented stages were invisible in exactly the tool meant to show what is
  missing. For a *declared versus observed* view that is a bug, not a cosmetic
  detail.
  """
  @spec to_mermaid([map()], keyword()) :: String.t()
  def to_mermaid(overlay, opts \\ []) do
    static = static()
    # A node's state comes from the event counters, **not from the edges**. The
    # first version read it from the edges and showed three observed events as
    # dead — because nothing subscribes to them, so they appear in no edge. An
    # event can be observed with no edge at all, and that is an ordinary case
    # rather than an exception.
    observed = observed(opts).nodes
    pending = pending_events()

    nodes =
      for node <- static.nodes do
        entry = Map.get(observed, to_string(node.event))

        state =
          cond do
            entry -> "confirmed"
            node.event in pending -> "in_flight"
            true -> "dead"
          end

        {node.event, state, node.label, entry}
      end

    node_lines =
      for {event, _state, label, entry} <- nodes do
        # Occurrences and runs side by side on the diagram too. An occurrence
        # count alone in a picture is the same half-truth as in the text report,
        # and more people look at the picture.
        suffix = if entry, do: " (#{entry.count}x, #{runs(entry.instances)})", else: ""
        ~s(    #{event}["#{label}#{suffix}"])
      end

    sibling_lines =
      for {{from, to}, count} <- command_siblings(opts) do
        # A dotted line **with no arrowhead** and an explicit caption. If it
        # looked like an arrow, somebody would read it as causation and build
        # logic on top of it.
        "    #{from} -. #{count}x same command .- #{to}"
      end

    edge_lines =
      for edge <- overlay do
        # `-. text .->` and `|label|` are mutually exclusive in mermaid syntax —
        # for a dotted arrow everything goes into the pipes.
        # A fraction rather than a bare number: "3x" does not separate three runs
        # that went through from one that went through three times — and with
        # five runs, the difference between 3/5 and 5/5 is the whole information.
        traversals = "#{edge.instances}/#{edge.of_instances} runs"

        {arrow, label} =
          if edge.async,
            do: {"-.->", "#{edge.count}x async · #{traversals}"},
            else: {"-->", "#{edge.count}x · #{traversals}"}

        "    #{edge.from} #{arrow}|#{label}| #{edge.to}"
      end

    class_lines =
      nodes
      |> Enum.group_by(fn {_e, state, _l, _c} -> state end, fn {e, _s, _l, _c} -> e end)
      |> Enum.map(fn {state, events} -> "    class #{Enum.join(events, ",")} #{state}" end)

    Enum.join(
      ["flowchart LR"] ++
        node_lines ++
        sibling_lines ++
        edge_lines ++
        class_lines ++
        [
          "    classDef confirmed fill:#c8e6c9,stroke:#2e7d32,color:#000",
          "    classDef in_flight fill:#fff3c4,stroke:#f9a825,color:#000",
          "    classDef dead fill:#eeeeee,stroke:#9e9e9e,color:#616161,stroke-dasharray: 4 3"
        ],
      "\n"
    )
  end

  @doc """
  One process's **declared shape** as a mermaid diagram: stages as lanes, the
  events in them, how it can end, and each assertion as an arrow carrying its
  window.

  ## This is not the graph that was rejected

  `PLAN.md` records a dated finding that a diagram was not worth building: eleven
  events gave three edges and it said nothing a sorted list did not. That was the
  **handler graph** — edges from the registry — drawn for the team's evidence
  screen. This is a different picture for a different reader.

  The distinction is not a nicety, it is the whole reason this can be worth
  drawing. A contract with no implementation has **no handler edges at all**, so
  the rejected picture of a contract written before its implementation is a row of
  unconnected boxes. The sequence in a contract does not live in its edges; it
  lives in `stages`, `terminal` and `trace`, and none of the three appears on the
  handler graph.

  ## Who it is for

  The process owner, before anything is built — the reader `docs/warsztat-rehmed.md`
  is written for. So the nodes carry `label`, which is the one place in the whole
  system written in the client's language, and the assertion arrows carry the
  number, because a claim with a number is the only thing somebody can correct.

  **A picture is easier to nod at than to correct**, which is why this is meant to
  sit above the assertion sentences rather than replace them. The measure of a
  validation session is corrections, not agreement.

  ## What it deliberately does not show

  Payload fields, `identity`, `retain`, `owner`, `rule`. Those are for whoever
  writes the code. A diagram showing everything the contract holds would be the
  module again, and the module is what the reader could not read.
  """
  @spec declared_to_mermaid(module(), atom()) :: String.t()
  def declared_to_mermaid(contract, process_name) do
    process =
      Enum.find(contract.processes(), &(&1.name == process_name)) ||
        raise ArgumentError, "#{inspect(contract)} declares no process #{inspect(process_name)}"

    events = contract.events_of(process_name)
    traces = Enum.filter(contract.traces(), &(contract.process_of(&1.from).name == process_name))

    Enum.join(
      ["flowchart TB"] ++
        declared_lanes(process, events) ++
        declared_assertions(traces) ++
        declared_dependencies(contract, events) ++
        declared_classes(events),
      "\n"
    )
  end

  defp declared_lanes(%{stages: []}, events) do
    for e <- events, do: ~s(    #{e.name}["#{escape(e.label)}"])
  end

  defp declared_lanes(process, events) do
    lanes =
      for stage <- process.stages do
        in_stage = Enum.filter(events, &(&1.stage == stage))

        # A stage with no events prints an empty lane rather than disappearing.
        # A declared phase nothing has been assigned to is a finding, and a
        # diagram that hides it is the wrong tool to find it with.
        body =
          case in_stage do
            [] -> [~s(        stage_#{stage}_empty[" "])]
            _ -> for e <- in_stage, do: ~s(        #{e.name}["#{escape(e.label)}"])
          end

        [~s(    subgraph stage_#{stage}["#{lane_title(stage, in_stage)}"])] ++ body ++ ["    end"]
      end

    # The order between stages is the only ordering claim a contract makes, so it
    # is the only arrow drawn between lanes.
    order =
      process.stages
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> "    stage_#{a} --> stage_#{b}" end)

    List.flatten(lanes) ++ order
  end

  # **A lane holding more than one event says so on its title.**
  #
  # Inside a stage a contract claims nothing about order, so those events are
  # drawn with no arrows between them — and to a reader who has not been told the
  # rule, boxes with no arrows read as *unfinished*, not as *deliberately
  # unordered*. The two collect completely different corrections, and the whole
  # point of putting this in front of a process owner is the corrections.
  #
  # One event alone carries no marker: there is nothing there to order.
  defp lane_title(stage, [_, _ | _]), do: "#{stage} · no order claimed inside"
  defp lane_title(stage, _one_or_none), do: "#{stage}"

  # The assertions, and they are why this picture carries information the
  # inventory does not: an arrow with a number on it is a claim somebody can
  # disagree with.
  defp declared_assertions(traces) do
    Enum.flat_map(traces, fn trace ->
      window =
        if trace.within,
          do: "within #{EhOsContract.Duration.humanize(trace.within)}",
          else: "eventually"

      eventually = "    #{trace.from} ==>|#{window}| #{trace.eventually}"

      case trace.or_else do
        nil -> [eventually]
        or_else -> [eventually, "    #{trace.from} -.->|or else| #{or_else}"]
      end
    end)
  end

  # A dashed line with **no arrowhead**, following the convention the overlay
  # already set for a relation that is not causation: a dependency is something a
  # fact rests on, not something it leads to.
  defp declared_dependencies(contract, events) do
    depended_on = events |> Enum.map(& &1.depends_on) |> Enum.filter(& &1) |> Enum.uniq()

    nodes =
      for name <- depended_on,
          external = Enum.find(contract.externals(), &(&1.name == name)),
          do: ~s|    #{name}[("#{escape(external.label)}")]|

    links = for e <- events, e.depends_on, do: "    #{e.name} -.- #{e.depends_on}"

    nodes ++ links
  end

  defp declared_classes(events) do
    terminal = for e <- events, e.terminal, do: e.name
    external = events |> Enum.map(& &1.depends_on) |> Enum.filter(& &1) |> Enum.uniq()

    assignment = fn
      [], _class -> []
      names, class -> ["    class #{Enum.join(names, ",")} #{class}"]
    end

    assignment.(terminal, "terminal") ++
      assignment.(external, "external") ++
      [
        "    classDef terminal fill:#c8e6c9,stroke:#2e7d32,color:#000",
        "    classDef external fill:#eceff1,stroke:#546e7a,color:#000,stroke-dasharray: 4 3"
      ]
  end

  # A label is the client's own sentence and may hold anything they wrote. Only
  # the double quote actually breaks a quoted mermaid node.
  defp escape(label), do: String.replace(label, ~s("), "'")

  @doc "The overlay as one line per edge, for a terminal."
  @spec to_text([map()]) :: String.t()
  def to_text(overlay) do
    overlay
    |> Enum.sort_by(&{&1.state, -&1.count})
    |> Enum.map_join("\n", fn edge ->
      mode = if edge.async, do: "async", else: "sync "
      state = edge.state |> Atom.to_string() |> String.pad_trailing(10)
      queue = if Map.get(edge, :in_flight, 0) > 0, do: ", #{edge.in_flight} queued", else: ""
      # Both dimensions side by side, because on its own each of them lies.
      #
      # An event written before its process declared `instance:` has no run
      # identity and will never get one. "0 runs" against a non-zero occurrence
      # count would read as silence, and this is history — the same problem the
      # `:historical` state solves for contract versions.
      traversals =
        if edge.count > 0 and edge.instances == 0,
          do: "no run identity",
          else: "#{edge.instances}/#{edge.of_instances} runs"

      "  #{state} #{mode}  #{edge.from} -> #{edge.to}  (#{edge.count}x, #{traversals}#{queue})"
    end)
  end

  @spec runs(non_neg_integer()) :: String.t()
  defp runs(1), do: "1 run"
  defp runs(n), do: "#{n} runs"

  @spec maybe_since(Ecto.Query.t(), DateTime.t() | nil) :: Ecto.Query.t()
  defp maybe_since(query, nil), do: query
  defp maybe_since(query, since), do: where(query, [event: e], e.occurred_at >= ^since)

  # The evidence report is **for a period**, so it needs both bounds. `since`
  # alone means "from X until now", so a July report regenerated in September
  # would include August — and a proof that changes when reprinted is not a proof.
  @spec maybe_until(Ecto.Query.t(), DateTime.t() | nil) :: Ecto.Query.t()
  defp maybe_until(query, nil), do: query
  defp maybe_until(query, until), do: where(query, [event: e], e.occurred_at <= ^until)

  @spec maybe_instance(Ecto.Query.t(), String.t() | nil) :: Ecto.Query.t()
  defp maybe_instance(query, nil), do: query
  defp maybe_instance(query, id), do: where(query, [event: e], e.instance_id == ^id)

  # **Read at run time, not at compile time — and that changed when the engine
  # became its own application (2026-08-20).** `Application.compile_env!/2`
  # resolved to the host's repo module while compiling this package, and a package
  # compiles before the application that configures it: every call site warned that
  # the host's repo module was undefined, and in a real consumer it would warn about
  # theirs. A library cannot hold a compile-time reference to a module its user
  # has not written yet.
  #
  # What is lost is `compile_env!`'s check that configuration has not changed since
  # the build. What is gained is that this compiles standing alone, which is the
  # whole point of a package.
  defp repo, do: Application.fetch_env!(:eh_os_contract, :repo)
end
