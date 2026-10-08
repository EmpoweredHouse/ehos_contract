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

// A relation from a card to itself — a move a lifecycle does not allow, which leaves a status for the same one —
// as a loop out of the card's side that faces its label and back, its far end just short of the label, which
// stays where dagre made room for it. dagre 3.1.1 centres a loop's points on its label and never touches the
// card with them, so they are not used.
const loop = (card, label) => {
  const [dx, dy] = [label.x - card.x, label.y - card.y]
  const across = Math.abs(dx) / card.width > Math.abs(dy) / card.height
  // u points out of the card towards the label, v along the side the loop leaves from.
  const [ux, uy] = across ? [Math.sign(dx) || 1, 0] : [0, Math.sign(dy) || 1]
  const [vx, vy] = [-uy, ux]
  const edge = across ? card.width / 2 : card.height / 2
  const side = across ? card.height : card.width
  const spread = Math.min(side / 4, 24)
  const centre = Math.max(-side / 2 + spread, Math.min(side / 2 - spread, dx * vx + dy * vy))
  // A cubic whose two controls lie at c out from the side peaks at three quarters of c.
  const gap = Math.abs(across ? dx : dy) - edge - (across ? label.width : label.height) / 2
  const reach = Math.max(16, (gap - 4) / 0.75)
  const at = (along, out) => `${card.x + ux * (edge + out) + vx * along},${card.y + uy * (edge + out) + vy * along}`
  return (
    `M${at(centre - spread, 0)}` +
    `C${at(centre - spread - 12, reach)} ${at(centre + spread + 12, reach)} ${at(centre + spread, 0)}`
  )
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

    // A font that arrives after the first layout changes the cards' sizes: lay them out again. So does a
    // canvas that was hidden when it was first laid out, whose cards measured nothing, once it is shown.
    this.fontsLoaded = () => this.draw()
    document.fonts.addEventListener("loadingdone", this.fontsLoaded)
    this.resized = new ResizeObserver(() => this.draw())
    this.resized.observe(this.canvas)

    this.drawn = Promise.resolve()
    this.draw()
  },

  updated() {
    this.draw()
  },

  destroyed() {
    this.gone = true
    document.fonts.removeEventListener("loadingdone", this.fontsLoaded)
    this.resized.disconnect()
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
  // arrows' classes follow the labels', which is all a selection or a new overlay changes. Fitted to the
  // canvas again only when the cards are other cards — another document, another view — so the reader's
  // zoom stays across a selection, a new overlay and a late font.
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

    const nodes = cards.map(({ id }) => id).join("\n")
    if (nodes !== this.fittedFor) {
      this.fittedFor = nodes
      this.fitted = false
    }
    if (!this.fitted) this.fit()
  },

  lay(cards, labels) {
    // A view with nothing in it: dagre would size an empty graph as -Infinity.
    if (!cards.length) {
      this.layoutSheet.replaceSync(`${this.scope} .ehg-viewport { visibility: visible }`)
      this.el.querySelector(".ehg-arrows").replaceChildren()
      this.arrows = new Map()
      this.size = null
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
    this.size = { width, height }
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
    const arrows = labels.map(({ id, from, to, width, height }) => {
      const edge = graph.edge({ v: from, w: to, name: id })
      const d =
        from === to
          ? loop(graph.node(from), { x: edge.x, y: edge.y, width, height })
          : curve(edge.points)
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

  // The whole graph in view, never larger than its own size, centred. Not while the canvas has no size: the
  // ResizeObserver tries again when it has one.
  fit() {
    const box = this.canvas.getBoundingClientRect()
    if (!this.size || !box.width || !box.height) return
    const { width, height } = this.size
    const k = Math.min(1, (box.width - 32) / width, (box.height - 32) / height)
    const at = zoomIdentity.translate((box.width - width * k) / 2, (box.height - height * k) / 2).scale(k)
    select(this.canvas).call(this.zoom.transform, at)
    this.fitted = true
  },

  zoomed({ x, y, k }) {
    this.zoomSheet.replaceSync(`${this.scope} .ehg-viewport { transform: translate(${x}px, ${y}px) scale(${k}) }`)
  },
}
