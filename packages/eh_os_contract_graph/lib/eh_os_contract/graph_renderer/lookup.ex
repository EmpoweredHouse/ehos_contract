defmodule EhOsContract.GraphRenderer.Lookup do
  # The joins a panel makes over a `graph.v1` document: a node by its id, the relations
  # into and out of it, the nodes whose owner field names it, and the scenarios about it
  # or covering one of its relations.
  #
  # Each is a join on ids and nothing more (plan E13, decision 2): who may issue a command
  # is the `may_issue` relations into it, what a reaction issues the relations out of it,
  # which scenarios pin an arrow those whose `covers` names it. Whatever takes the
  # DSL's meaning the engine has already computed into the document.
  #
  # A relation and a scenario come back as the document has them, with the type of their
  # group under `"type"`, since the document keys each group by it.
  @moduledoc false

  defstruct nodes: %{},
            kinds: %{},
            by_kind: %{},
            by_type: %{},
            into: %{},
            out: %{},
            covering: %{},
            about: %{}

  @type t :: %__MODULE__{}

  @doc "The joins of `document`, a `graph.v1` document with string keys."
  @spec new(map()) :: t()
  def new(document) do
    by_kind = Map.new(document["nodes"] || %{}, fn {kind, group} -> {kind, group} end)

    relations =
      for {type, group} <- document["relations"] || %{},
          relation <- group,
          do: Map.put(relation, "type", type)

    scenarios =
      for {type, group} <- document["scenarios"] || %{},
          scenario <- group,
          do: Map.put(scenario, "type", type)

    %__MODULE__{
      nodes: for({_kind, group} <- by_kind, node <- group, into: %{}, do: {node["id"], node}),
      kinds: for({kind, group} <- by_kind, node <- group, into: %{}, do: {node["id"], kind}),
      by_kind: by_kind,
      by_type: Enum.group_by(relations, & &1["type"]),
      into: Enum.group_by(relations, & &1["to"]),
      out: Enum.group_by(relations, & &1["from"]),
      covering:
        Enum.reduce(Enum.reverse(scenarios), %{}, fn scenario, acc ->
          Enum.reduce(
            scenario["covers"] || [],
            acc,
            &Map.update(&2, &1, [scenario], fn s -> [scenario | s] end)
          )
        end),
      about: Enum.group_by(scenarios, & &1["target"])
    }
  end

  @doc "The node `id` names, or nil."
  @spec node(t(), String.t() | nil) :: map() | nil
  def node(%__MODULE__{nodes: nodes}, id), do: Map.get(nodes, id)

  @doc "The kind of the node `id` names, or nil."
  @spec kind(t(), String.t() | nil) :: String.t() | nil
  def kind(%__MODULE__{kinds: kinds}, id), do: Map.get(kinds, id)

  @doc "Every node of `kind`, in the document's order."
  @spec nodes(t(), String.t()) :: [map()]
  def nodes(%__MODULE__{by_kind: by_kind}, kind), do: Map.get(by_kind, kind, [])

  @doc "The nodes of `kind` whose owner field `field` names `id`, in the document's order."
  @spec owned(t(), String.t(), String.t(), String.t()) :: [map()]
  def owned(lookup, kind, field, id), do: Enum.filter(nodes(lookup, kind), &(&1[field] == id))

  @doc "Every relation of `type`, in the document's order."
  @spec relations(t(), String.t()) :: [map()]
  def relations(%__MODULE__{by_type: by_type}, type), do: Map.get(by_type, type, [])

  @doc "Every relation that ends at `id`, whatever its type."
  @spec into(t(), String.t()) :: [map()]
  def into(%__MODULE__{into: into}, id), do: Map.get(into, id, [])

  @doc "Every relation that starts at `id`, whatever its type."
  @spec out(t(), String.t()) :: [map()]
  def out(%__MODULE__{out: out}, id), do: Map.get(out, id, [])

  @doc "The relations of `types` that end at `id`, in the document's order within each type."
  @spec into(t(), String.t(), String.t() | [String.t()]) :: [map()]
  def into(%__MODULE__{into: into}, id, types), do: of_types(Map.get(into, id, []), types)

  @doc "The relations of `types` that start at `id`, in the document's order within each type."
  @spec out(t(), String.t(), String.t() | [String.t()]) :: [map()]
  def out(%__MODULE__{out: out}, id, types), do: of_types(Map.get(out, id, []), types)

  @doc "The scenarios whose `covers` names relation `id`, in the document's order."
  @spec covering(t(), String.t()) :: [map()]
  def covering(%__MODULE__{covering: covering}, id), do: Map.get(covering, id, [])

  @doc "The scenarios whose `target` is `id`, in the document's order."
  @spec about(t(), String.t()) :: [map()]
  def about(%__MODULE__{about: about}, id), do: Map.get(about, id, [])

  @doc "What a node is called: the client's words, or its name where it has none, or the id."
  @spec title(t(), String.t() | nil) :: String.t() | nil
  def title(_lookup, nil), do: nil

  def title(lookup, id) do
    case node(lookup, id) do
      nil -> id
      node -> node["label"] || node["name"] || id
    end
  end

  defp of_types(relations, types) do
    types = List.wrap(types)
    for type <- types, relation <- relations, relation["type"] == type, do: relation
  end
end
