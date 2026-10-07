// The drawing layer of eh_os_contract_graph (docs/adr/graph-renderer.md, option C). The server renders every
// card and every relation's label in HEEx (EhOsContract.GraphRenderer.Canvas); this hook measures them, lays
// them out with dagre, places them, draws the arrows in SVG, and pans and zooms with d3-zoom. What is selected
// and what the overlay says are classes the server puts on the cards and the labels; the hook copies a label's
// classes onto its arrow and keeps nothing of its own but the layout and the zoom.
//
// Two rules keep it working under a Content-Security-Policy of `default-src 'self'` and under LiveView's
// patches:
//
// * No `style` attribute, ever. The policy refuses one written as markup or through setAttribute, and
//   LiveView takes away, on its next patch, one the server did not render. Every position, size and the zoom
//   live in constructed stylesheets (the CSSOM), which the policy allows and LiveView does not see.
//   test/assets_test.exs holds this file to it.
// * The arrows live in an <svg phx-update="ignore">, so LiveView leaves what is drawn there alone.

import { graphlib, layout } from "../vendor/dagre.esm.js"
import { select, zoom, zoomIdentity } from "../vendor/d3-zoom.esm.js"

const SVG = "http://www.w3.org/2000/svg"

// Room between cards, in pixels: across a rank, between ranks, between arrows, around the graph.
const SPACING = { rankdir: "LR", nodesep: 28, ranksep: 72, edgesep: 14, marginx: 24, marginy: 24 }

let instances = 0

const adopt = () => {
  const sheet = new CSSStyleSheet()
  document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet]
  return sheet
}

// A value inside a quoted attribute selector. A node's id is the client's names and may hold any character.
const quoted = (value) => `"${CSS.escape(value)}"`

const svg = (name, attributes = {}) => {
  const element = document.createElementNS(SVG, name)
  for (const [key, value] of Object.entries(attributes)) element.setAttribute(key, value)
  return element
}

// A path through dagre's points, smoothed as d3's curveBasis smooths it: it starts on the first point and ends
// on the last, which dagre puts on the two cards' borders, so the arrowhead touches the card.
const curve = (points) => {
  const [first, ...rest] = points
  if (rest.length < 2) return `M${first.x},${first.y}` + rest.map((p) => `L${p.x},${p.y}`).join("")

  let [x0, y0, x1, y1] = [first.x, first.y, rest[0].x, rest[0].y]
  let d = `M${x0},${y0}L${(5 * x0 + x1) / 6},${(5 * y0 + y1) / 6}`
  const step = (x, y) => {
    d +=
      `C${(2 * x0 + x1) / 3},${(2 * y0 + y1) / 3} ${(x0 + 2 * x1) / 3},${(y0 + 2 * y1) / 3} ` +
      `${(x0 + 4 * x1 + x) / 6},${(y0 + 4 * y1 + y) / 6}`
    ;[x0, y0, x1, y1] = [x1, y1, x, y]
  }
  rest.slice(1).forEach((p) => step(p.x, p.y))
  step(x1, y1)
  return d + `L${x1},${y1}`
}

// A plain wheel scrolls the page, as it does everywhere else on it; with Ctrl or ⌘ — which is also what a
// trackpad's pinch sends — it zooms. The main button pans.
const gesture = (event) =>
  event.type === "wheel" ? event.ctrlKey || event.metaKey : !event.button && !event.ctrlKey

