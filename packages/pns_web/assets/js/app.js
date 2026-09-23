// The dashboard's client-side code: connect the LiveView socket, and (since
// the graph screen) render Mermaid diagrams the server can only ever hand
// over as text. Everything else — access control and the four questions —
// is server-rendered.
import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

// Mermaid is loaded by its own <script defer> tag in the root layout, not
// `import`ed here, and that is load-bearing, not a style choice: the
// vendored build (assets/js/vendor/mermaid.min.js, copied verbatim by
// `mix assets.build`) relies on a bare top-level `var` becoming a real
// `globalThis` property, which is only true for a classic global script —
// esbuild wraps an `import`ed file in its own scope, which silently breaks
// that assumption and throws deep inside Mermaid's own init code instead of
// failing to import. Loaded first (document order, both `defer`), so the
// bare `mermaid` identifier below resolves through the real global by the
// time this file runs.

mermaid.initialize({ startOnLoad: false })

// The graph screen's `<pre class="mermaid" phx-hook="MermaidRender">` blocks
// carry the raw diagram source in `data-graph` rather than as text content:
// mermaid replaces a node's content with rendered SVG in place, so a second
// `run` on the same node has nothing left to read unless the source is put
// back first. `updated()` fires on every diff LiveView applies to the
// element (a process switch re-rendering the declared-shape diagram), not
// only on first mount.
const Hooks = {
  MermaidRender: {
    mounted() {
      this.renderGraph()
    },
    updated() {
      this.renderGraph()
    },
    renderGraph() {
      this.el.textContent = this.el.dataset.graph
      mermaid.run({ nodes: [this.el] })
    },
  },
}

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
})

liveSocket.connect()
