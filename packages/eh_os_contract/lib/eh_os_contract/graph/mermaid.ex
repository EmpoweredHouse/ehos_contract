defmodule EhOsContract.Graph.Mermaid do
  @moduledoc """
  Draws a graph built as data (`EhOsContract.Graph.Document`) as a Mermaid flowchart
  (plan EG). The graphs are built first and drawn here, so a renderer other than
  Mermaid needs only the data.

  Everything about the look is here, and nothing about it is in the data (plan E13a):
  a node's kind gives its shape and its class, in the Event Storming colours; an
  edge's relation gives its line, its arrowhead and the words on it; and the ids are
  Mermaid's own, made from each node's kind and name as they always were — the
  document's ids are not Mermaid identifiers. This module goes in E13b, with the
  renderer that replaces it.

  Labels are the client's and may hold anything they wrote; what breaks a quoted
  Mermaid label is a double quote and a line break (`escape/1`).
  """

  alias EhOsContract.Graph.Document

  # The Event Storming palette: commands blue, events orange, policies lilac, process
  # managers purple, effects pink as the outside world, timers grey, actors and the
  # state they decide on yellow, the read side green; an invariant is a rule, in red,
  # and a command's constraint a paler one;
  # an external system grey and dashed, as the declared shape draws it. On the maps
  # between them, a context is blue, a contract grey, and a publication on the wire
  # teal. An aggregate's statuses are its state's yellow, an end drawn heavier, and
  # where a new aggregate starts is a black dot.
  @classes [
    command: "fill:#a7c7e7,stroke:#3b6ea5,color:#000",
    event: "fill:#ffb86c,stroke:#c46a00,color:#000",
    policy: "fill:#d7b8f3,stroke:#7b4fa8,color:#000",
    process_manager: "fill:#b39ddb,stroke:#5e35b1,color:#000",
    effect: "fill:#f8bbd0,stroke:#ad1457,color:#000",
    timer: "fill:#e0e0e0,stroke:#757575,color:#000",
    actor: "fill:#fff59d,stroke:#f9a825,color:#000",
    state: "fill:#fff9c4,stroke:#f9a825,color:#000",
    read_model: "fill:#c5e1a5,stroke:#558b2f,color:#000",
    query: "fill:#dcedc8,stroke:#689f38,color:#000",
    invariant: "fill:#ffcdd2,stroke:#c62828,color:#000",
    constraint: "fill:#ffebee,stroke:#c62828,color:#000",
    external: "fill:#eceff1,stroke:#546e7a,color:#000,stroke-dasharray: 4 3",
    context: "fill:#e3f2fd,stroke:#1565c0,color:#000",
    contract: "fill:#f5f5f5,stroke:#424242,color:#000",
    publication: "fill:#e0f7fa,stroke:#00838f,color:#000",
    status: "fill:#fff9c4,stroke:#f9a825,color:#000",
    status_end: "fill:#fff9c4,stroke:#f9a825,color:#000,stroke-width:3px",
    start: "fill:#212121,stroke:#212121,color:#fff"
  ]

  @doc """
  `graph` as a Mermaid flowchart laid out in `direction` (`"LR"` or `"TB"`): the
  groups with their nodes, then the nodes in no group, the edges, and a class for
  every kind drawn.
  """
  @spec render(Document.graph(), String.t()) :: String.t()
  def render(graph, direction \\ "LR") do
    groups = Map.get(graph, :groups, [])
    grouped = MapSet.new(Enum.flat_map(groups, & &1.nodes))
    by_id = Map.new(graph.nodes, &{&1.id, &1})
    ids = mermaid_ids(graph.nodes)

    group_lines =
      for group <- groups do
        [~s(    subgraph #{group.kind}_#{group.name}["#{escape(group_label(group))}"])] ++
          for(id <- group.nodes, do: "        " <> node_line(Map.fetch!(by_id, id), ids)) ++
          ["    end"]
      end

    free = for node <- graph.nodes, not MapSet.member?(grouped, node.id), do: node
    classes = graph.nodes |> Enum.map(&class/1) |> Enum.uniq()

    Enum.join(
      ["flowchart #{direction}"] ++
        List.flatten(group_lines) ++
        Enum.map(free, &("    " <> node_line(&1, ids))) ++
        Enum.map(graph.edges, &("    " <> edge_line(&1, ids))) ++
        for({class, style} <- @classes, class in classes, do: "    classDef #{class} #{style}"),
      "\n"
    )
  end

  @doc """
  A label with what would end it or be read as markup replaced: a double quote, which
  ends a quoted Mermaid label; a line break, which ends the line the label is on — and
  in a Markdown page, a line of three backticks after it would end the diagram's
  block; and `<`, `>` and `#`, which Mermaid would read as a tag or an entity, so
  `a<b` and `Faktura #12;` print as written. All four become Mermaid's own entity
  codes, which it draws as the characters they stand for — a quote the client wrote
  stays a quote (plan LC4b, CodeRabbit on #125: it used to become an apostrophe).
  """
  @spec escape(String.t()) :: String.t()
  def escape(label) do
    label
    |> String.replace("#", "#35;")
    |> String.replace("<", "#lt;")
    |> String.replace(">", "#gt;")
    |> String.replace(~s("), "#quot;")
    |> String.replace(["\r\n", "\r", "\n"], " ")
  end

  # --- ids -----------------------------------------------------------------------------

  # A Mermaid id for each node, in their order: its kind and name, or, when an earlier
  # node took that already, the first of `base_2`, `base_3`, … still free. Ids made
  # from a client's names can meet — `visit.settled` and `visit_settled` both read
  # `visit_settled` once a module is slugged — and two nodes of one id are one node to
  # Mermaid.
  defp mermaid_ids(nodes) do
    {pairs, _taken} =
      Enum.map_reduce(nodes, MapSet.new(), fn node, taken ->
        base = base_id(node)

        id =
          Stream.iterate(2, &(&1 + 1))
          |> Stream.map(&"#{base}_#{&1}")
          |> then(&Stream.concat([base], &1))
          |> Enum.find(&(not MapSet.member?(taken, &1)))

        {{node.id, id}, MapSet.put(taken, id)}
      end)

    Map.new(pairs)
  end

  # A command's constraint is the command's: two commands may name theirs alike.
  defp base_id(%{kind: :constraint} = node), do: "constraint_#{node.command}_#{node.name}"
  defp base_id(%{kind: :start}), do: "start"

  # A module: every segment, so two contexts' `Settlement` stay apart.
  defp base_id(%{kind: :contract, name: module}),
    do: "contract_" <> (module |> Module.split() |> Enum.map_join("_", &Macro.underscore/1))

  # A name on the wire; the name itself is its label.
  defp base_id(%{kind: :publication, name: name}),
    do: "publication_" <> String.replace(name, ~r/[^A-Za-z0-9_]/u, "_")

  defp base_id(%{kind: kind, name: name}), do: "#{kind}_#{name}"

  # --- nodes ---------------------------------------------------------------------------

  # A node's line: its id, its shape around its text, and its class.
  defp node_line(node, ids) do
    class = class(node)
    {open, close} = shape(class)
    ~s(#{Map.fetch!(ids, node.id)}#{open}"#{text(node)}"#{close}:::#{class})
  end

  # An end of a lifecycle is a status drawn heavier.
  defp class(%{kind: :status, final: true}), do: :status_end
  defp class(%{kind: kind}), do: kind

  # The card: the unit's label and kind, then a line per field of its state, each
  # escaped — the break is the renderer's, not a character of the client's.
  defp text(%{kind: :state} = node) do
    lines =
      for field <- node.fields do
        notes =
          [field.identity && "identity", field.optional && "optional"] |> Enum.filter(& &1)

        suffix = if notes == [], do: "", else: " · " <> Enum.join(notes, ", ")
        "#{field.name}: #{type(field.type)}#{suffix}"
      end

    Enum.map_join(["#{node.label} · #{node.unit_kind}" | lines], "<br/>", &escape/1)
  end

  defp text(%{kind: :start}), do: " "

  defp text(%{kind: :contract} = node) do
    label = Enum.join(Enum.reject([node.label, Map.get(node, :process)], &is_nil/1), " · ")
    escape(label <> runs_suffix(Map.get(node, :runs)))
  end

  defp text(node), do: escape(node.label) <> count_suffix(Map.get(node, :counts))

  defp group_label(%{kind: :unit} = group), do: "#{group.label} · #{group.unit_kind}"
  defp group_label(%{kind: :subdomain} = group), do: "#{group.label} · #{group.type}"
  defp group_label(%{kind: :context} = group), do: "#{group.label} · context"

  defp runs_suffix(nil), do: ""
  defp runs_suffix(runs), do: " (#{runs(runs)})"

  defp count_suffix(nil), do: ""
  defp count_suffix(count), do: " (#{count}x)"

  defp runs(1), do: "1 run"
  defp runs(n), do: "#{n} runs"

  defp type({:list, inner}), do: "list of #{type(inner)}"
  defp type({:enum, values}), do: "one of #{Enum.map_join(values, ", ", &enum_value/1)}"
  defp type(type) when is_atom(type), do: Atom.to_string(type)
  defp type(type), do: inspect(type)

  defp enum_value({value, _label}), do: value
  defp enum_value(value), do: value

  defp shape(:command), do: {"[", "]"}
  defp shape(:event), do: {"[", "]"}
  defp shape(:policy), do: {"{{", "}}"}
  defp shape(:process_manager), do: {"[[", "]]"}
  defp shape(:effect), do: {">", "]"}
  defp shape(:timer), do: {"([", "])"}
  defp shape(:actor), do: {"(", ")"}
  defp shape(:state), do: {"[", "]"}
  defp shape(:read_model), do: {"[", "]"}
  defp shape(:query), do: {"[/", "/]"}
  defp shape(:invariant), do: {"{", "}"}
  defp shape(:constraint), do: {"{", "}"}
  defp shape(:external), do: {"[(", ")]"}
  defp shape(:context), do: {"(", ")"}
  defp shape(:contract), do: {"[", "]"}
  defp shape(:publication), do: {"[/", "\\]"}
  defp shape(:status), do: {"(", ")"}
  defp shape(:status_end), do: {"([", "])"}
  defp shape(:start), do: {"((", "))"}

  # --- edges ---------------------------------------------------------------------------

  # An edge's line, in the syntax its look calls for.
  defp edge_line(edge, ids) do
    {line, head, label} = look(edge)
    from = Map.fetch!(ids, edge.from)
    to = Map.fetch!(ids, edge.to)

    case {line, head, label} do
      {:solid, true, _} -> "#{from} -->#{pipes(label)} #{to}"
      {:dotted, true, _} -> "#{from} -.->#{pipes(label)} #{to}"
      {:solid, false, _} -> "#{from} ---#{pipes(label)} #{to}"
      {:dotted, false, nil} -> "#{from} -.- #{to}"
      {:dotted, false, _} -> "#{from} -. #{label} .- #{to}"
    end
  end

  @symmetric [:partnership, :shared_kernel, :separate_ways]

  # The look of each relation, the table E13b's renderer replaces: `{line, head,
  # words}`. A relation that is not a delivery — owning a timer, resting on a system,
  # being backed by one, a symmetric pattern between contexts — has no arrowhead; one
  # that is not causation, or runs after the transaction, is dotted.
  defp look(%{relation: r} = e) when r in [:emits, :handled_by, :issues, :fires, :projected_into],
    do: delivered(e, note([scenarios(e), steps(e)]))

  defp look(%{relation: :sets_timer}), do: {:dotted, false, "sets"}
  defp look(%{relation: :records}), do: {:solid, true, "records"}
  defp look(%{relation: :asks}), do: {:solid, true, nil}
  defp look(%{relation: :reads}), do: {:solid, true, "reads"}
  defp look(%{relation: :calls}), do: {:dotted, true, "calls"}
  defp look(%{relation: :depends_on}), do: {:dotted, false, nil}
  defp look(%{relation: :backed_by}), do: {:dotted, false, "backed by"}
  defp look(%{relation: :gives} = e), do: {:dotted, true, "gives #{e.field}"}

  defp look(%{relation: :refused_on} = e),
    do: {:dotted, true, note(["may be refused", scenarios(e)])}

  defp look(%{relation: :builds}), do: {:dotted, true, nil}

  defp look(%{relation: :consulted_by, match: match}),
    do: {:dotted, true, "consulted by #{Enum.join(match, ", ")}"}

  defp look(%{relation: :consulted_by}), do: {:dotted, true, "consulted, where stated in prose"}

  defp look(%{relation: :transition} = e),
    do: {:solid, true, quoted(e.label, taken(Map.get(e, :overlay)))}

  defp look(%{relation: :undeclared} = e),
    do: {:dotted, true, quoted(e.label, "not declared, #{e.overlay.count}x")}

  defp look(%{relation: :consumed_by} = e),
    do: {:solid, true, note([Enum.map_join(e.events, ", ", &Atom.to_string/1) | traffic(e)])}

  defp look(%{relation: :publishes} = e), do: {:dotted, true, "publishes #{e.event}"}
  defp look(%{relation: :subscribed_by} = e), do: {:dotted, true, "as #{e.as}"}

  defp look(%{relation: r}) when r in @symmetric,
    do: {if(r == :separate_ways, do: :dotted, else: :solid), false, words(r)}

  defp look(%{relation: r}), do: {:solid, true, words(r)}

  # A step or a projection after the transaction is dotted and says so.
  defp delivered(%{delivery: :async}, text), do: {:dotted, true, note(["async", text])}
  defp delivered(_edge, text), do: {:solid, true, text}

  defp note(parts) do
    case Enum.reject(parts, &(&1 in [nil, false])) do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end

  defp scenarios(%{scenarios: 1}), do: "1 scenario"
  defp scenarios(%{scenarios: n}) when n > 1, do: "#{n} scenarios"
  defp scenarios(_edge), do: nil

  # The log over a step: how often it was taken, and what waits or fails there.
  defp steps(%{overlay: o}) do
    taken = if o.taken, do: "#{o.taken} taken", else: "taken unknown"
    note([taken, o.waiting > 0 && "#{o.waiting} waiting", o.failing && "failing"])
  end

  defp steps(_edge), do: nil

  # The log over an edge between two contracts: the consumed events it holds.
  defp traffic(%{overlay: o}),
    do: ["#{o.events} events", o.waiting > 0 && "#{o.waiting} waiting", o.failing && "failing"]

  defp traffic(_edge), do: []

  # How the report reads a lifecycle's arrow: taken so many times, not taken yet while
  # an aggregate still stands where it can be, or never.
  defp taken(nil), do: nil
  defp taken(%{count: n}) when n > 0, do: "#{n}x"
  defp taken(%{pending: true}), do: "not yet"
  defp taken(%{untraversed: true}), do: "never"
  defp taken(_overlay), do: "0x"

  defp quoted(label, nil), do: ~s("#{escape(label)}")
  defp quoted(label, count), do: ~s("#{escape(label)} · #{count}")

  defp words(type), do: type |> Atom.to_string() |> String.replace("_", " ")

  defp pipes(nil), do: ""
  defp pipes(""), do: ""
  defp pipes(label), do: "|#{label}|"
end
