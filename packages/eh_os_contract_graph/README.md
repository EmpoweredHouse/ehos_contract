# EhOsContract.GraphRenderer

Draws [EhOsContract](../eh_os_contract)'s `graph.v1` documents in a Phoenix LiveView: a card per node, an
arrow per relation, the overlay's numbers from the log on them, and a panel for what is clicked.

The engine says what is in a contract or a domain; this package says how it is drawn. At run time it needs
`phoenix_live_view` (and `phoenix`, which that needs anyway), and `boundary` and `esbuild` come with it as
tools of its own build; it does not depend on the engine: a document is plain data, the same whether it
comes from `EhOsContract.Graph.Document` in the same process or from `GET <mount>/graph/:contract` decoded.
`eh_os_contract_web`'s dashboard draws with it, and so can the EHOS Console.

**Work in progress** (plan E13b). What it draws today is a test bed: every node and every relation of the
document, and a raw panel. The views a reader is shown — which facts go on one picture — and the panels
come next, once they are specified.

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

## Drawing a document

```heex
<.live_component
  module={EhOsContract.GraphRenderer.Canvas}
  id="contract-graph"
  document={@document}
  overlay={@overlay}
/>
```

`document` is a `graph.v1` document with string keys. `overlay`, optional, is an
`eh_os_contract.graph_overlay.v1` of the same document; one whose `document_digest` is not the document's
`digest` is not drawn. The panel opens beside the graph.

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
attribute, no inline `<style>`, no `eval`. Positions and the zoom live in constructed stylesheets. The one
style anything sets is d3-zoom's tap highlight on the canvas, on a touch device, through the CSSOM, which the
policy allows.

## Using it

Drag to pan; Ctrl or ⌘ with the wheel, or a trackpad's pinch, to zoom; the wheel alone scrolls the page. A
click on a card, a label or an arrow selects it and opens its panel; a second click, or the panel's close
button, clears it.

## Developing it

The script and the stylesheet are built by `mix assets.build` — esbuild, a downloaded binary, no Node —
and committed under `priv/static/`. The two libraries the script carries, dagre and d3-zoom, are vendored
under `assets/vendor/`; `NOTICE` says what each is, its licence and how it was taken.

Each change to the drawing layer is looked at in a browser, under `default-src 'self'`: the prototype's
defects passed every check that reads the files and showed only on the screen (`docs/adr/graph-renderer.md`).
On the sandbox host the dashboard draws every document of the test material with it.
