defmodule EhOsContract.Graph.Unit do
  @moduledoc """
  One unit of a v2 contract as a graph (plan EG1): its state, its commands and the
  events they emit, its invariants and its commands' constraints, and how many
  scenarios pin each of those paths.

  The state is a card listing its fields. An aggregate's state is built from its own
  events, so each event points at it; a dynamic consistency boundary decides over
  the events it consults instead, its own among them only where it consults them,
  so those point at it, with the fields they are matched by. An invariant is a rule
  hanging off each command it may refuse; a command's constraint hangs off that
  command alone.

  **Scenarios are counted, not drawn.** A scenario of the unit whose command is
  expected to emit an event counts on that edge; one refused on an invariant counts
  on the command's edge to it. So a path no scenario pins is the edge with no count
  — which is what somebody reading the unit before it is built can ask about. The
  scenarios themselves, with their data, are on the unit's page.
  """

  alias EhOsContract.Graph.{Document, Mermaid}
  alias EhOsContract.Model

  @doc """
  Unit `name` of `contract` as data: `EhOsContract.Graph.Document.graph()`. Raises
  when the contract has no such unit.
  """
  @spec build(module() | map(), atom()) :: Document.graph()
  def build(contract, name) do
    model = Model.fetch(contract)

    unit =
      Enum.find(model.units, &(&1.name == name)) ||
        raise ArgumentError,
              "#{inspect(model.module)} has no unit #{inspect(name)}; " <>
                "it has #{inspect(Enum.map(model.units, & &1.name))}"

    commands = for c <- model.commands, c.unit == name, do: c
    events = for e <- model.events, e.unit == name, do: e

    scenarios =
      for s <- model.scenarios,
          s.target == %{kind: unit.kind, name: name},
          s.trigger.kind == :command,
          do: s

    contract = model.module
    state = state_node(contract, unit)

    {built_from, from_elsewhere} = built_from(model, unit, events)

    nodes =
      [state] ++
        Enum.map(commands, &Document.graph_node(:command, contract, &1.name, &1.label)) ++
        Enum.map(events, &Document.graph_node(:event, contract, &1.name, &1.label)) ++
        from_elsewhere ++
        Enum.map(unit.invariants, &invariant_node(contract, unit, &1)) ++
        for(
          cmd <- commands,
          k <- Map.get(cmd, :constraints, []),
          do: constraint_node(contract, cmd, k)
        )

    emits =
      for cmd <- commands, event <- cmd.emits do
        n = Enum.count(scenarios, &(&1.trigger.name == cmd.name and expects?(&1, event)))

        Document.edge(id(contract, :command, cmd.name), id(contract, :event, event), :emits,
          scenarios: scenarios(n)
        )
      end

    refuses =
      for cmd <- commands, rule <- cmd.rejects do
        n = Enum.count(scenarios, &(&1.trigger.name == cmd.name and &1.rejected == rule))

        Document.edge(
          id(contract, :command, cmd.name),
          refused_on(contract, unit, cmd, rule),
          :refused_on,
          scenarios: scenarios(n)
        )
      end

    %{nodes: nodes, edges: emits ++ refuses ++ built_from}
  end

  @doc "Unit `name` of `contract` as a Mermaid flowchart."
  @spec to_mermaid(module() | map(), atom()) :: String.t()
  def to_mermaid(contract, name), do: contract |> build(name) |> Mermaid.render("LR")

  # A command may be refused on an invariant of its unit or on a constraint of its own
  # (plan EL2), and a constraint is the command's: two commands may name theirs alike.
  # An invariant is the unit's: two units may name theirs alike.
  defp refused_on(contract, unit, command, rule) do
    if Enum.any?(unit.invariants, &(&1.name == rule)),
      do: Document.id([:invariant, contract, unit.name, rule]),
      else: Document.id([:constraint, contract, command.name, rule])
  end

  defp invariant_node(contract, unit, invariant) do
    %{
      id: Document.id([:invariant, contract, unit.name, invariant.name]),
      kind: :invariant,
      name: invariant.name,
      label: invariant.label || to_string(invariant.name)
    }
  end

  defp constraint_node(contract, command, constraint) do
    %{
      id: Document.id([:constraint, contract, command.name, constraint.name]),
      kind: :constraint,
      name: constraint.name,
      label: constraint.label,
      command: command.name
    }
  end

  # The card: the unit's label and kind, and its state's fields.
  defp state_node(contract, unit) do
    fields =
      for field <- unit.state.fields do
        %{
          name: field.name,
          type: field.type,
          identity: field.name in unit.identity,
          optional: field.optional
        }
      end

    %{
      id: id(contract, :state, unit.name),
      kind: :state,
      name: unit.name,
      label: unit.label,
      unit_kind: unit.kind,
      fields: fields
    }
  end

  # What the state is built from: an aggregate's own events, or the events a dynamic
  # consistency boundary consults — nodes of their own when they are not the unit's.
  defp built_from(model, %{kind: :dcb} = unit, events) do
    own = MapSet.new(events, & &1.name)
    contract = model.module

    edges =
      for c <- unit.consults do
        Document.edge(
          id(contract, :event, c.event),
          id(contract, :state, unit.name),
          :consulted_by,
          match: match(c)
        )
      end

    elsewhere =
      for c <- unit.consults, not MapSet.member?(own, c.event), uniq: true do
        label =
          case Model.declaring(model, c.event) do
            {_contract, e} -> e.label
            nil -> nil
          end

        Document.graph_node(:event, contract, c.event, label)
      end

    {edges, elsewhere}
  end

  defp built_from(model, unit, events) do
    edges =
      for e <- events,
          do:
            Document.edge(
              id(model.module, :event, e.name),
              id(model.module, :state, unit.name),
              :builds
            )

    {edges, []}
  end

  # The fields a consulted event is matched by, or none where `where` says it in prose.
  defp match(%{match: [_ | _] = match}), do: match
  defp match(_where_in_prose), do: nil

  defp expects?(scenario, event), do: Enum.any?(scenario.expect, &(&1.event == event))

  defp scenarios(0), do: nil
  defp scenarios(n), do: n

  defp id(contract, kind, name), do: Document.id([kind, contract, name])
end
