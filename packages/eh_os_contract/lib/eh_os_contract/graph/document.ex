defmodule EhOsContract.Graph.Document do
  @moduledoc """
  The graphs of the contracts as data, with nothing of how they are drawn (plan E13a):
  nodes, edges and groups, which `build/*` of `EhOsContract.Graph.Contract`,
  `EhOsContract.Graph.Unit`, `EhOsContract.Graph.Lifecycle`,
  `EhOsContract.Graph.Declared`, `EhOsContract.Graph.ContextMap` and
  `EhOsContract.Graph.System` return — and the `graph.v1` documents made of them
  (`contract/1`, `domain/2`), which is what the engine hands a renderer, in the same
  process or over HTTP.

  A node is `%{id, kind, name, label}`, and a kind may add what it alone has: a
  command's constraint the `command` it belongs to, a unit's state its `unit_kind` and
  `fields`, a lifecycle's status whether it is `final`, a contract the label of its
  `process`, an event on a process's declared shape its `stage` and whether it is
  `terminal`. With the log laid over a graph, an event carries `counts`,
  its occurrences, and a contract its process's `runs`.

  An edge is `%{id, from, to, relation}`: what the source is to the target, read in the
  edge's direction — a command `emits` an event, an event is `projected_into` a read
  model, a contract's events are `consumed_by` another — never how the line looks; a
  renderer chooses that from the relation. A context-mapping pattern goes from the
  upstream to the downstream, or, symmetric, between the two ends in the order
  `between` names them. A relation may add what it
  needs: `delivery` (`:inline` or `:async`) where a step or a projection runs in the
  transaction or after it, `scenarios` where scenarios pin a path, `field`, `match`,
  `event`, `label`, `events`, `as` or `promise` where the relation is about one of
  them, `within` where a promise has a window; and, with the log over it, `overlay`,
  the numbers the log gives it. An edge ends at nodes, except `precedes`, which orders
  two stages and so goes from one stage's group to the next one's.

  A group is `%{id, kind, name, label, nodes}`: a unit's commands and events, a
  subdomain's contexts, a context's contracts, a stage's events.

  ## The documents

  A `graph.v1` document is JSON-ready data — string keys, atoms as strings, modules
  without `Elixir.` — whose top level says what it is: `schema`
  (`"eh_os_contract.graph.v1"`), `kind` (`"contract"` or `"domain"`), what it is of,
  its `graphs`, and a `digest` (`digest/1`). Its shape is the JSON Schema at
  `schema_path/0`, which ships with the package so a renderer can hold a document to
  it without the engine.

  **A document is what the contract declares and nothing from the log**, so it does
  not depend on the database: the same contract gives the same document and the same
  digest, and a reader that has the digest already need not fetch it again. What the
  log says over it is another document (plan E13a, batch 4), joined on the same ids.

  **An id is stable and opaque.** It is made from the node's kind, the module whose
  name it is and the names that pick it out there (`id/1`), so the same declaration
  has the same id in every version of the contract, and an overlay or a renderer
  joins on it. On a contract's graphs that module is the contract: an event it
  consumes or includes is drawn under the name it has *here*, which a rename may make
  another than its declaring contract's, so it is `event:<this contract>:<local
  name>` — the same event has another id on the graph of the contract that declares
  it. An actor, an external system, a context, a subdomain and a publication are the
  domain's. Nothing should read an id apart: a client's name may hold any character,
  a colon included. An edge's id is its relation, its two ends and what tells it
  apart from another edge of that relation between them (`edge/4`), so what the log
  says of a step or a transition joins on an id too.
  """

  alias EhOsContract.{Graph, Model}

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
          | :precedes
          | :eventually
          | :or_else
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
          required(:id) => String.t(),
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

  @schema "eh_os_contract.graph.v1"

  # What tells apart two edges of one relation between the same two nodes.
  @discriminators [:event, :promise, :field, :as]

  @doc """
  The document of `contract`: its full graph (`EhOsContract.Graph.Contract`), its
  process's declared shape (`EhOsContract.Graph.Declared`, `nil` without a process),
  and each unit's graph (`EhOsContract.Graph.Unit`) and each lifecycle
  (`EhOsContract.Graph.Lifecycle`), keyed by the id of the unit's group on the full
  graph — so a reader goes from the group it was shown to the unit's own pictures by
  the id it already has. With the contract's `version` and the document's `digest`.
  """
  @spec contract(module() | map()) :: map()
  def contract(contract) do
    model = Model.fetch(contract)
    unit_id = &id([:unit, model.module, &1.name])

    graphs = %{
      contract: Graph.Contract.build(model),
      process: model.process && Graph.Declared.build(model, model.process.name),
      units: Map.new(model.units, &{unit_id.(&1), Graph.Unit.build(model, &1.name)}),
      lifecycles:
        for(
          u <- model.units,
          EhOsContract.Lifecycle.of(u),
          into: %{},
          do: {unit_id.(u), Graph.Lifecycle.build(model, u.name)}
        )
    }

    seal(%{
      "schema" => @schema,
      "kind" => "contract",
      "contract" => Model.json_data(model.module),
      "domain" => Model.json_data(model.domain),
      "version" => model.version,
      "graphs" => %{
        "contract" => json_graph(graphs.contract),
        "process" => graphs.process && json_graph(graphs.process),
        "units" => Map.new(graphs.units, fn {k, g} -> {k, json_graph(g)} end),
        "lifecycles" => Map.new(graphs.lifecycles, fn {k, g} -> {k, json_graph(g)} end)
      }
    })
  end

  @doc """
  The document of `domain`: its context map (`EhOsContract.Graph.ContextMap`) and its
  `contracts` as one system (`EhOsContract.Graph.System`, which leaves out those of
  another domain), with the document's `digest`. The order of `contracts` does not
  matter.
  """
  @spec domain(module() | map(), [module() | map()]) :: map()
  def domain(domain, contracts) do
    model = Model.fetch(domain)
    # The system is drawn in the order it is given; the document is the same whoever
    # asks for it, in whatever order they list the contracts.
    contracts = Enum.sort_by(contracts, &Model.fetch(&1).module)

    seal(%{
      "schema" => @schema,
      "kind" => "domain",
      "domain" => Model.json_data(model.module),
      "graphs" => %{
        "context_map" => json_graph(Graph.ContextMap.build(model)),
        "system" => json_graph(Graph.System.build(model, contracts))
      }
    })
  end

  @doc """
  The digest of a document: a hash of everything in it but the digest itself, through
  `EhOsContract.Digest`, so it does not depend on the order keys are written in. It
  hashes the generated document rather than the contract, as the model's and the
  AsyncAPI's digests do: a change to how a graph is built changes what a reader is
  given, and the digest has to say so.
  """
  @spec digest(map()) :: String.t()
  def digest(document),
    do: document |> Map.delete("digest") |> EhOsContract.Digest.document_hash()

  @doc "Where the JSON Schema of a `graph.v1` document is: in the package's `priv/schema`."
  @spec schema_path() :: Path.t()
  def schema_path, do: Application.app_dir(:eh_os_contract, "priv/schema/graph.v1.json")

  defp seal(body), do: Map.put(body, "digest", digest(body))

  # Every graph has its groups, empty where it has none, so a reader need not ask.
  defp json_graph(graph), do: graph |> Map.put_new(:groups, []) |> Model.json_data()

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
  `nil` is left out, so an edge has a key only for what it says. Its id is the
  relation, its two ends and, where two edges of one relation may join the same two
  nodes, what tells them apart (`@discriminators`): two transitions between two
  statuses by two events, two promises over one pair of events, two fields one
  external gives one command.
  """
  @spec edge(String.t(), String.t(), relation(), keyword() | map()) :: edge()
  def edge(from, to, relation, attrs \\ []) do
    edge =
      for {key, value} <- attrs,
          value != nil,
          into: %{from: from, to: to, relation: relation},
          do: {key, value}

    apart = for key <- @discriminators, Map.has_key?(edge, key), do: to_string(edge[key])
    Map.put(edge, :id, id([relation, from, to | apart]))
  end
end
