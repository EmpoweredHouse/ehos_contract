defmodule EhOsContract.Graph.System do
  @moduledoc """
  A domain's v2 contracts as one graph (plan EG2): each context a group of the
  contracts in it, and between contracts what one consumes from another — an arrow
  from the contract that declares the events to the one that consumes them, carrying
  their names.

  What crosses to another application goes through a publication, drawn as a node
  of its own and named as it is on the wire: a contract's `publish` is an arrow to
  it, and a `consumes` of a published name an arrow from it. A contract that
  publishes a name and one that consumes it meet on the same node.

  `overlay: true` lays the log over it. On each contract with a process, the runs of
  that process. On each edge between two contracts, how many of the consumed events
  the log holds, and what waits or fails at the consumer's steps that start from
  them (`EhOsContract.Paths`): an edge that carries events nobody has handled yet
  says so. A publication carries no count: what another application did with it is
  not in this log. `since:` and `until:` bound the log, as in the report.

  Navigation inside a contract stays per process (ADR §9): this is the map between
  contracts, and each contract's own picture is `EhOsContract.Graph.Contract`'s.
  """

  import Ecto.Query

  alias EhOsContract.{Event, Model, Paths}
  alias EhOsContract.Graph.Mermaid

  @doc """
  The system of `domain`, a domain module or its model, over `contracts`, the v2
  contract modules or models: those naming another domain are left out.
  """
  @spec build(module() | map(), [module() | map()], keyword()) :: Mermaid.graph()
  def build(domain, contracts, opts \\ []) do
    domain = Model.fetch(domain)
    overlay? = Keyword.get(opts, :overlay, false)

    models =
      contracts
      |> Enum.map(&Model.fetch/1)
      |> Enum.filter(&(&1.domain == domain.module))

    here = MapSet.new(models, & &1.module)

    # Each consumer's steps with the log, read once however many edges reach it.
    observed =
      if overlay?, do: Map.new(models, &{&1.module, Paths.observe(&1, opts)}), else: %{}

    contract_nodes =
      for m <- models do
        node = Mermaid.graph_node(:contract, slug(m.module), contract_label(m))
        if overlay? and m.process, do: Map.put(node, :runs, runs(m, opts)), else: node
      end

    between =
      for m <- models,
          %{kind: :contract, from: from} = c <- m.consumes,
          MapSet.member?(here, from) do
        sibling = Enum.find(models, &(&1.module == from))
        consumed(sibling, m, c, observed, opts)
      end

    {topic_nodes, topic_edges} = publications(models)

    groups =
      for context <- domain.contexts,
          members = for(m <- models, m.context == context.name, do: m),
          members != [] do
        %{
          id: Mermaid.id(:context, context.name),
          label: "#{context.label} · context",
          nodes: Enum.map(members, &Mermaid.id(:contract, slug(&1.module)))
        }
      end

    %{
      nodes: Enum.map(contract_nodes, &with_runs/1) ++ topic_nodes,
      edges: between ++ topic_edges,
      groups: groups
    }
  end

  @doc "The system of `domain` as a Mermaid flowchart; arguments as `build/3`."
  @spec to_mermaid(module() | map(), [module() | map()], keyword()) :: String.t()
  def to_mermaid(domain, contracts, opts \\ []),
    do: domain |> build(contracts, opts) |> Mermaid.render("LR")

  # --- nodes ---------------------------------------------------------------------------

  defp contract_label(%{module: module, process: nil}), do: short(module)
  defp contract_label(%{module: module, process: p}), do: "#{short(module)} · #{p.label}"

  defp short(module), do: module |> Module.split() |> List.last()

  # A module as a node id: every segment, so two contexts' `Settlement` stay apart.
  defp slug(module),
    do: module |> Module.split() |> Enum.map_join("_", &Macro.underscore/1)

  defp with_runs(%{runs: runs} = node),
    do: node |> Map.delete(:runs) |> Map.update!(:label, &"#{&1} (#{Mermaid.runs(runs)})")

  defp with_runs(node), do: node

  # A name on the wire as a node id; the name itself is its label.
  defp topic_id(name), do: "publication_" <> String.replace(name, ~r/[^A-Za-z0-9_]/u, "_")

  # --- edges ---------------------------------------------------------------------------

  defp consumed(sibling, consumer, c, observed, opts) do
    label = Enum.map_join(c.events, ", ", &Atom.to_string/1)

    label =
      case Map.fetch(observed, consumer.module) do
        {:ok, steps} -> Enum.join([label | traffic(sibling, c, steps, opts)], " · ")
        :error -> label
      end

    Mermaid.edge(
      Mermaid.id(:contract, slug(sibling.module)),
      Mermaid.id(:contract, slug(consumer.module)),
      label: label
    )
  end

  # Each `publish` into its publication, and each publication a `consumes` reads.
  defp publications(models) do
    out =
      for m <- models, p <- m.publishes do
        {p.as,
         Mermaid.edge(Mermaid.id(:contract, slug(m.module)), topic_id(p.as),
           line: :dotted,
           label: "publishes #{p.from}"
         )}
      end

    into =
      for m <- models, %{kind: :published, from: name} = c <- m.consumes do
        {name,
         Mermaid.edge(topic_id(name), Mermaid.id(:contract, slug(m.module)),
           line: :dotted,
           label: "as #{c.as}"
         )}
      end

    nodes =
      for name <- (out ++ into) |> Enum.map(&elem(&1, 0)) |> Enum.uniq(),
          do: %{id: topic_id(name), kind: :publication, name: name, label: name}

    {nodes, Enum.map(out ++ into, &elem(&1, 1))}
  end

  # --- the log -------------------------------------------------------------------------

  defp runs(model, opts), do: Paths.runs_of(model, Atom.to_string(model.process.name), opts)

  # How many of the consumed events the log holds, and what waits or fails at the
  # consumer's steps that start from them — under the names they have there.
  defp traffic(sibling, c, steps, opts) do
    types = for e <- sibling.events, e.name in c.events, do: e.type
    local = MapSet.new(c.events, &Map.get(c.renames, &1, &1))

    count =
      from(e in Event, as: :event, where: e.type in ^types, select: count(e.id))
      |> EhOsContract.Graph.bounded(opts)
      |> repo().one()

    steps =
      for step <- steps,
          step.from.kind == :event,
          MapSet.member?(local, step.from.name),
          do: step

    waiting = steps |> Enum.map(&Enum.sum(Map.values(&1.in_flight))) |> Enum.sum()

    failing? =
      Enum.any?(steps, fn %{failing: f} ->
        f.commands > 0 or f.effects > 0 or f.subscription != nil
      end)

    ["#{count} events", waiting > 0 && "#{waiting} waiting", failing? && "failing"]
    |> Enum.filter(& &1)
  end

  defp repo, do: Application.fetch_env!(:eh_os_contract, :repo)
end