export const EhOsContractGraph = {
  mounted() {
    this.scope = `#${CSS.escape(this.el.id)}`
    this.head = `ehg-head-${++instances}`
    this.layoutSheet = adopt()
    this.zoomSheet = adopt()
    this.key = null
    this.arrows = new Map()

    this.canvas = this.el.querySelector(".ehg-canvas")
    this.zoom = zoom()
      .scaleExtent([0.1, 2])
      .filter(gesture)
      // A press that moves less than this is a click on a card, not a pan.
      .clickDistance(4)
      .on("zoom", ({ transform }) => this.zoomed(transform))
    select(this.canvas).call(this.zoom).on("dblclick.zoom", null)

    this.el.querySelector(".ehg-arrows").addEventListener("click", (event) => {
      const arrow = event.target.closest("[data-ehg-arrow]")
      if (arrow) this.pushEventTo(this.el, "select", { id: arrow.dataset.ehgArrow })
    })

    // A font that arrives after the first layout changes the cards' sizes: lay them out again.
    this.fontsLoaded = () => this.draw()
    document.fonts.addEventListener("loadingdone", this.fontsLoaded)

    this.drawn = Promise.resolve()
    this.draw()
  },

  updated() {
    this.draw()
  },

  destroyed() {
    this.gone = true
    document.fonts.removeEventListener("loadingdone", this.fontsLoaded)
    const own = [this.layoutSheet, this.zoomSheet]
    document.adoptedStyleSheets = document.adoptedStyleSheets.filter((sheet) => !own.includes(sheet))
  },

  // One draw at a time, each after the one before, so what is left on screen is the last one asked for.
  draw() {
    this.drawn = this.drawn
      .then(() => this.redraw())
      .catch((error) => console.error("eh_os_contract_graph: the graph could not be drawn:", error))
  },

  // Laid out again only when a card or a label appeared, went, or changed its size; otherwise only the
  // arrows' classes follow the labels', which is all a selection or a new overlay changes.
  async redraw() {
    await document.fonts.ready
    if (this.gone) return

    const viewport = this.el.querySelector(".ehg-viewport")
    const cards = [...viewport.querySelectorAll("[data-ehg-node]")].map((el) => ({
      id: el.dataset.ehgNode,
      width: el.offsetWidth,
      height: el.offsetHeight,
    }))
    const labels = [...viewport.querySelectorAll("[data-ehg-relation]")].map((el) => ({
      el,
      id: el.dataset.ehgRelation,
      from: el.dataset.from,
      to: el.dataset.to,
      width: el.offsetWidth,
      height: el.offsetHeight,
    }))

    const key = JSON.stringify([cards, labels.map(({ el, ...label }) => label)])
    if (key !== this.key) {
      this.key = key
      this.lay(cards, labels)
    }
    this.paint(labels)
  },

  lay(cards, labels) {
    // A view with nothing in it: dagre would size an empty graph as -Infinity.
    if (!cards.length) {
      this.layoutSheet.replaceSync(`${this.scope} .ehg-viewport { visibility: visible }`)
      this.el.querySelector(".ehg-arrows").replaceChildren()
      this.arrows = new Map()
      return
    }

    const graph = new graphlib.Graph({ multigraph: true })
    graph.setGraph({ ...SPACING })
    graph.setDefaultEdgeLabel(() => ({}))
    cards.forEach(({ id, width, height }) => graph.setNode(id, { width, height }))
    labels.forEach(({ id, from, to, width, height }) =>
      graph.setEdge({ v: from, w: to, name: id }, { width, height, labelpos: "c" }),
    )
    layout(graph)

    const { width, height } = graph.graph()
    const rules = [`${this.scope} .ehg-viewport { width: ${width}px; height: ${height}px; visibility: visible }`]
    cards.forEach(({ id, width, height }) => {
      const { x, y } = graph.node(id)
      rules.push(`${this.scope} [data-ehg-node=${quoted(id)}] { left: ${x - width / 2}px; top: ${y - height / 2}px }`)
    })
    labels.forEach(({ id, from, to, width, height }) => {
      const { x, y } = graph.edge({ v: from, w: to, name: id })
      rules.push(
        `${this.scope} [data-ehg-relation=${quoted(id)}] { left: ${x - width / 2}px; top: ${y - height / 2}px }`,
      )
    })
    this.layoutSheet.replaceSync(rules.join("\n"))

    this.drawArrows(graph, labels, width, height)
    if (!this.fitted) this.fit(width, height)
  },

  // Each arrow is two paths: the line the reader sees, and a wide invisible one under it that takes the click.
  // No visible style reaches the second — a dash would cut gaps in it, a fill would draw it — so the stylesheet
  // styles them apart (.ehg-line, .ehg-hit).
  drawArrows(graph, labels, width, height) {
    const layer = this.el.querySelector(".ehg-arrows")
    layer.setAttribute("width", width)
    layer.setAttribute("height", height)
    layer.setAttribute("viewBox", `0 0 ${width} ${height}`)

    const marker = svg("marker", {
      id: this.head,
      viewBox: "0 0 10 10",
      refX: "9",
      refY: "5",
      markerWidth: "7",
      markerHeight: "7",
      orient: "auto-start-reverse",
    })
    marker.append(svg("path", { d: "M0,0L10,5L0,10z", class: "ehg-head" }))
    const defs = svg("defs")
    defs.append(marker)

    this.arrows = new Map()
    const arrows = labels.map(({ id, from, to }) => {
      const d = curve(graph.edge({ v: from, w: to, name: id }).points)
      const arrow = svg("g", { class: "ehg-arrow", "data-ehg-arrow": id })
      arrow.append(
        svg("path", { class: "ehg-hit", d }),
        svg("path", { class: "ehg-line", d, "marker-end": `url(#${this.head})` }),
      )
      this.arrows.set(id, arrow)
      return arrow
    })
    layer.replaceChildren(defs, ...arrows)
  },

  paint(labels) {
    labels.forEach(({ el, id }) => {
      const states = [...el.classList].filter((name) => name.startsWith("is-"))
      this.arrows.get(id)?.setAttribute("class", ["ehg-arrow", ...states].join(" "))
    })
  },

  // The whole graph in view, never larger than its own size, centred.
  fit(width, height) {
    const box = this.canvas.getBoundingClientRect()
    if (!box.width || !box.height || !width || !height) return
    const k = Math.min(1, (box.width - 32) / width, (box.height - 32) / height)
    const at = zoomIdentity.translate((box.width - width * k) / 2, (box.height - height * k) / 2).scale(k)
    select(this.canvas).call(this.zoom.transform, at)
    this.fitted = true
  },

  zoomed({ x, y, k }) {
    this.zoomSheet.replaceSync(`${this.scope} .ehg-viewport { transform: translate(${x}px, ${y}px) scale(${k}) }`)
  },
}
