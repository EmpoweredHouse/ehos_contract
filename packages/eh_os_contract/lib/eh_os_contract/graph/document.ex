defmodule EhOsContract.Graph.Document do
  @moduledoc """
  The graphs of the contracts as data, with nothing of how they are drawn (plan E13a):
  nodes, edges and groups, which `build/*` of `EhOsContract.Graph.Contract`,
  `EhOsContract.Graph.Unit`, `EhOsContract.Graph.Lifecycle`,
  `EhOsContract.Graph.ContextMap` and `EhOsContract.Graph.System` return.

  A node is `%{id, kind, name, label}`, and a kind may add what it alone has: a
  command's constraint the `command` it belongs to, a unit's state its `unit_kind` and
  `fields`, a lifecycle's status whether it is `final`, a contract the label of its
  `process`. With the log laid over a graph, an event carries `counts`,
  its occurrences, and a contract its process's `runs`.

  An edge is `%{from, to, relation}`: what the source is to the target, read in the
  edge's direction — a command `emits` an event, an event is `projected_into` a read
  model, a contract's events are `consumed_by` another — never how the line looks; a
  renderer chooses that from the relation. A context-mapping pattern goes from the
  upstream to the downstream, or, symmetric, between the two ends in the order
  `between` names them. A relation may add what it
  needs: `delivery` (`:inline` or `:async`) where a step or a projection runs in the
  transaction or after it, `scenarios` where scenarios pin a path, `field`, `match`,
  `event`, `label`, `events` or `as` where the relation is about one of them; and,
  with the log over it, `overlay`, the numbers the log gives it.

  A group is `%{id, kind, name, label, nodes}`: a unit's commands and events, a
  subdomain's contexts, a context's contracts.

  **An id is stable and opaque.** It is made from the node's kind, the module whose
  name it is and the names that pick it out there (`id/1`), so the same declaration
  has the same id in every version of the contract, and an overlay or a renderer
  joins on it. On a contract's graphs that module is the contract: an event it
  consumes or includes is drawn under the name it has *here*, which a rename may make
  another than its declaring contract's, so it is `event:<this contract>:<local
  name>` — the same event has another id on the graph of the contract that declares
  it. An actor, an external system, a context, a subdomain and a publication are the
  domain's. Nothing should read an id apart: a client's name may hold any character,
  a colon included.
  """

  @typedoc "What an edge's source is to its target."
  @type relation ::
          :emits
          | :handled_by
          | :issues
          | :fires
          | :sets_timer
          | :records
          | :asks
          | :projected_into
          | :reads
          | :calls
          | :depends_on
          | :backed_by
          | :gives
          | :refused_on
          | :builds
          | :consulted_by
          | :transition
          | :undeclared
          | :consumed_by
          | :publishes
          | :subscribed_by
          | :partnership
          | :shared_kernel
          | :separate_ways
          | :customer_supplier
          | :conformist
          | :anticorruption_layer
          | :open_host_service
          | :published_language

  @typedoc "A node of a graph."
  @type graph_node :: %{
          required(:id) => String.t(),
          required(:kind) => atom(),
          required(:name) => atom() | String.t() | nil,
          required(:label) => String.t() | nil,
          optional(atom()) => term()
        }

  @typedoc "An edge of a graph."
  @type edge :: %{
          required(:from) => String.t(),
          required(:to) => String.t(),
          required(:relation) => relation(),
          optional(atom()) => term()
        }

  @typedoc "A group of nodes."
  @type group :: %{
          required(:id) => String.t(),
          required(:kind) => atom(),
          required(:name) => atom() | String.t(),
          required(:label) => String.t(),
          required(:nodes) => [String.t()],
          optional(atom()) => term()
        }

  @typedoc "A graph."
  @type graph :: %{
          required(:nodes) => [graph_node()],
          required(:edges) => [edge()],
          optional(:groups) => [group()]
        }

  @doc """
  The id of a declaration: its kind, then the module whose name it is, then the names
  that pick it out there — `[:event, Rehmed.Contracts.VisitSettlement, :visit_settled]`
  is `"event:Rehmed.Contracts.VisitSettlement:visit_settled"`.
  """
  @spec id([atom() | String.t()]) :: String.t()
  def id(parts), do: Enum.map_join(parts, ":", &part/1)

  defp part(module) when is_atom(module) do
    case Atom.to_string(module) do
      "Elixir." <> name -> name
      name -> name
    end
  end

  defp part(name), do: name

  @doc """
  A node of `kind` named `name`, declared in `scope`, with its label or, lacking one,
  its name.
  """
  @spec graph_node(atom(), module(), atom() | String.t(), String.t() | nil) :: graph_node()
  def graph_node(kind, scope, name, label),
    do: %{id: id([kind, scope, name]), kind: kind, name: name, label: label || to_string(name)}

  @doc """
  An edge between two node ids, with what `relation` adds; an attribute given as
  `nil` is left out, so an edge has a key only for what it says.
  """
  @spec edge(String.t(), String.t(), relation(), keyword() | map()) :: edge()
  def edge(from, to, relation, attrs \\ []) do
    for {key, value} <- attrs,
        value != nil,
        into: %{from: from, to: to, relation: relation},
        do: {key, value}
  end
end
