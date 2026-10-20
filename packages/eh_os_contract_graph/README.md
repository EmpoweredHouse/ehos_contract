# EhOsContract.GraphRenderer

Draws [EhOsContract](https://github.com/EmpoweredHouse/eh-os-contract/tree/main/packages/eh_os_contract)'s
`graph.v1` documents in a Phoenix LiveView: a card per node, an arrow per relation, the overlay's numbers from the log on them, and a panel for what is clicked.

The engine says what is in a contract or a domain; this package says how it is drawn. At run time it needs
`phoenix_live_view` (and `phoenix`, which that needs anyway), and `boundary` and `esbuild` come with it as
tools of its own build; it does not depend on the engine: a document is plain data, the same whether it
comes from `EhOsContract.Graph.Document` in the same process or from `GET <mount>/graph/:contract` decoded.
`eh_os_contract_web`'s dashboard draws with it, and so can the EHOS Console.

**Work in progress.** An explorer moves through a domain's pictures (below); a canvas draws one. It draws seven views — a contract's full graph, a unit, an aggregate's lifecycle, a
process module's stages and promises, a domain's context map and its system, several domains joined into a
landscape — and, as a test bed, every node
and relation of a document. The panel says what is clicked, from the document alone: a command's fields and who may issue it, an event's and where it comes from, a reaction's
rules, delivery and scenarios, a query's parameters and answers, a context's terms, an actor's role and
what it may do, the scenarios behind an arrow.

## Installation

From git, with the same `git:` and `sparse:` shape as the other packages of this repository:

```elixir
{:eh_os_contract_graph,
 git: "https://github.com/EmpoweredHouse/eh-os-contract.git",
 sparse: "packages/eh_os_contract_graph"}
```

A host of `eh_os_contract_web` needs none of this: the dashboard declares the dependency and carries the
script and the stylesheet in its own. The two are made for each other — the script in the dashboard's bundle
reads the markup this package renders — so update them together:
`mix deps.update eh_os_contract_web eh_os_contract_graph`.

## Exploring a domain

The explorer is one canvas the reader moves through, with two viewpoints as tabs: the **structure** — the
domain's system (its contracts in their contexts, with a switch to its context map), a contract, one of its units
(with a switch to its lifecycle) — and the **processes**. A path goes back up, and the panel opens where a card
leads: a contract or a process of the map, a unit of a contract, an event's unit or contract.

```heex
<.live_component
  module={EhOsContract.GraphRenderer.Explorer}
  id="graph"
  domain="Lending.Domain"
  loader={MyAppWeb.GraphLoader}
/>
```

The host gives it a loader, `EhOsContract.GraphRenderer.Loader`: `document/2` and `overlay/2` of a domain, a
contract or a process module, which the explorer calls in the background the first time the reader enters a
picture. An application reads its engine; a host with only the application's JSON API reads
`GET <mount>/graph/…`.

## Drawing a document

```heex
<.live_component
  module={EhOsContract.GraphRenderer.Canvas}
  id="contract-graph"
  document={@document}
  overlay={@overlay}
  view={:contract}
/>
```

`document` is a `graph.v1` document with string keys. `overlay`, optional, is an
`eh_os_contract.graph_overlay.v1` of the same document; one whose `document_digest` is not the document's
`digest` is not drawn. `view` names which picture of the document is drawn
(`EhOsContract.GraphRenderer.View`):

| `view` | Of | The picture |
| --- | --- | --- |
| `:contract` | a contract | its full graph: commands and events in their units, the reactions and timers between them, read models and queries, the actors and external systems around them |
| `{:unit, id}` | a contract | one unit: its state, commands, events and rules, and the scenarios that pin each path |
| `{:lifecycle, id}` | a contract | an aggregate's statuses and the events that move it between them |
| `:process` | a process module | the process and who answers for it, its stages in order, the events each includes with their contracts, those that end a run, its promises with their windows; with its overlay, its runs, how often each event happened and each promise's verdicts |
| `:context_map` | a domain | its subdomains, contexts, external systems and their relations |
| `:system` | a domain | its contracts in their contexts and what flows between them, and its process modules with the contracts whose events each includes and their runs |
| `:landscape` | a landscape (below) | several domains, each a box of its contracts that publish or subscribe, and a card per name on the wire between them |
| `:all`, the default | either | every node and relation: the drawing layer's test bed |

`EhOsContract.GraphRenderer.View.views/1` lists the views a document has, with their titles. The panel is a
sidebar at the right of the window, as tall as it and scrolled inside, one for the page: selecting in one
canvas closes another's, and Escape closes it. It lies over the page, so opening it resizes no canvas. The
reader drags its left edge to set its width, which the browser keeps; it opens
`--eh-os-contract-graph-panel-width` wide, which a host may set. A name in the panel
selects that node, drawn or not. A canvas whose width changes is fitted to it again, unless the reader has
zoomed or panned it; while a pan or a zoom lasts, the graph is a layer of its own, moved without being
painted again.
A domain's actors, which no view draws, are a table of their own, each row selecting its actor in a canvas
of the same document:

```heex
<EhOsContract.GraphRenderer.Actors.table document={@domain_document} canvas="domain-map" />
```

The script is an ES module, `priv/static/eh_os_contract_graph.esm.js`, which the host's own bundle imports
and whose hook it registers:

```js
import { EhOsContractGraph } from "<path to the dependency>/priv/static/eh_os_contract_graph.esm.js"

const liveSocket = new LiveSocket("/live", Socket, { hooks: { EhOsContractGraph } })
```

The stylesheet, `priv/static/eh_os_contract_graph.css`, is imported into the host's or served beside it.
It is drawn on the EmpoweredHouse design system's tokens (`--surface-*`, `--border-*`, `--text-*`, …),
which the host defines, so it follows the host's theme.

Nothing it loads or sets needs more than a Content-Security-Policy of `default-src 'self'`: no `style`
attribute, no inline `<style>`, no `eval`. Positions and sizes live in constructed stylesheets; what moves
on every frame — the zoom, the panel's edge while it is dragged — is a Web Animation, because WebKit styles the
whole page again whenever a stylesheet changes, and Safari stuttered while a stylesheet was written every
frame. The one
style anything sets is d3-zoom's tap highlight on the canvas, on a touch device, through the CSSOM, which the
policy allows.

## Joining applications

An application's domain document says which of its contracts publish an event to other applications, under
which name on the wire, and which subscribe to one by its name; each knows only its own side.
`EhOsContract.GraphRenderer.Landscape.join/1` takes several, each with its application's name, and matches the
two sides by that name into one landscape, which the canvas draws with `view={:landscape}`:

```elixir
landscape = EhOsContract.GraphRenderer.Landscape.join([{"billing", billing}, {"ledger", ledger}])
```

A box per domain holds its contracts that publish or subscribe, and says how many others it has; between the
boxes, a card per name on the wire, with an arrow from each contract that publishes it and to each that
subscribes. Two domains of one application are joined as two applications are. It is how the EHOS Console draws
the applications it sees together, from the domain documents each submitted with its deployment.

## Using it

Drag to pan; Ctrl or ⌘ with the wheel, or a trackpad's pinch, to zoom; the wheel alone scrolls the page. A
click on a card, a group's title, a label or an arrow selects it and opens its panel; a second click, or the panel's close
button, clears it.

## Developing it

The script and the stylesheet are built by `mix assets.build` — esbuild, a downloaded binary, no Node —
and committed under `priv/static/`. The two libraries the script carries, dagre and d3-zoom, are vendored
under `assets/vendor/`; `NOTICE` says what each is, its licence and how it was taken.

Each change to the drawing layer is looked at in a browser, under `default-src 'self'`: the prototype's
defects passed every check that reads the files and showed only on the screen ([`docs/adr/graph-renderer.md`](https://github.com/EmpoweredHouse/eh-os-contract/blob/main/docs/adr/graph-renderer.md)).
On the sandbox host the dashboard draws every document of the test material with it.
