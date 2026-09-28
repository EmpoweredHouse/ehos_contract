defmodule EhOsContract.Graph.ContextMap do
  @moduledoc """
  A domain's context map as a graph (plan EG2): its subdomains, each a group of the
  contexts in it, its external systems, and the relations between them.

  A relation with a direction — `customer_supplier`, `conformist`,
  `anticorruption_layer`, `open_host_service`, `published_language` — is an arrow
  from its upstream to its downstream, either end of which may be an external
  system. A symmetric one — `partnership`, `shared_kernel` — is a line without an
  arrowhead, and `separate_ways`, which says the two do not integrate, a dashed one.
  Every external of the domain is on the map, one no relation reaches included: that
  is a finding, and a map that hides it is the wrong tool to find it with.

  It reads the domain alone. Which contract sits where, and what flows between them,
  is `EhOsContract.Graph.System`'s picture.
  """

  alias EhOsContract.Graph.Mermaid
  alias EhOsContract.Model

  @doc "The context map of `domain`, a domain module or its model, as data."
  @spec build(module() | map()) :: Mermaid.graph()
  def build(domain) do
    domain = Model.fetch(domain)
    contexts = MapSet.new(domain.contexts, & &1.name)
    node_id = fn name -> Mermaid.id(end_kind(contexts, name), name) end

    context_nodes = Enum.map(domain.contexts, &Mermaid.graph_node(:context, &1.name, &1.label))
    external_nodes = Enum.map(domain.externals, &Mermaid.graph_node(:external, &1.name, &1.label))

    groups =
      for subdomain <- domain.subdomains,
          members = for(c <- domain.contexts, c.subdomain == subdomain.name, do: c),
          members != [] do
        %{
          id: Mermaid.id(:subdomain, subdomain.name),
          label: "#{subdomain.label} · #{subdomain.type}",
          nodes: Enum.map(members, &Mermaid.id(:context, &1.name))
        }
      end

    %{
      nodes: context_nodes ++ external_nodes,
      edges: Enum.map(domain.relations, &relation(&1, node_id)),
      groups: groups
    }
  end

  @doc "The context map of `domain` as a Mermaid flowchart."
  @spec to_mermaid(module() | map()) :: String.t()
  def to_mermaid(domain), do: domain |> build() |> Mermaid.render("LR")

  defp end_kind(contexts, name),
    do: if(MapSet.member?(contexts, name), do: :context, else: :external)

  defp relation(%{between: [a, b]} = r, node_id) do
    Mermaid.edge(node_id.(a), node_id.(b),
      line: if(r.type == :separate_ways, do: :dotted, else: :solid),
      head: false,
      label: words(r.type)
    )
  end

  defp relation(r, node_id),
    do: Mermaid.edge(node_id.(r.upstream), node_id.(r.downstream), label: words(r.type))

  defp words(type), do: type |> Atom.to_string() |> String.replace("_", " ")
end
