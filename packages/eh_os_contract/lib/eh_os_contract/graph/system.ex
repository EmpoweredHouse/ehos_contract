defmodule EhOsContract.Graph.System do
  @moduledoc """
  A domain's v2 contracts as one graph (plan EG2): each context a group of the
  contracts in it, and between contracts what one consumes from another — an arrow
  from the contract that declares the events to the one that consumes them, carrying
  their names.

  What crosses to another application goes through a publication, drawn as a node
  of its own and named as it is on the wire: a contract's `publish` is an arrow to
  it, and a `subscribe` to a published name an arrow from it. A contract that
  publishes a name and one that subscribes to it meet on the same node.

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
    ids = Mermaid.unique_ids(Enum.map(models, & &1.module), &("contract_" <> slug(&1)))

    edges =
      for m <- models,
          %{kind: :contract, from: from} = c <- m.consumes,
          MapSet.member?(here, from),
          do: {Enum.find(models, &(&1.module == from)), m, c}

    # Only a consumer's steps are read, once however many edges reach it, and the
    # consumed events are counted in one query for every edge.
    {observed, counts} =
      if overlay? do
        consumers = edges |> Enum.map(&elem(&1, 1)) |> Enum.uniq_by(& &1.module)
        types = for {sibling, _m, c} <- edges, e <- sibling.events, e.name in c.events, do: e.type

        {Map.new(consumers, &{&1.module, Paths.observe(&1, opts)}), counts(types, opts)}
      else
        {%{}, %{}}
      end

    contract_nodes =
      for m <- models do
        node = %{id: ids[m.module], kind: :contract, name: m.module, label: contract_label(m)}
        if overlay?, do: Map.put(node, :runs, runs(m, observed, opts)), else: node
      end

    between =
      for {sibling, m, c} <- edges,
          do: consumed(ids, sibling, m, c, Map.get(observed, m.module), counts)

    {topic_nodes, topic_edges} = publications(models, ids)

    groups =
      for context <- domain.contexts,
          members = for(m <- models, m.context == context.name, do: m),
          members != [] do
        %{
          id: Mermaid.id(:context, context.name),
          label: "#{context.label} · context",
          nodes: Enum.map(members, &ids[&1.module])
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

  # A module as a node id: every segment, so two contexts' `Settlement` stay apart;
  # `Mermaid.unique_ids/2` keeps apart the rest, `A.BC` and `A.B.C`.
  defp slug(module),
    do: module |> Module.split() |> Enum.map_join("_", &Macro.underscore/1)

  defp with_runs(%{runs: nil} = node), do: Map.delete(node, :runs)

  defp with_runs(%{runs: runs} = node),
    do: node |> Map.delete(:runs) |> Map.update!(:label, &"#{&1} (#{Mermaid.runs(runs)})")

  defp with_runs(node), do: node

  # A name on the wire as a node id, before `Mermaid.unique_ids/2`; the name itself is
  # its label.
  defp topic_id(name), do: "publication_" <> String.replace(name, ~r/[^A-Za-z0-9_]/u, "_")

  # --- edges ---------------------------------------------------------------------------

  defp consumed(ids, sibling, consumer, c, steps, counts) do
    label = Enum.map_join(c.events, ", ", &Atom.to_string/1)

    label =
      if steps,
        do: Enum.join([label | traffic(sibling, c, steps, counts)], " · "),
        else: label

    Mermaid.edge(ids[sibling.module], ids[consumer.module], label: label)
  end

  # Each `publish` into its publication, and each publication a `subscribe` reads.
  defp publications(models, ids) do
    names =
      Enum.uniq(
        for(m <- models, p <- m.publishes, do: p.as) ++
          for(m <- models, %{kind: :published, from: name} <- m.consumes, do: name)
      )

    topic = Mermaid.unique_ids(names, &topic_id/1)

    out =
      for m <- models, p <- m.publishes do
        {p.as,
         Mermaid.edge(ids[m.module], topic[p.as],
           line: :dotted,
           label: "publishes #{p.from}"
         )}
      end

    into =
      for m <- models, %{kind: :published, from: name} = c <- m.consumes do
        {name,
         Mermaid.edge(topic[name], ids[m.module],
           line: :dotted,
           label: "as #{c.as}"
         )}
      end

    nodes = for name <- names, do: %{id: topic[name], kind: :publication, name: name, label: name}

    {nodes, Enum.map(out ++ into, &elem(&1, 1))}
  end

  # --- the log -------------------------------------------------------------------------

  # A process's runs, which a consumer's observed steps already carry.
  defp runs(%{process: nil}, _observed, _opts), do: nil

  defp runs(model, observed, opts) do
    case Map.get(observed, model.module) do
      [step | _] -> step.of_runs
      _none -> Paths.runs_of(model, Atom.to_string(model.process.name), opts)
    end
  end

  # How many events of each type the log holds, in the period. `count(position)`
  # rather than of the id, so the `(type, position)` index answers it alone.
  defp counts([], _opts), do: %{}

  defp counts(types, opts) do
    from(e in Event,
      as: :event,
      where: e.type in ^Enum.uniq(types),
      group_by: e.type,
      select: {e.type, count(e.position)}
    )
    |> EhOsContract.Graph.bounded(opts)
    |> repo().all()
    |> Map.new()
  end

  # How many of the consumed events the log holds, and what waits or fails at the
  # consumer's steps that start from them — under the names they have there.
  defp traffic(sibling, c, steps, counts) do
    types = for e <- sibling.events, e.name in c.events, do: e.type
    local = MapSet.new(c.events, &Map.get(c.renames, &1, &1))
    count = types |> Enum.map(&Map.get(counts, &1, 0)) |> Enum.sum()

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
