defmodule EhOsContract.GraphRenderer.View do
  @moduledoc """
  Which facts of a document are drawn together: a view is the nodes one picture
  shows and the relations between them.

  A document groups its nodes by kind and its relations by type
  (`EhOsContract.Graph.Document` in the engine). A view flattens them into the two
  lists the drawing layer takes, each node with its kind and each relation with its
  type, and keeps a relation only when both of its ends are in the view, so that no
  arrow points at nothing.

  **There is one view so far, `all/1`**: every node and every relation of the
  document. It is a test bed for the drawing layer, not a picture anybody reads
  from: the views a reader is shown are specified on paper first and approved by
  the user (plan E13b, batch 2), then built here as functions of the same shape.
  """

  @typedoc "A node as the drawing layer takes it; `facts` is the document's node, whole."
  @type graph_node :: %{
          id: String.t(),
          kind: String.t(),
          name: String.t(),
          label: String.t() | nil,
          facts: map()
        }

  @typedoc "A relation as the drawing layer takes it; `facts` is the document's relation, whole."
  @type relation :: %{
          id: String.t(),
          type: String.t(),
          from: String.t(),
          to: String.t(),
          facts: map()
        }

  @type t :: %{nodes: [graph_node()], relations: [relation()]}

  @doc """
  Every node and every relation of `document`, kinds and types in name order and each
  group in the document's order, so the same document gives the same view and the
  same layout.
  """
  @spec all(map()) :: t()
  def all(%{"nodes" => nodes, "relations" => relations}) do
    nodes =
      for {kind, group} <- Enum.sort(nodes), node <- group do
        %{id: node["id"], kind: kind, name: node["name"], label: node["label"], facts: node}
      end

    %{nodes: nodes, relations: within(nodes, flatten(relations))}
  end

  @doc """
  `view` with the relations `overlay` observed and the document does not declare —
  a move a lifecycle does not allow, which happened anyway — as relations of type
  `"undeclared"`. Without an overlay, the view as it is.
  """
  @spec with_observed(t(), map() | nil) :: t()
  def with_observed(view, nil), do: view

  def with_observed(view, overlay) do
    observed = get_in(overlay, ["observed", "relations"]) || %{}
    %{view | relations: view.relations ++ within(view.nodes, flatten(observed))}
  end

  defp flatten(relations) do
    for {type, group} <- Enum.sort(relations), relation <- group do
      %{
        id: relation["id"],
        type: type,
        from: relation["from"],
        to: relation["to"],
        facts: relation
      }
    end
  end

  defp within(nodes, relations) do
    ids = MapSet.new(nodes, & &1.id)
    Enum.filter(relations, &(MapSet.member?(ids, &1.from) and MapSet.member?(ids, &1.to)))
  end
end
