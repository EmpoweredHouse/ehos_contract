defmodule EhOsContract.Graph.Mermaid do
  # Draws a graph built as data — nodes, edges and groups — as a Mermaid flowchart
  # (plan EG). The v2 graphs are built first and drawn here, so a renderer other than
  # Mermaid needs only the data.
  #
  # A node is `%{id, kind, label}` and may carry `counts`, its occurrences; its
  # kind gives its shape and its class, in the Event Storming colours. An edge is
  # `%{from, to, line, head, label}`: `line` is `:solid` or `:dotted`, and `head: false`
  # is a relation that is not a delivery, drawn without an arrowhead. A group is
  # `%{id, label, nodes}`, drawn as a subgraph holding those nodes.
  #
  # Labels are the client's and may hold anything they wrote; what breaks a quoted
  # Mermaid label is a double quote and a line break (`escape/1`).
  @moduledoc false

  @typedoc "A node of a graph built as data."
  @type graph_node :: %{
          required(:id) => String.t(),
          required(:kind) => atom(),
          required(:label) => String.t() | [String.t()],
          optional(:counts) => non_neg_integer() | nil
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
    text = lines(node.label) <> count_suffix(Map.get(node, :counts))
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

  # A label given as lines is drawn as them, each escaped: the break is the renderer's,
  # not a character of the client's.
  defp lines(label) when is_list(label), do: Enum.map_join(label, "<br/>", &escape/1)
  defp lines(label), do: escape(label)

  @doc "A node of `kind` named `name`, with its label or, lacking one, its name."
  @spec graph_node(atom(), atom() | String.t(), String.t() | nil) :: graph_node()
  def graph_node(kind, name, label),
    do: %{id: id(kind, name), kind: kind, name: name, label: label || to_string(name)}

  @doc "The id of the node of `kind` named `name`, which edges and groups join on."
  @spec id(atom(), atom() | String.t()) :: String.t()
  def id(kind, name), do: "#{kind}_#{name}"

  @doc """
  An id for each of `names`, in their order: `base` of the name, or, when an earlier
  name took that already, the first of `base_2`, `base_3`, … still free. Ids made
  from a client's names can meet — `visit.settled` and `visit_settled` both read
  `visit_settled` — and two nodes of one id are one node to Mermaid.
  """
  @spec unique_ids([term()], (term() -> String.t())) :: %{term() => String.t()}
  def unique_ids(names, base) do
    {pairs, _taken} =
      Enum.map_reduce(names, MapSet.new(), fn name, taken ->
        id =
          Stream.iterate(2, &(&1 + 1))
          |> Stream.map(&"#{base.(name)}_#{&1}")
          |> then(&Stream.concat([base.(name)], &1))
          |> Enum.find(&(not MapSet.member?(taken, &1)))

        {{name, id}, MapSet.put(taken, id)}
      end)

    Map.new(pairs)
  end

  @doc "`1 run`, `3 runs`."
  @spec runs(non_neg_integer()) :: String.t()
  def runs(1), do: "1 run"
  def runs(n), do: "#{n} runs"

  defp pipes(nil), do: ""
  defp pipes(""), do: ""
  defp pipes(label), do: "|#{label}|"

  defp count_suffix(nil), do: ""
  defp count_suffix(count), do: " (#{count}x)"

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
end
