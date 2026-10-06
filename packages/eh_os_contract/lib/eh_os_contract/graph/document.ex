defmodule EhOsContract.Graph.Document do
  @moduledoc """
  The `graph.v1` documents (plan E13a): what the engine hands a renderer, in the same
  process or over HTTP — a contract's (`contract/1`) and a domain's (`domain/2`).

  ## The documents

  A document is a **graph of facts** (`EhOsContract.Graph.Facts`): `nodes` grouped by
  kind and `relations` grouped by type, every kind and type present, and a contract's
  `scenarios` grouped by the kind of their target. Example and default data in it are
  redacted as in `EhOsContract.Model.to_data/1`. It holds no
  pictures — which facts are shown together, and how, is the renderer's — and
  nothing from the log. It is JSON-ready data — string keys, atoms as strings,
  modules without `Elixir.` — whose top level says what it is: `schema`
  (`"eh_os_contract.graph.v1"`), `kind` (`"contract"` or `"domain"`), what it is of,
  its `version`, and a `digest` (`digest/1`). Its shape is the JSON Schema at
  `schema_path/0`, which ships with the package so a renderer can hold a document to
  it without the engine.

  **A document is what the contract declares and nothing from the log**, so it does
  not depend on the database: the same contract gives the same document and the same
  digest, and a reader that has the digest already need not fetch it again. What the
  log says over it is another document (plan E13a, batch 5), joined on the same ids.

  **An id is stable and opaque.** It is made from the declaration's kind, the module
  whose name it is and the names that pick it out there (`id/1`), so the same
  declaration has the same id in every version of the contract, and an overlay or a
  renderer joins on it. In a contract's document that module is the contract: an
  event it consumes is a node under the name it has *here*, which a rename may make
  another than its sibling's, so it is `event:<this contract>:<local name>` and
  says which sibling event it is in `declared_as`. An actor, an external system, a
  context, a subdomain and a publication are the domain's. Nothing should read an id
  apart: a client's name may hold any character, a colon included.

  ## The pictures, until E13b

  `graph_node/4`, `edge/4` and the types below serve the six pictures the dashboard
  draws with Mermaid (`EhOsContract.Graph.Contract`, `Unit`, `Lifecycle`, `Declared`,
  `ContextMap`, `System`): a node is `%{id, kind, name, label}` and what its kind
  adds, an edge `%{id, from, to, relation}` and what its relation adds, a group
  `%{id, kind, name, label, nodes}`. They go with Mermaid in E13b.
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
  The document of `contract`: its graph of facts (`EhOsContract.Graph.Facts`) under
  `nodes`, `relations` and `scenarios`, with what it is — the contract's module and `id:`, the
  domain it names, the id of its context, its `version` — and the document's
  `digest`.
  """
  @spec contract(module() | map()) :: map()
  def contract(contract) do
    model = Model.fetch(contract)
    facts = Graph.Facts.contract(model)

    seal(%{
      "schema" => @schema,
      "kind" => "contract",
      "contract" => Model.json_data(model.module),
      "contract_id" => Model.json_data(Map.get(model, :id)),
      "domain" => Model.json_data(model.domain),
      "context" => id([:context, model.domain, model.context]),
      "version" => model.version,
      "nodes" => Model.json_data(facts.nodes),
      "relations" => Model.json_data(facts.relations),
      "scenarios" => Model.json_data(facts.scenarios)
    })
  end

  @doc """
  The document of `domain`: its graph of facts over `contracts`
  (`EhOsContract.Graph.Facts`, which leaves out those of another domain), with the
  domain's `name` — the prefix of every role and capability — `language`,
  `time_zone` and `version`, and the document's `digest`. The order of `contracts`
  does not matter.
  """
  @spec domain(module() | map(), [module() | map()]) :: map()
  def domain(domain, contracts) do
    model = Model.fetch(domain)
    facts = Graph.Facts.domain(model, contracts)

    seal(%{
      "schema" => @schema,
      "kind" => "domain",
      "domain" => Model.json_data(model.module),
      "name" => Model.json_data(model.name),
      "language" => Model.json_data(model.language),
      "time_zone" => model.time_zone,
      "version" => model.version,
      "nodes" => Model.json_data(facts.nodes),
      "relations" => Model.json_data(facts.relations)
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
