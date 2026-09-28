defmodule EhOsContract.Graph.Mermaid do
  @moduledoc """
  Draws a graph built as data — nodes, edges and groups — as a Mermaid flowchart
  (plan EG). The v2 graphs are built first and drawn here, so a renderer other than
  Mermaid needs only the data.

  A node is `%{id, kind, label}` and may carry `counts: {occurrences, runs}`; its
  kind gives its shape and its class, in the Event Storming colours. An edge is
  `%{from, to, line, head, label}`: `line` is `:solid` or `:dotted`, and `head: false`
  is a relation that is not a delivery, drawn without an arrowhead. A group is
  `%{id, label, nodes}`, drawn as a subgraph holding those nodes.

  Labels are the client's and may hold anything they wrote; the one character that
  breaks a quoted Mermaid label is the double quote.
  """

  @typedoc "A node of a graph built as data."
  @type graph_node :: %{
          required(:id) => String.t(),
          required(:kind) => atom(),
          required(:label) => String.t(),
          optional(:counts) => {non_neg_integer(), non_neg_integer()} | nil
        }

  @typedoc "An edge of a graph built as data."
  @type edge :: %{
          from: String.t(),
          to: String.t(),
          line: :solid | :dotted,
          head: boolean(),
          label: String.t() | nil
        }

  @typedoc "A group of nodes, drawn as a subgraph."
  @type group :: %{id: String.t(), label: String.t(), nodes: [String.t()]}

  @typedoc "A graph built as data."
  @type graph :: %{
          required(:nodes) => [graph_node()],
          required(:edges) => [edge()],
          optional(:groups) => [group()]
        }

  # The Event Storming palette: commands blue, events orange, policies lilac, process
  # managers purple, effects pink as the outside world, timers grey, actors and the
  # state they decide on yellow, the read side green; an invariant is a rule, in red;
  # an external system grey and dashed, as the declared shape draws it.
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
    external: "fill:#eceff1,stroke:#546e7a,color:#000,stroke-dasharray: 4 3"
  ]

  @doc """
  `graph` as a Mermaid flowchart laid out in `direction` (`"LR"` or `"TB"`): the
  groups with their nodes, then the nodes in no group, the edges, and a class for
  every kind drawn.
  """
  @spec render(graph(), String.t()) :: String.t()
  def render(graph, direction \\ "LR") do
    groups = Map.get(graph, :groups, [])
    grouped = MapSet.new(Enum.flat_map(groups, & &1.nodes))
    by_id = Map.new(graph.nodes, &{&1.id, &1})

    group_lines =
      for group <- groups do
        [~s(    subgraph #{group.id}["#{escape(group.label)}"])] ++
          for(id <- group.nodes, do: "        " <> node_line(Map.fetch!(by_id, id))) ++
          ["    end"]
      end

    free = for node <- graph.nodes, not MapSet.member?(grouped, node.id), do: node
    kinds = graph.nodes |> Enum.map(& &1.kind) |> Enum.uniq()

    Enum.join(
      ["flowchart #{direction}"] ++
        List.flatten(group_lines) ++
        Enum.map(free, &("    " <> node_line(&1))) ++
        Enum.map(graph.edges, &("    " <> edge_line(&1))) ++
        for({kind, style} <- @classes, kind in kinds, do: "    classDef #{kind} #{style}"),
      "\n"
    )
  end

  @doc "A node's line: its id, its shape around its label and counts, and its class."
  @spec node_line(graph_node()) :: String.t()
  def node_line(node) do
    {open, close} = shape(node.kind)
    text = escape(node.label) <> count_suffix(Map.get(node, :counts))
    ~s(#{node.id}#{open}"#{text}"#{close}:::#{node.kind})
  end

  @doc "An edge's line, in the syntax its line, head and label call for."
  @spec edge_line(edge()) :: String.t()
  def edge_line(%{line: :solid, head: true} = e), do: "#{e.from} -->#{pipes(e.label)} #{e.to}"
  def edge_line(%{line: :dotted, head: true} = e), do: "#{e.from} -.->#{pipes(e.label)} #{e.to}"
  def edge_line(%{line: :solid, head: false} = e), do: "#{e.from} ---#{pipes(e.label)} #{e.to}"
  def edge_line(%{line: :dotted, head: false, label: nil} = e), do: "#{e.from} -.- #{e.to}"
  def edge_line(%{line: :dotted, head: false} = e), do: "#{e.from} -. #{e.label} .- #{e.to}"

  @doc "An edge between two node ids."
  @spec edge(String.t(), String.t(), keyword()) :: edge()
  def edge(from, to, opts \\ []) do
    %{
      from: from,
      to: to,
      line: Keyword.get(opts, :line, :solid),
      head: Keyword.get(opts, :head, true),
      label: Keyword.get(opts, :label)
    }
  end

  @doc "A label with the double quotes that would end it replaced."
  @spec escape(String.t()) :: String.t()
  def escape(label), do: String.replace(label, ~s("), "'")

  @doc "`1 run`, `3 runs`."
  @spec runs(non_neg_integer()) :: String.t()
  def runs(1), do: "1 run"
  def runs(n), do: "#{n} runs"

  defp pipes(nil), do: ""
  defp pipes(""), do: ""
  defp pipes(label), do: "|#{label}|"

  defp count_suffix(nil), do: ""
  defp count_suffix({count, instances}), do: " (#{count}x, #{runs(instances)})"

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
  defp shape(:external), do: {"[(", ")]"}
end
