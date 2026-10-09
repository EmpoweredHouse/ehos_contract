defmodule EhOsContract.Graph.Document do
  # Plan E13a. The facts are built by `EhOsContract.Graph.Facts`; the overlay is
  # batch 5's. What a contract declares is scoped to its `id:` since plan DD, ID3
  # (#173).
  @moduledoc """
  The `graph.v1` documents: what the engine hands a renderer, in the same process or
  over HTTP — a contract's (`contract/1`) and a domain's (`domain/2`).

  ## The documents

  A document is a **graph of facts**: `nodes` grouped by kind and `relations` grouped by
  type, every kind and type present, and a contract's `scenarios` grouped by the kind of
  their target. Example and default data in it are redacted as in
  `EhOsContract.Model.to_data/1`. It holds no pictures — which facts are shown together,
  and how, is the renderer's — and nothing from the log. It is JSON-ready data — string
  keys, atoms as strings, modules without `Elixir.` — whose top level says what it is:
  `schema` (`"eh_os_contract.graph.v1"`), `kind` (`"contract"` or `"domain"`), what it
  is of, its `version`, and a `digest` (`digest/1`). Its shape is the JSON Schema at
  `schema_path/0`, which ships with the package so a renderer can hold a document to it
  without the engine.

  **A document is what the contract declares and nothing from the log**, so it does
  not depend on the database: the same contract gives the same document and the same
  digest, and a reader that has the digest already need not fetch it again. What the
  log says over it is another document (`EhOsContract.Graph.Overlay`), joined on the
  same ids.

  **An id is stable and opaque.** It is made from the declaration's kind, what it is
  declared in and the names that pick it out there (`id/1`), so the same declaration has
  the same id in every version of the contract, and an overlay or a renderer joins on
  it. What a contract declares is scoped to the contract's `id:`, as the log names it,
  so moving the contract's module moves no id: an event it consumes is a node under the
  name it has *here*, which a rename may make another than its sibling's, so it is
  `event:<this contract's id>:<local name>` and says which sibling event it is in
  `declared_as`. An actor, an external system, a context, a subdomain and a publication
  are the domain's, scoped to the domain's module. Nothing should read an id apart: a
  client's name may hold any character, a colon included.
  """

  alias EhOsContract.{Graph, Model}

  @schema "eh_os_contract.graph.v1"

  # The contract's `id:` names it outside the code since plan DD, P1a (#183).
  @doc """
  The document of `contract`: its graph of facts under `nodes`, `relations` and
  `scenarios`, with what it is — the contract's `id:` as `contract`, which names it
  outside the code, its `module`, the domain it names, the id of its context, its
  `version` — and the document's `digest`.
  """
  @spec contract(module() | map()) :: map()
  def contract(contract) do
    model = Model.fetch(contract)
    facts = Graph.Facts.contract(model)

    seal(%{
      "schema" => @schema,
      "kind" => "contract",
      "contract" => model.id,
      "module" => Model.json_data(model.module),
      "domain" => Model.json_data(model.domain),
      "context" => id([:context, model.domain, model.context]),
      "version" => model.version,
      "nodes" => Model.json_data(facts.nodes),
      "relations" => Model.json_data(facts.relations),
      "scenarios" => Model.json_data(facts.scenarios)
    })
  end

  @doc """
  The document of `domain`: its graph of facts over `contracts`, leaving out those of
  another domain, with the
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
  The digest of a document: a hash of everything in it but the digest itself, which
  does not depend on the order its keys are written in. It
  hashes the generated document rather than the contract, as the model's and the
  AsyncAPI's digests do: a change to how a graph is built changes what a reader is
  given, and the digest has to say so.
  """
  @spec digest(map()) :: String.t()
  def digest(document),
    do: document |> Map.delete("digest") |> EhOsContract.Digest.document_hash()

  @doc """
  `document` — a `graph.v1` document or an overlay — as JSON whose bytes depend on
  its content alone: every object's keys in order, at every depth, rather than in
  whatever order a map happens to keep them. The same declarations give the same
  bytes, after a restart too, so the digest is a sound `ETag` and two outputs can be
  compared with `diff`. `pretty: true` indents it.
  """
  @spec encode(map(), keyword()) :: String.t()
  def encode(document, opts \\ []),
    do: document |> ordered() |> Jason.encode!(pretty: Keyword.get(opts, :pretty, false))

  defp ordered(%{} = map) do
    map
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {key, value} -> {key, ordered(value)} end)
    |> Jason.OrderedObject.new()
  end

  defp ordered(list) when is_list(list), do: Enum.map(list, &ordered/1)
  defp ordered(value), do: value

  @doc "Where the JSON Schema of a `graph.v1` document is: in the package's `priv/schema`."
  @spec schema_path() :: Path.t()
  def schema_path, do: Application.app_dir(:eh_os_contract, "priv/schema/graph.v1.json")

  defp seal(body), do: Map.put(body, "digest", digest(body))

  @doc """
  The id of a declaration: its kind, then what it is declared in — a contract's `id:`,
  or a domain's module — then the names that pick it out there —
  `[:event, "rehmed.settlement", :visit_settled]` is
  `"event:rehmed.settlement:visit_settled"`, `[:actor, Rehmed.Domain, :reception]` is
  `"actor:Rehmed.Domain:reception"`.
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
end
