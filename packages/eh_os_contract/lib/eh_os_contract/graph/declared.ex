defmodule EhOsContract.Graph.Declared do
  @moduledoc """
  One process's **declared shape** as a graph (plan E7c, E13a): its stages, the
  events in them, how it can end, each promise with its window, and the external
  systems its events rest on. Why this picture is worth drawing, who it is for and
  what it leaves out is `EhOsContract.Graph.declared_to_mermaid/2`'s.

  Each stage is a group, in the order the process declares them, and that order is
  the only ordering claim a contract makes: it is an edge `precedes` from one stage's
  group to the next one's, the only edges on any graph that end at a group rather
  than a node. Inside a stage the contract claims no order, so a stage's events have
  no edges between them, and a stage nothing has been assigned to is a group with no
  nodes — a finding, which a picture hiding it would be the wrong tool to find.

  An event is the contract's own or one it includes, where the `include` puts it,
  with its `stage` and whether it is `terminal`. A promise is an edge `eventually`
  from the event it starts at to the one that keeps it, with its `within` where it
  has a window, and, where it has one, an edge `or_else` to the event that keeps it
  the other way; both name the `promise`. An event's `depends_on` is an edge to the
  domain's external system.
  """

  alias EhOsContract.Graph.Document
  alias EhOsContract.Model

  @doc """
  The declared shape of process `process` of `contract` as data:
  `EhOsContract.Graph.Document.graph()`. Raises when the contract declares no such
  process.
  """
  @spec build(module() | map(), atom()) :: Document.graph()
  def build(contract, process) do
    model = Model.fetch(contract)

    case Model.process(model) do
      %{name: ^process} = declared -> shape(model, declared)
      _ -> raise ArgumentError, "#{inspect(model.module)} declares no process #{inspect(process)}"
    end
  end

  defp shape(model, process) do
    contract = model.id
    domain = domain(model.domain)
    externals = Map.new(domain.externals, &{&1.name, &1.label})

    run =
      for e <- Model.process_events(model),
          do: {e.name, e.declaration.label, e.stage, e.terminal, e.declaration.depends_on}

    events =
      for {name, label, stage, terminal, _depends_on} <- run do
        :event
        |> Document.graph_node(contract, name, label)
        |> Map.merge(%{stage: stage, terminal: terminal})
      end

    depended_on =
      for {_name, _label, _stage, _terminal, external} <- run,
          external != nil,
          uniq: true,
          do: Document.graph_node(:external, model.domain, external, externals[external])

    stage_id = &Document.id([:stage, contract, process.name, &1])
    event_id = &Document.id([:event, contract, &1])

    groups =
      for stage <- process.stages do
        %{
          id: stage_id.(stage.name),
          kind: :stage,
          name: stage.name,
          label: stage.label || to_string(stage.name),
          nodes: for(e <- events, e.stage == stage.name, do: e.id)
        }
      end

    order =
      process.stages
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> Document.edge(stage_id.(a.name), stage_id.(b.name), :precedes) end)

    promises =
      Enum.flat_map(process.promises, fn p ->
        within = p.within && %{amount: p.within.amount, unit: p.within.unit}

        [
          Document.edge(event_id.(p.from), event_id.(p.eventually), :eventually,
            promise: p.name,
            within: within
          )
        ] ++
          if p.or_else,
            do: [
              Document.edge(event_id.(p.from), event_id.(p.or_else), :or_else, promise: p.name)
            ],
            else: []
      end)

    dependencies =
      for {name, _label, _stage, _terminal, external} <- run,
          external != nil,
          do:
            Document.edge(
              event_id.(name),
              Document.id([:external, model.domain, external]),
              :depends_on
            )

    %{
      nodes: events ++ depended_on,
      edges: order ++ promises ++ dependencies,
      groups: groups
    }
  end

  # A contract may name a domain that does not exist (v2 §8): its externals are then
  # drawn by name, with nothing to label them.
  defp domain(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__eh_os_contract_model__, 0),
      do: Model.fetch(module),
      else: %{externals: []}
  end
end
