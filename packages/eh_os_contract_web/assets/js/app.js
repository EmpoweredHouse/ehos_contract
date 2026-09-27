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

// Diagrams take their colours from the design system's tokens (the page's computed style), so they
// follow the theme; Mermaid's own themes are light or dark, never these. Its theme engine reads hex
// only, and a token may be rgba() — a hairline is a translucent line — so each is painted over the
// surface it sits on and read back as one opaque colour.
const paint = document.createElement("canvas").getContext("2d", { willReadFrequently: true })

const token = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim()

const solid = (name, over = "--surface-1") => {
  paint.fillStyle = token(over)
  paint.fillRect(0, 0, 1, 1)
  paint.fillStyle = token(name)
  paint.fillRect(0, 0, 1, 1)
  const [r, g, b] = paint.getImageData(0, 0, 1, 1).data
  return "#" + [r, g, b].map((c) => c.toString(16).padStart(2, "0")).join("")
}

// The engine colours some nodes itself, with a `classDef` per state (EhOsContract.Graph). Those in
// this table are status colours — green for observed or ended, amber for waiting — which the design
// system does not have, so each is replaced by tokens: the difference is in the fill and the line,
// and the words on the node say the rest. The v2 graph's Event Storming classes (command, event,
// policy, …) are not here and keep the engine's colours for now; they join this table when that
// palette is decided (docs/adr/dashboard-design-system.md).
const NODE_CLASSES = {
  confirmed: { fill: "--surface-3", stroke: "--border-strong", color: "--text-primary" },
  in_flight: { fill: "--surface-2", stroke: "--text-tertiary", color: "--text-secondary" },
  dead: { fill: "--surface-1", stroke: "--border-strong", color: "--text-tertiary", dash: "4 3" },
  terminal: { fill: "--surface-3", stroke: "--text-secondary", color: "--text-primary" },
  external: { fill: "--surface-1", stroke: "--border-strong", color: "--text-secondary", dash: "4 3" },
}

const classDef = (name, { fill, stroke, color, dash }) =>
  `classDef ${name} fill:${solid(fill)},stroke:${solid(stroke)},color:${solid(color)}` +
  (dash ? `,stroke-dasharray: ${dash}` : "")

const themed = (source) =>
  source.replace(/^(\s*)classDef (\w+) .*$/gm, (line, indent, name) =>
    NODE_CLASSES[name] ? indent + classDef(name, NODE_CLASSES[name]) : line,
  )

const themeMermaid = () => {
  const fontFamily = token("--sans")

  mermaid.initialize({
    startOnLoad: false,
    theme: "base",
    fontFamily,
    themeVariables: {
      darkMode: getComputedStyle(document.documentElement).colorScheme === "dark",
      fontFamily,
      fontSize: "13px",
      background: solid("--surface-1"),
      primaryColor: solid("--surface-2"),
      primaryTextColor: solid("--text-primary"),
      primaryBorderColor: solid("--border-strong"),
      secondaryColor: solid("--surface-2"),
      tertiaryColor: solid("--surface-1"),
      mainBkg: solid("--surface-2"),
      nodeBorder: solid("--border-strong"),
      nodeTextColor: solid("--text-primary"),
      textColor: solid("--text-secondary"),
      titleColor: solid("--text-primary"),
      lineColor: solid("--text-tertiary"),
      clusterBkg: solid("--surface-1"),
      clusterBorder: solid("--border-soft"),
      edgeLabelBackground: solid("--surface-1"),
    },
  })
}

// Every graph on the page, so that a change of theme draws them all again.
const graphs = new Set()

const redraw = () => {
  themeMermaid()
  graphs.forEach((graph) => graph.renderGraph())
}

themeMermaid()
window.matchMedia("(prefers-color-scheme: light)").addEventListener("change", redraw)
new MutationObserver(redraw).observe(document.documentElement, {
  attributes: true,
  attributeFilter: ["data-theme"],
})

// The graph screen's `<pre class="mermaid" phx-hook="MermaidRender">` blocks
// carry the raw diagram source in `data-graph` rather than as text content:
// mermaid replaces a node's content with rendered SVG in place, so a second
// `run` on the same node has nothing left to read unless the source is put
// back first. `updated()` fires on every diff LiveView applies to the
// element (a process switch re-rendering the declared-shape diagram), not
// only on first mount.
const Hooks = {
  MermaidRender: {
    // After the fonts: Mermaid measures its labels once, and a label measured in the fallback
    // font overflows its node when Albert Sans arrives.
    mounted() {
      graphs.add(this)
      document.fonts.ready.then(() => this.renderGraph())
    },
    updated() {
      this.renderGraph()
    },
    destroyed() {
      graphs.delete(this)
    },
    // `data-processed` is Mermaid's mark on a node it has drawn, which it then skips. A LiveView
    // patch drops it, because the server never renders it; a redraw for the theme drops it here.
    renderGraph() {
      this.el.removeAttribute("data-processed")
      this.el.textContent = themed(this.el.dataset.graph)
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
