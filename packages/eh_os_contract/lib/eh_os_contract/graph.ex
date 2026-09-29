defmodule EhOsContract.Graph do
  @moduledoc """
  The contracts' graphs as Mermaid diagrams (notes §5, §9): one process's declared
  shape, a contract's steps, one unit, a domain's context map and its contracts as
  one system.

  The picture of a contract and of a system can lay the log over the declarations:
  declared = possible (a superset), observed = actual (a weighted subset). **The
  join of the two is the product.**

  This module **does not draw a dashboard**. It produces the diagrams a dashboard
  would stand on.
  """

  import Ecto.Query

  alias EhOsContract.Model
  alias EhOsContract.Graph.Mermaid

  @doc """
  One process's **declared shape** as a mermaid diagram: stages as lanes, the
  events in them, how it can end, and each assertion as an arrow carrying its
  window.

  ## This is not the graph that was rejected

  `PLAN.md` records a dated finding that a diagram was not worth building: eleven
  events gave three edges and it said nothing a sorted list did not. That was the
  **handler graph** — edges from handler registrations — drawn for the team's
  evidence screen. This is a different picture for a different reader.

  The distinction is not a nicety, it is the whole reason this can be worth
  drawing. A contract with no implementation has **no handler edges at all**, so
  the rejected picture of a contract written before its implementation is a row of
  unconnected boxes. The sequence in a contract does not live in its edges; it
  lives in `stages`, `terminal` and `promise`, and none of the three appeared on the
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

  Fields, `identity`, `personal:`, `rule`. Those are for whoever writes the code.
  A diagram showing everything the contract holds would be the module again, and
  the module is what the reader could not read.

  ## What it shows

  The process's stages as lanes (plan E7c), each titled by its label where it has
  one; the contract's own events in the stage group they sit in, and the events it
  includes where the `include` sits; each `promise` as an arrow; the externals from
  the domain.
  """
  @spec declared_to_mermaid(module(), atom()) :: String.t()
  def declared_to_mermaid(contract, process_name),
    do: contract |> Model.fetch() |> declared_v2(process_name)

  # **A contract's process** (plan E7c): its stages as lanes, titled by their label
  # where they have one; its own events in the stage group they
  # sit in, and the events it includes in the stage the `include` sits in; each
  # `promise` as an arrow with its window; the externals from the domain. The steps
  # between them are `contract_to_mermaid/2`'s picture, not this one.
  defp declared_v2(%{process: %{name: process_name} = process} = model, process_name) do
    own =
      for e <- model.events do
        %{
          name: e.name,
          label: e.label,
          stage: e.stage,
          terminal: e.terminal,
          depends_on: e.depends_on
        }
      end

    included =
      for include <- process.includes,
          {_contract, e} <- [Model.declaring(model, include.event)] do
        %{
          name: include.event,
          label: e.label,
          stage: include.stage,
          terminal: include.terminal,
          depends_on: e.depends_on
        }
      end

    traces =
      for p <- process.promises do
        %{p | within: p.within && {p.within.amount, p.within.unit}}
      end

    domain = Model.fetch(model.domain)
    externals = fn name -> Enum.find_value(domain.externals, &(&1.name == name && &1.label)) end

    Enum.join(
      ["flowchart TB"] ++
        declared_lanes(
          for(s <- process.stages, do: {s.name, s.label || "#{s.name}"}),
          own ++ included
        ) ++
        declared_assertions(traces) ++
        declared_dependencies(externals, own ++ included) ++
        declared_classes(own ++ included),
      "\n"
    )
  end

  defp declared_v2(model, process_name) do
    raise ArgumentError, "#{inspect(model.module)} declares no process #{inspect(process_name)}"
  end

  defp declared_lanes([], events) do
    for e <- events, do: ~s(    #{e.name}["#{Mermaid.escape(e.label)}"])
  end

  defp declared_lanes(stages, events) do
    lanes =
      for {stage, title} <- stages do
        in_stage = Enum.filter(events, &(&1.stage == stage))

        # A stage with no events prints an empty lane rather than disappearing.
        # A declared phase nothing has been assigned to is a finding, and a
        # diagram that hides it is the wrong tool to find it with.
        body =
          case in_stage do
            [] -> [~s(        stage_#{stage}_empty[" "])]
            _ -> for e <- in_stage, do: ~s(        #{e.name}["#{Mermaid.escape(e.label)}"])
          end

        [~s(    subgraph stage_#{stage}["#{Mermaid.escape(lane_title(title, in_stage))}"])] ++
          body ++ ["    end"]
      end

    # The order between stages is the only ordering claim a contract makes, so it
    # is the only arrow drawn between lanes.
    order =
      stages
      |> Enum.map(&elem(&1, 0))
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
  defp lane_title(title, [_, _ | _]), do: "#{title} · no order claimed inside"
  defp lane_title(title, _one_or_none), do: title

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

  # A dashed line with **no arrowhead**, for a relation that is not causation: a
  # dependency is something a fact rests on, not something it leads to.
  defp declared_dependencies(external_label, events) do
    depended_on = events |> Enum.map(& &1.depends_on) |> Enum.filter(& &1) |> Enum.uniq()

    nodes =
      for name <- depended_on,
          label = external_label.(name),
          do: ~s|    #{name}[("#{Mermaid.escape(label)}")]|

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

  @doc """
  A v2 contract's full graph as a Mermaid diagram (plan EG1): the steps of
  `EhOsContract.Paths` — commands, events, the policies, process managers and effects
  that react, and timers, each kind in its Event Storming colour — and around them
  the actors, read models, queries and external systems the contract names, each
  unit's commands and events in a group of their own. `overlay: true` lays the log
  over the steps, `since:` and `until:` bound it. See `EhOsContract.Graph.Contract`.
  """
  @spec contract_to_mermaid(module(), keyword()) :: String.t()
  def contract_to_mermaid(contract, opts \\ []),
    do: EhOsContract.Graph.Contract.to_mermaid(contract, opts)

  @doc """
  Unit `unit` of a v2 contract as a Mermaid diagram (plan EG1): its state, commands,
  events and invariants, with how many scenarios pin each path. See
  `EhOsContract.Graph.Unit`.
  """
  @spec unit_to_mermaid(module(), atom()) :: String.t()
  def unit_to_mermaid(contract, unit), do: EhOsContract.Graph.Unit.to_mermaid(contract, unit)

  @doc """
  A domain's context map as a Mermaid diagram (plan EG2): its subdomains as groups of
  their contexts, its external systems, and the relations between them. See
  `EhOsContract.Graph.ContextMap`.
  """
  @spec context_map_to_mermaid(module()) :: String.t()
  def context_map_to_mermaid(domain), do: EhOsContract.Graph.ContextMap.to_mermaid(domain)

  @doc """
  A domain's v2 contracts as one Mermaid diagram (plan EG2): each context a group of
  its contracts, and what one consumes from another, or through a publication, as
  the edges between them. `overlay: true` lays the log over it, `since:` and
  `until:` bound it. See `EhOsContract.Graph.System`.
  """
  @spec system_to_mermaid(module(), [module()], keyword()) :: String.t()
  def system_to_mermaid(domain, contracts, opts \\ []),
    do: EhOsContract.Graph.System.to_mermaid(domain, contracts, opts)

  @doc """
  `query`, over events bound as `:event`, narrowed to the period `opts` names with
  `:since` and `:until`, as every reader of the log narrows it.
  """
  @spec bounded(Ecto.Query.t(), keyword()) :: Ecto.Query.t()
  def bounded(query, opts),
    do: query |> maybe_since(opts[:since]) |> maybe_until(opts[:until])

  @spec maybe_since(Ecto.Query.t(), DateTime.t() | nil) :: Ecto.Query.t()
  defp maybe_since(query, nil), do: query
  defp maybe_since(query, since), do: where(query, [event: e], e.occurred_at >= ^since)

  # The evidence report is **for a period**, so it needs both bounds. `since`
  # alone means "from X until now", so a July report regenerated in September
  # would include August — and a proof that changes when reprinted is not a proof.
  @spec maybe_until(Ecto.Query.t(), DateTime.t() | nil) :: Ecto.Query.t()
  defp maybe_until(query, nil), do: query
  defp maybe_until(query, until), do: where(query, [event: e], e.occurred_at <= ^until)
end
