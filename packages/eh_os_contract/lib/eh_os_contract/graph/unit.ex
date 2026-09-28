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

  alias EhOsContract.Graph.Mermaid
  alias EhOsContract.Model

  @doc """
  Unit `name` of `contract` as data: `EhOsContract.Graph.Mermaid.graph()`. Raises
  when the contract has no such unit.
  """
  @spec build(module() | map(), atom()) :: Mermaid.graph()
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

    state = state_node(unit)

    {built_from, from_elsewhere} = built_from(model, unit, events)

    nodes =
      [state] ++
        Enum.map(commands, &graph_node(:command, &1.name, &1.label)) ++
        Enum.map(events, &graph_node(:event, &1.name, &1.label)) ++
        from_elsewhere ++
        Enum.map(unit.invariants, &graph_node(:invariant, &1.name, &1.label)) ++
        for(c <- commands, k <- Map.get(c, :constraints, []), do: constraint_node(c, k))

    emits =
      for c <- commands, event <- c.emits do
        n = Enum.count(scenarios, &(&1.trigger.name == c.name and expects?(&1, event)))
        Mermaid.edge(id(:command, c.name), id(:event, event), label: scenarios(n))
      end

    refuses =
      for c <- commands, rule <- c.rejects do
        n = Enum.count(scenarios, &(&1.trigger.name == c.name and &1.rejected == rule))

        Mermaid.edge(id(:command, c.name), refused_on(unit, c, rule),
          line: :dotted,
          label: Enum.join(Enum.reject(["may be refused", scenarios(n)], &is_nil/1), " · ")
        )
      end

    %{nodes: nodes, edges: emits ++ refuses ++ built_from}
  end

  @doc "Unit `name` of `contract` as a Mermaid flowchart."
  @spec to_mermaid(module() | map(), atom()) :: String.t()
  def to_mermaid(contract, name), do: contract |> build(name) |> Mermaid.render("LR")

  # A command may be refused on an invariant of its unit or on a constraint of its own
  # (plan EL2), and a constraint is the command's: two commands may name theirs alike.
  defp refused_on(unit, command, rule) do
    if Enum.any?(unit.invariants, &(&1.name == rule)),
      do: id(:invariant, rule),
      else: constraint_id(command, rule)
  end

  defp constraint_node(command, constraint) do
    %{
      id: constraint_id(command, constraint.name),
      kind: :constraint,
      name: constraint.name,
      label: constraint.label
    }
  end

  defp constraint_id(command, name), do: "constraint_#{command.name}_#{name}"

  # The card: the unit's label and kind, then a line per field of its state.
  defp state_node(unit) do
    lines =
      for field <- unit.state.fields do
        notes =
          [field.name in unit.identity && "identity", field.optional && "optional"]
          |> Enum.filter(& &1)

        suffix = if notes == [], do: "", else: " · " <> Enum.join(notes, ", ")
        "#{field.name}: #{type(field.type)}#{suffix}"
      end

    label = ["#{unit.label} · #{unit.kind}" | lines]
    %{id: id(:state, unit.name), kind: :state, name: unit.name, label: label}
  end

  # What the state is built from: an aggregate's own events, or the events a dynamic
  # consistency boundary consults — nodes of their own when they are not the unit's.
  defp built_from(model, %{kind: :dcb} = unit, events) do
    own = MapSet.new(events, & &1.name)

    edges =
      for c <- unit.consults do
        Mermaid.edge(id(:event, c.event), id(:state, unit.name),
          line: :dotted,
          label: consulted(c)
        )
      end

    elsewhere =
      for c <- unit.consults, not MapSet.member?(own, c.event), uniq: true do
        label =
          case Model.declaring(model, c.event) do
            {_contract, e} -> e.label
            nil -> nil
          end

        graph_node(:event, c.event, label)
      end

    {edges, elsewhere}
  end

  defp built_from(_model, unit, events) do
    edges =
      for e <- events,
          do: Mermaid.edge(id(:event, e.name), id(:state, unit.name), line: :dotted)

    {edges, []}
  end

  defp consulted(%{match: [_ | _] = match}), do: "consulted by #{Enum.join(match, ", ")}"
  defp consulted(_where_in_prose), do: "consulted, where stated in prose"

  defp expects?(scenario, event), do: Enum.any?(scenario.expect, &(&1.event == event))

  defp scenarios(0), do: nil
  defp scenarios(1), do: "1 scenario"
  defp scenarios(n), do: "#{n} scenarios"

  defp type({:list, inner}), do: "list of #{type(inner)}"
  defp type({:enum, values}), do: "one of #{Enum.map_join(values, ", ", &enum_value/1)}"
  defp type(type) when is_atom(type), do: Atom.to_string(type)
  defp type(type), do: inspect(type)

  defp enum_value({value, _label}), do: value
  defp enum_value(value), do: value

  defp graph_node(kind, name, label), do: Mermaid.graph_node(kind, name, label)
  defp id(kind, name), do: Mermaid.id(kind, name)
end
