# The JSON API

This page gives each route of the read-only JSON API of the dashboard: what it accepts, what it
returns, and its errors. It is for a developer of a client that reads the contracts of an
application without the dashboard. Examples of such a client are a CI job, a renderer and a tool.

## Mount it

The API needs a pipeline of its own that accepts JSON. A browser pipeline answers 406 to an API
client before the route.

```elixir
pipeline :ehos_contract_api do
  plug :accepts, ["json"]
end

scope "/" do
  pipe_through :ehos_contract_api
  import EhosContract.Web.Router

  ehos_contract_api "/api", resolver: MyApp.EhosContractResolver
end
```

`:resolver` is required. It is the resolver of the dashboard:
[Decide who can see the dashboard](who-can-see-it.md). The macro adds no `Plug.Parsers`, because
no route has a body.

The API adds no authentication. Add a plug that authenticates your API clients to this pipeline.
The `resolve_user/1` of the resolver then finds the caller on the connection.

## Routes

Each route is `GET`. The examples use the mount `/api`.

| Route | Returns |
| --- | --- |
| `/api/conformance?contract=<id>&since=<ISO 8601>&until=<ISO 8601>` | the conformance report of the contract, schema `ehos_contract.conformance.v3` |
| `/api/conformance?process=<id>&since=<ISO 8601>&until=<ISO 8601>` | the conformance report of the process module, with the same schema, keyed `"process"` where the report of a contract is keyed `"contract"` |
| `/api/model` | each contract with its module, its version and the digest of its model document, schema `ehos_contract.model-index.v2` |
| `/api/model/<id>` | the model document of the contract, schema `ehos_contract.model.v1` |
| `/api/openapi` | each contract, with its version and the digest of its OpenAPI document |
| `/api/openapi/<id>` | the commands and queries of the contract, as OpenAPI 3.1 |
| `/api/asyncapi` | each contract, with its version and the digest of its AsyncAPI document |
| `/api/asyncapi/<id>` | what the contract publishes, as AsyncAPI 3.0 |
| `/api/graph` | each contract, process module and domain, with its version and the digest of its graph document |
| `/api/graph/<id>` | the graph document of the contract, `graph.v1`: its facts, with the content of the panels and the scenarios |
| `/api/graph/<id>/overlay?since=<ISO 8601>&until=<ISO 8601>` | the overlay of the contract, `ehos_contract.graph_overlay.v1`: what the log says over its graph document |
| `/api/graph/process/<id>` | the graph document of the process module: its stages, the events that each stage includes, and its promises |
| `/api/graph/process/<id>/overlay?since=…&until=…` | its overlay: its runs, how many times each event occurred, and the verdicts of each promise |
| `/api/graph/domain/<module>` | the graph document of the domain: its contexts, actors, contracts and process modules, and what goes between them |
| `/api/graph/domain/<module>/overlay?since=…&until=…` | its overlay |

Four routes are indexes: `/api/graph`, `/api/model`, `/api/openapi` and `/api/asyncapi`. If the
application has nothing to list, each answers 200 with empty lists.

On `/api/conformance`:

- `contract` is optional if the application has exactly one contract.
- `since` and `until` are optional.
- Do not give `contract` and `process` together.

## Names

- A contract has the same name on each route: its `id:`.
- A process module has its own `id:`, under `/api/graph/process/` and in `process=`. A process
  module and a contract can have the same id, so the two have separate routes.
- A domain has no `id:`, so its routes name its module, such as `Lending.Domain`.

## Which document do I read?

- **A client that draws a contract reads `/api/graph/<id>`.** A graph document holds each fact that a
  picture or a panel shows, by ids that do not change. Its overlay holds what the log says about
  the same ids.
- **A client that works with the declarations reads `/api/model/<id>`.** The model document is the
  contract as its DSL declares it, one key for each declaration. Examples: a code generator, or a
  comparison of 2 versions in CI.

## Digests and caching

The engine writes the same bytes for the same declarations, with the keys of each object in
order. The digest of a document is therefore its version.

- A model document and a graph document hold the digest in `"digest"`. An OpenAPI or AsyncAPI
  document holds it in `info["x-ehos-contract-digest"]`.
- Each of these documents also sends the digest as its `ETag`. A client can compare what an
  instance serves with what its build recorded, with a `HEAD` request and no body.
- A graph document answers `304` to a request whose `If-None-Match` has its digest, or `*`. The
  other documents send the `ETag` but do not answer `304`.
- An overlay has no digest and no `ETag`, because the log changes under it. It gives the digest of
  the graph document that it belongs to, in `document_digest`, and joins it by id.

The JSON Schemas ship with `ehos_contract`: `priv/schema/graph.v1.json` and
`priv/schema/graph_overlay.v1.json`.

## Errors

| Status | Body | When |
| --- | --- | --- |
| 400 | `{"error": "bad_request", "detail": …}` | On `/api/conformance`: an unknown contract or process module, both given, no `contract` and no `process` when the application has 0 or more than 1 contract, or a parameter that does not parse. On an overlay: a time that does not parse, or a `since` after its `until`. |
| 403 | `{"error": "forbidden"}` | The resolver refused the caller, on any route. |
| 404 | `{"error": "not_found", "detail": …}` | A contract, process module or domain that the application does not have, on each route except `/api/conformance`, the overlays included. A contract, process module or domain that the application does not have never gets an empty graph document. |

## Who sees it

The API carries no business data, but it gives the business of the client in the words of the
client. The conformance report gives the number of events for each version, with their times:
the volume of the business. The API redacts nothing. The resolver decides who sees it.

## Next steps

- [Decide who can see the dashboard](who-can-see-it.md): the resolver that each route asks first.
- `EhosContract.Web.Router`: the reference of the macro.
