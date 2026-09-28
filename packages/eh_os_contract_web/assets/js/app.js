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
// only, and a token may be rgba() — a hairline is a translucent line — so each is resolved by the
// browser on a hidden element and laid over the surface it sits on, as one opaque colour. Not
// through a canvas: reading pixels back is what anti-fingerprinting browsers block or blur.
const probe = document.createElement("span")
probe.hidden = true
document.body.append(probe)

const token = (name) => {
  const value = getComputedStyle(document.documentElement).getPropertyValue(name).trim()
  if (!value) throw new Error(`the design system defines no ${name}`)
  return value
}

// An invalid colour is ignored by the assignment, not refused, and would leave the previous
// token's colour in place; so the probe is cleared first and the assignment checked.
const channels = (name) => {
  const value = token(name)
  probe.style.color = ""
  probe.style.color = value
  if (!probe.style.color) throw new Error(`${name} is not a colour: ${value}`)
  const color = getComputedStyle(probe).color
  const match = color.match(/^rgba?\(([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?\)$/)
  if (!match) throw new Error(`${name} is not a colour this can read: ${color}`)
  const [r, g, b, a = "1"] = match.slice(1)
  return [+r, +g, +b, +a]
}

const solid = (name, over = "--surface-1") => {
  const [r, g, b, a] = channels(name)
  const base = channels(over)
  return (
    "#" +
    [r, g, b]
      .map((c, i) => Math.round(c * a + base[i] * (1 - a)).toString(16).padStart(2, "0"))
      .join("")
  )
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

// Worked out once per theme, not once per draw.
let classDefs = {}
let fontFamily = "sans-serif"

const themed = (source) =>
  source.replace(/^(\s*)classDef (\w+) .*$/gm, (line, indent, name) =>
    classDefs[name] ? indent + classDefs[name] : line,
  )

const themeMermaid = () => {
  try {
    const sans = token("--sans")

    mermaid.initialize({
      startOnLoad: false,
      theme: "base",
      fontFamily: sans,
      themeVariables: {
        darkMode: getComputedStyle(document.documentElement).colorScheme === "dark",
        fontFamily: sans,
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

    classDefs = Object.fromEntries(
      Object.entries(NODE_CLASSES).map(([name, style]) => [name, classDef(name, style)]),
    )
    fontFamily = sans
  } catch (error) {
    // A token the design system no longer defines, or one in a format this cannot read: the
    // diagrams fall back to Mermaid's own look, and the rest of the page still connects.
    console.error("eh_os_contract_web: the diagrams are not themed:", error)
    classDefs = {}
    mermaid.initialize({ startOnLoad: false })
  }
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

// A drawn diagram under a strict Content-Security-Policy (plan EG3). EHOS serves
// `default-src 'self'`, which refuses every inline style: the `<style>` Mermaid writes into each
// SVG, and every `style` attribute on its elements. Styles set through the CSSOM are not inline
// styles, and the policy leaves them alone. So the SVG Mermaid returns is parsed in a document of
// its own, where no policy applies, and before it joins the page its stylesheet becomes a
// constructed one and each `style` attribute is set again through `element.style`. Only Mermaid's
// own stylesheet, the SVG's child, is kept; a label's text reaches here escaped (Graph.Mermaid).
const sheets = new Map()

const place = (el, svgText) => {
  const svg = new DOMParser().parseFromString(svgText, "text/html").body.firstElementChild
  const styles = [...svg.querySelectorAll("style")]
  const css = styles.filter((style) => style.parentNode === svg).map((style) => style.textContent)
  styles.forEach((style) => style.remove())

  const inline = [svg, ...svg.querySelectorAll("[style]")]
    .filter((node) => node.hasAttribute("style"))
    .map((node) => [node, node.getAttribute("style")])
  inline.forEach(([node]) => node.removeAttribute("style"))

  let sheet = sheets.get(el)
  if (!sheet) {
    sheet = new CSSStyleSheet()
    sheets.set(el, sheet)
    document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet]
  }
  sheet.replaceSync(css.join("\n"))

  el.replaceChildren(document.adoptNode(svg))
  inline.forEach(([node, text]) => (node.style.cssText = text))
}

const forget = (el) => {
  const sheet = sheets.get(el)
  sheets.delete(el)
  document.adoptedStyleSheets = document.adoptedStyleSheets.filter((s) => s !== sheet)
}

// A block's id as Mermaid can put it in a selector and a stylesheet, and a new one on every draw:
// Mermaid first removes the element holding the id it is about to draw, so drawing the id already
// on screen blanked the diagram until the new one arrived, and left it blank if drawing failed.
let draws = 0
const drawId = (el) => `${el.id.replace(/[^A-Za-z0-9_-]/g, "_")}-svg-${++draws}`

// Where Mermaid lays out its scratch copy: off the screen, in the diagrams' font, so a label is
// measured as it is drawn, on a first draw as on every later one. Mermaid's own stylesheet does not
// reach the scratch copy under the policy, and the page's body font is not the diagrams'.
const scratch = () => {
  const box = document.createElement("div")
  box.style.cssText =
    `position: absolute; left: -10000px; top: 0; visibility: hidden; ` +
    `font-family: ${fontFamily}; font-size: 13px`
  document.body.append(box)
  return box
}

// The graph screen's `<pre class="mermaid" phx-hook="MermaidRender" phx-update="ignore">` blocks
// carry the raw diagram source in `data-graph`, and the hook draws it into the block. LiveView
// leaves an ignored block's children alone — without that, every patch took the drawn SVG out of
// every block, changed or not — and still updates its attributes, so `updated()` fires when
// `data-graph` changes (a process switch re-rendering the declared-shape diagram).
const Hooks = {
  MermaidRender: {
    mounted() {
      this.drawn = Promise.resolve()
      graphs.add(this)
      this.renderGraph()
    },
    updated() {
      this.renderGraph()
    },
    destroyed() {
      graphs.delete(this)
      forget(this.el)
    },
    // One draw at a time per diagram, each after the one before: a patch or a change of theme that
    // arrives mid-draw waits for it, so what is left on screen is the last one asked for. Mermaid
    // queues `render` itself, so two diagrams never draw at once.
    renderGraph() {
      this.drawn = this.drawn.then(() => this.draw()).catch((error) => console.error(error))
    },
    // After the fonts its labels need: Mermaid measures a label once, and one measured in the
    // fallback font overflows its node when Albert Sans arrives. Loading with the diagram's own text
    // fetches the latin-ext subset when a label has Polish letters, which `document.fonts.ready`
    // would not: nothing else on the page may have asked for it yet.
    async draw() {
      if (!graphs.has(this)) return
      const source = themed(this.el.dataset.graph)
      await document.fonts.load(`13px ${fontFamily}`, source).catch(() => {})
      if (!graphs.has(this)) return

      const box = scratch()

      try {
        const { svg, bindFunctions } = await mermaid.render(drawId(this.el), source, box)
        if (!graphs.has(this)) return
        place(this.el, svg)
        bindFunctions?.(this.el)
      } catch (error) {
        // What Mermaid drew of its error stays in the scratch box, which goes; the block says so.
        if (graphs.has(this))
          this.el.textContent = "This diagram could not be drawn; the browser's console says why."
        throw error
      } finally {
        box.remove()
      }
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
