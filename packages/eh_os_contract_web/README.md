# EhOsContract.Web

A conformance dashboard for [EhOsContract](https://hex.pm/packages/eh_os_contract), mounted in your
own router.

Two screens and nothing else: the contract's conformance status, and the graphs —
each domain's context map and system, and per contract its full graph with the log laid
over it, and its units and their lifecycles.

The graphs are drawn by
[`eh_os_contract_graph`](https://github.com/EmpoweredHouse/eh-os-contract/tree/main/packages/eh_os_contract_graph),
the renderer of the engine's `graph.v1` documents; a click on anything drawn opens a panel
that says what it is.

## Installation

From git, beside the engine, with the same `git:` and `sparse:` shape — this package
declares its dependency on the engine that way whenever it is fetched on its own, so
the two declarations converge instead of diverging:

```elixir
def deps do
  [
    {:eh_os_contract,
     git: "https://github.com/EmpoweredHouse/eh-os-contract.git",
     sparse: "packages/eh_os_contract"},
    {:eh_os_contract_web,
     git: "https://github.com/EmpoweredHouse/eh-os-contract.git",
     sparse: "packages/eh_os_contract_web"}
  ]
end
```

The dashboard brings the graph renderer, `eh_os_contract_graph`, the same way, and carries its
script in its own bundle. That script reads the markup the renderer's component renders, so
update the two together: `mix deps.update eh_os_contract_web eh_os_contract_graph`.

## Mounting it

```elixir
scope "/" do
  pipe_through :browser
  import EhOsContract.Web.Router

  eh_os_contract_dashboard "/dashboard", resolver: MyApp.EhOsContractResolver
end
```

Static assets are served at the **endpoint**, not through the macro. Phoenix's
cross-origin script guard refuses to serve JavaScript through a CSRF-protected
route, on principle and correctly, so add one line to your endpoint:

```elixir
plug Plug.Static,
  at: "/eh_os_contract_web/assets",
  from: {:eh_os_contract_web, "priv/static/assets"},
  gzip: false
```

This package's own test host carries that same line, so the suite proves the
instruction rather than assuming it.

The same line serves the fonts: they sit beside the stylesheet, in
`priv/static/assets/fonts/`, and the stylesheet names them by relative URL. Nothing
the dashboard loads comes from anywhere but these assets — no Google Fonts, no CDN —
so it works under a policy of `default-src 'self'` and without internet (see "Looks"
below).

## Looks

The dashboard is styled from the EmpoweredHouse design system, the one the EHOS
console uses: dark by default, light when the system prefers it. Its tokens and fonts
come from the `ehos_design` package of EmpoweredHouse's `ehos-tools` repository, a
`:dev` dependency pinned in `mix.exs` to the commit tagged `ehos_design-v0.1.0`. `mix assets.build` imports the plain tokens,
`priv/css/colors_and_type.css`, into the stylesheet and copies the fonts beside it.
The built stylesheet and the fonts are committed under `priv/static/assets/`, so a host
fetches nothing from that package; a new version of the design system reaches the
dashboard by moving the pinned ref and rebuilding.

`ehos-tools` is private, and a plain `mix deps.get` fetches every environment's
dependencies, this one included. Without access to it, fetch with
`mix deps.get --only test`: the tests read only the committed build, and only
`mix assets.build` needs the package.

A host cannot restyle it or pin its theme yet. The dashboard's root layout replaces
the host's for these routes and loads only this package's stylesheet, so neither a
host stylesheet nor a `data-theme` attribute reaches the page. The
`--eh-os-contract-*` custom properties are kept as the names such a hook would set.

**The dashboard works under a strict Content-Security-Policy**, `default-src 'self'`
as EHOS serves it: no page carries an inline style, and the graph renderer sets none.
The sandbox host serves this policy on the dashboard, so it is looked at there as it
runs in EHOS.

## The API

`eh_os_contract_api/2` mounts read-only JSON routes in a scope of their own (its docs
show the pipeline): what a client of the engine — EHOS Console, a CI job, a renderer —
reads without the dashboard.

```elixir
scope "/" do
  pipe_through :eh_os_contract_api
  import EhOsContract.Web.Router

  eh_os_contract_api "/api", resolver: MyApp.EhOsContractResolver
end
```

| Route | What |
| --- | --- |
| `GET /api/conformance?contract=…&since=…&until=…` | the conformance report, `eh_os_contract.conformance.v3` |
| `GET /api/model`, `/api/model/rehmed.settlement` | the exported model, `eh_os_contract.model.v1`, digest as `ETag` |
| `GET /api/asyncapi`, `/api/asyncapi/rehmed.settlement` | what a contract publishes, as AsyncAPI |
| `GET /api/openapi`, `/api/openapi/rehmed.settlement` | its commands and queries, as OpenAPI |
| `GET /api/graph` | every contract and domain with its version and graph digest |
| `GET /api/graph/rehmed.settlement` | the contract's `graph.v1` document: its graph of facts, with the panels' content and scenarios |
| `GET /api/graph/rehmed.settlement/overlay?since=…&until=…` | what the log says over it, `eh_os_contract.graph_overlay.v1` |
| `GET /api/graph/domain/Rehmed.Domain`, `…/overlay` | the same for a domain: contexts, actors, contracts and what crosses between them |

**Which to read.** A graph or a picture of a contract — the EHOS Console, a renderer — reads
`/graph`: its document holds every fact a picture or a panel shows, by stable ids, and its
overlay what the log says over them. `/model` is the contract as its DSL declares it, one
key per declaration, for a reader that works with the declarations themselves rather than a
picture of them, such as a code generator or a diff of two versions in CI.

A contract is named by its `id:` on every route; a domain, which has none, by its module.
A graph document is the same bytes for the same declarations — every object's keys in
order — so its digest is its `ETag`, and a request sending it back in `If-None-Match`
gets `304`. An overlay names the digest of the document it joins (`document_digest`)
and is joined onto it by id. The schemas ship with `eh_os_contract`, in
`priv/schema/graph.v1.json` and `priv/schema/graph_overlay.v1.json`. A contract or a
domain the registry does not hold is `404`, never an empty graph.

## Who may see it

`eh_os_contract_dashboard/2` and `eh_os_contract_api/2` both require a `:resolver` implementing
`EhOsContract.Web.Resolver`: one callback says who the caller is, another says whether they
get `:all`, `:read_only` or a redirect. There is no default and no login screen —
the host already knows who is logged in, and this package does not get to guess.

## Not on Hex

This package is not published. Two reasons, both recorded rather than pending:

- it depends on `eh_os_contract`, which is not on Hex either, and a published package
  may depend only on published ones;
- `priv/static/assets/fonts/` holds two third-party fonts, and `priv/static/assets/app.js`
  bundles the graph renderer's dagre and d3, so a tarball redistributes somebody else's
  work. `NOTICE` carries the attribution, and the decision to actually publish is a
  separate one.

## Licence

Apache 2.0. Third-party components are listed in `NOTICE`.
