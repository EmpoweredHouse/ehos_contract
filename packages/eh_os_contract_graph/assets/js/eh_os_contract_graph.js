// The drawing layer of eh_os_contract_graph (docs/adr/graph-renderer.md, option C). The server renders every
// card, every group's box and every relation's label in HEEx (EhOsContract.GraphRenderer.Canvas); this hook
// measures them, lays them out with dagre in the direction the view names, places them, draws the arrows in
// SVG, and pans and zooms with d3-zoom. What is selected and what the overlay says are classes the server puts
// on the cards and the labels, and an arrow's line and head are attributes of its label; the hook copies both
// onto the arrow and keeps nothing of its own but the layout and the zoom.
//
// Two rules keep it working under a Content-Security-Policy of `default-src 'self'` and under LiveView's
// patches:
//
// * No `style` attribute, ever. The policy refuses one written as markup or through setAttribute, and
//   LiveView takes away, on its next patch, one the server did not render. Every position and size lives in
//   constructed stylesheets (the CSSOM), which the policy allows and LiveView does not see. What moves on every
//   frame — the zoom, the panel's edge while it is dragged — is a Web Animation instead: WebKit styles the whole
//   page again whenever a stylesheet changes, which Chrome does not, so a stylesheet written on every frame made
//   Safari stutter. An animation's value is neither an attribute nor a stylesheet, so the policy allows it and
//   LiveView keeps it. test/assets_test.exs holds this file to it.
// * The arrows live in an <svg phx-update="ignore">, so LiveView leaves what is drawn there alone.

import { graphlib, layout } from "../vendor/dagre.esm.js"
import { select, zoom, zoomIdentity } from "../vendor/d3-zoom.esm.js"

const SVG = "http://www.w3.org/2000/svg"

// The smallest scale a picture starts at: below it a card's words cannot be read. A larger picture starts where
// reading starts, its left edge (or its top, drawn top to bottom), and the reader pans to the rest; "Whole
// picture" fits it all, smaller.
const READABLE = 0.75

// Room between cards, in pixels: across a rank, between ranks, between arrows, around the graph.
const SPACING = { nodesep: 28, ranksep: 72, edgesep: 14, marginx: 24, marginy: 24 }

// The name of an edge dagre lays out only to hold one card before another (below). A relation's id cannot hold
// a NUL (EhOsContract.GraphRenderer.Canvas), so the name is never a relation's.
const HOLD = "\u0000hold"

let instances = 0

const adopt = () => {
  const sheet = new CSSStyleSheet()
  document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet]
  return sheet
}

// The panel is one sidebar for the page, whichever canvas it is of, so its width is the page's: a rule in a
// stylesheet every canvas shares, set while the reader drags the panel's edge and kept in the browser. A browser
// that refuses storage keeps it for the page only.
const WIDTH = "eh_os_contract_graph.panel_width"
let widthSheet = null

// A rule on the panel itself, not the custom property it starts from: a property on :root is inherited by every
// element of the page, which the browser would style again on every move of the drag. Not on a narrow screen,
// where the panel covers the window and has no grip.
const panelWidth = (px) => {
  widthSheet ??= adopt()
  widthSheet.replaceSync(`@media (min-width: 721px) { .ehg-panel { width: ${px}px } }`)
}

const keptWidth = () => {
  try {
    const px = Number(localStorage.getItem(WIDTH))
    return px > 0 ? px : null
  } catch {
    return null
  }
}

const keepWidth = (px) => {
  try {
    localStorage.setItem(WIDTH, String(px))
  } catch {}
}

// `element` held at `value` by a Web Animation that has ended and stays, `animation` reused while it is still
// the element's: what moves on every frame, without a stylesheet or an attribute (see the top of this file).
const hold = (element, animation, value) => {
  const frames = [value, value]
  if (animation && animation.effect.target === element) {
    animation.effect.setKeyframes(frames)
    return animation
  }
  animation?.cancel()
  const held = element.animate(frames, { duration: 0, fill: "forwards" })
  held.persist()
  return held
}

// The window's width without a scrollbar, at whose left a fixed panel's right edge stands.
const across = () => document.documentElement.clientWidth

// As wide as the reader drags it, but never so narrow it says nothing nor so wide no graph is left beside it.
const clampWidth = (px) => Math.round(Math.max(280, Math.min(px, across() - 240)))

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

// Where the line from a box's centre towards a point leaves the box.
const border = (box, toward) => {
  const [dx, dy] = [toward.x - box.x, toward.y - box.y]
  const s = Math.min(dx ? box.width / 2 / Math.abs(dx) : Infinity, dy ? box.height / 2 / Math.abs(dy) : Infinity)
  return Number.isFinite(s) ? { x: box.x + dx * s, y: box.y + dy * s } : { x: box.x, y: box.y }
}

// Whether a gesture has moved the graph from where it started: a scale, or more than a tremor.
const moved = (from, to) => !from || from.k !== to.k || Math.abs(from.x - to.x) + Math.abs(from.y - to.y) > 4

// A plain wheel scrolls the page, as it does everywhere else on it; with Ctrl or ⌘ — which is also what a
// trackpad's pinch sends — it zooms. The main button pans.
const gesture = (event) =>
  event.type === "wheel" ? event.ctrlKey || event.metaKey : !event.button && !event.ctrlKey

export const EhOsContractGraph = {
  mounted() {
    this.scope = `#${CSS.escape(this.el.id)}`
    this.head = `ehg-head-${++instances}`
    this.layoutSheet = adopt()
    this.sizeSheet = adopt()
    this.key = null
    this.arrows = new Map()

    this.canvas = this.el.querySelector(".ehg-canvas")
    this.zoom = zoom()
      .scaleExtent([0.1, 2])
      .filter(gesture)
      // A press that moves less than this is a click on a card, not a pan.
      .clickDistance(4)
      // While a gesture moves the graph it is a layer of its own, which the browser moves and scales without
      // painting the cards and the arrows again on every frame; after it, the layer goes, and the graph is
      // painted once more at the scale it was left at, sharp. A press is a gesture that may not move — a click
      // on a card, with a tremor under the click distance — and leaves the graph as it was: neither a layer
      // nor the reader's view.
      .on("start", ({ transform }) => (this.from = transform))
      .on("zoom", ({ transform, sourceEvent }) => {
        // A wheel, a pinch or a drag is the reader's; a fit is not.
        if (sourceEvent && !this.moving && moved(this.from, transform)) {
          this.moving = true
          this.touched = true
          this.layer()
        }
        this.zoomed(transform)
      })
      .on("end", () => {
        if (!this.moving) return
        this.moving = false
        this.layer()
      })
    select(this.canvas).call(this.zoom).on("dblclick.zoom", null)

    if (!widthSheet && keptWidth()) panelWidth(clampWidth(keptWidth()))
    this.el.addEventListener("pointerdown", (event) => this.resize(event))

    // One panel at a time: a canvas whose selection opens the panel closes the others', hidden at once and
    // gone with the server's answer. And Escape closes it.
    this.closeOthers = ({ detail }) => {
      if (detail === this.el || this.el.dataset.selected === undefined) return
      this.el.querySelector(".ehg-panel")?.setAttribute("hidden", "")
      this.pushEventTo(this.el, "closed", {})
    }
    window.addEventListener("eh_os_contract_graph:opened", this.closeOthers)
    this.escape = (event) => {
      if (event.key === "Escape" && this.el.dataset.selected !== undefined) this.pushEventTo(this.el, "deselect", {})
    }
    document.addEventListener("keydown", this.escape)
    this.announce()

    // The zoom's buttons are the reader's view alone, so the hook answers them, not the server.
    this.el.querySelector(".ehg-bar")?.addEventListener("click", (event) => {
      const button = event.target.closest("[data-ehg-zoom]")
      if (button) this.zoomTo(button.dataset.ehgZoom)
    })

    this.el.querySelector(".ehg-arrows").addEventListener("click", (event) => {
      const arrow = event.target.closest("[data-ehg-arrow]")
      if (arrow) this.pushEventTo(this.el, "select", { id: arrow.dataset.ehgArrow })
    })

    // A font that arrives after the first layout changes the cards' sizes: lay them out again. So does a
    // canvas that was hidden when it was first laid out, whose cards measured nothing, once it is shown.
    this.fontsLoaded = () => this.draw()
    document.fonts.addEventListener("loadingdone", this.fontsLoaded)
    // A canvas whose width changes with the window's is fitted to it again, unless the reader has zoomed or panned
    // it: then their view stays. A change of its height alone is fit()'s own, and asks for nothing.
    this.resized = new ResizeObserver(([entry]) => {
      const width = entry.contentRect.width
      if (width === this.width) return
      this.width = width
      if (!this.touched) this.fitted = false
      this.draw()
    })
    this.resized.observe(this.canvas)

    this.revealed = this.el.dataset.reveal
    this.drawn = Promise.resolve()
    this.draw()
  },

  updated() {
    this.announce()
    // A patch that put another viewport in place, or took the gesture's class away, leaves the zoom where it was.
    if (this.at && this.zooming?.effect.target !== this.viewport()) this.zoomed(this.at)
    if (this.moving) this.layer()
    this.draw()
  },

  destroyed() {
    this.gone = true
    window.removeEventListener("eh_os_contract_graph:opened", this.closeOthers)
    document.removeEventListener("keydown", this.escape)
    document.fonts.removeEventListener("loadingdone", this.fontsLoaded)
    this.resized.disconnect()
    const own = [this.layoutSheet, this.sizeSheet]
    document.adoptedStyleSheets = document.adoptedStyleSheets.filter((sheet) => !own.includes(sheet))
  },

  // A selection made here that was not here before tells the other canvases to close their panels.
  announce() {
    const selected = this.el.dataset.selected
    if (selected !== undefined && selected !== this.selected)
      window.dispatchEvent(new CustomEvent("eh_os_contract_graph:opened", { detail: this.el }))
    this.selected = selected
  },

  // A drag on the panel's edge sets its width, for every panel of the page, and keeps it when the drag ends.
  resize(event) {
    const grip = event.target.closest(".ehg-panel-grip")
    if (!grip || event.button) return
    event.preventDefault()
    grip.setPointerCapture(event.pointerId)
    // While it is dragged, the panel's width is an animation of the panel alone, the last move of each frame; the
    // stylesheet every panel takes its width from is written once, when the drag ends.
    const panel = grip.closest(".ehg-panel")
    let px = null
    let frame = null
    let sizing = null
    const move = (e) => {
      px = clampWidth(across() - e.clientX)
      frame ??= requestAnimationFrame(() => {
        frame = null
        sizing = hold(panel, sizing, { width: `${px}px` })
      })
    }
    const end = () => {
      grip.removeEventListener("pointermove", move)
      grip.removeEventListener("pointerup", end)
      grip.removeEventListener("pointercancel", end)
      if (frame !== null) cancelAnimationFrame(frame)
      if (px !== null) {
        panelWidth(px)
        keepWidth(px)
      }
      sizing?.cancel()
    }
    grip.addEventListener("pointermove", move)
    grip.addEventListener("pointerup", end)
    grip.addEventListener("pointercancel", end)
  },

  // One draw at a time, each after the one before, so what is left on screen is the last one asked for.
  draw() {
    this.drawn = this.drawn
      .then(() => this.redraw())
      .catch((error) => console.error("eh_os_contract_graph: the graph could not be drawn:", error))
  },

  // Laid out again only when a card or a label appeared, went, or changed its size; otherwise only the
  // arrows' classes follow the labels', which is all a selection changes. Fitted to the canvas again when the
  // cards are other cards — another document, another view — or, unless the reader has moved the graph, when
  // they were laid out again or the canvas's width changed: the reader's zoom stays.
  async redraw() {
    await document.fonts.ready
    if (this.gone) return

    const viewport = this.viewport()
    const direction = this.el.dataset.direction === "TB" ? "TB" : "LR"
    const boxes = [...viewport.querySelectorAll("[data-ehg-group]")]
    const present = new Set(boxes.map((el) => el.dataset.ehgGroup))
    const cards = [...viewport.querySelectorAll("[data-ehg-node]")].map((el) => ({
      id: el.dataset.ehgNode,
      group: present.has(el.dataset.group) ? el.dataset.group : null,
      width: el.offsetWidth,
      height: el.offsetHeight,
    }))
    // A group with cards in it is as large as dagre makes it around them, so it is not measured; one with none
    // is laid out as a card of its own, as large as its title.
    const filled = new Set(cards.map(({ group }) => group))
    const groups = boxes.map((el) => {
      const id = el.dataset.ehgGroup
      return filled.has(id) ? { id, filled: true } : { id, filled: false, width: el.offsetWidth, height: el.offsetHeight }
    })
    const labels = [...viewport.querySelectorAll("[data-ehg-relation]")].map((el) => ({
      el,
      id: el.dataset.ehgRelation,
      from: el.dataset.from,
      to: el.dataset.to,
      width: el.offsetWidth,
      height: el.offsetHeight,
    }))

    const key = JSON.stringify([direction, groups, cards, labels.map(({ el, ...label }) => label)])
    if (key !== this.key) {
      this.key = key
      this.lay(direction, groups, cards, labels)
      if (!this.touched) this.fitted = false
    }
    this.paint(labels)

    const nodes = cards.map(({ id }) => id).join("\n")
    if (nodes !== this.fittedFor) {
      this.fittedFor = nodes
      this.fitted = false
      this.touched = false
    }
    if (!this.fitted) this.fit()

    // A card the search selected is brought into view, at the scale the reader has.
    if (this.el.dataset.reveal !== this.revealed) {
      this.revealed = this.el.dataset.reveal
      this.reveal(this.el.dataset.selected)
    }
  },

  lay(direction, groups, cards, labels) {
    // A view with nothing in it: dagre would size an empty graph as -Infinity.
    if (!cards.length) {
      this.layoutSheet.replaceSync(`${this.scope} .ehg-viewport { visibility: visible }`)
      this.sizeSheet.replaceSync("")
      this.tall = null
      this.el.querySelector(".ehg-arrows").replaceChildren()
      this.arrows = new Map()
      this.places = new Map()
      this.size = null
      return
    }

    const graph = new graphlib.Graph({ multigraph: true, compound: true })
    graph.setGraph({ rankdir: direction, ...SPACING })
    graph.setDefaultEdgeLabel(() => ({}))
    cards.forEach(({ id, width, height }) => graph.setNode(id, { width, height }))
    groups.forEach(({ id, filled, width, height }) => graph.setNode(id, filled ? {} : { width, height }))
    cards.forEach(({ id, group }) => group !== null && graph.setParent(id, group))

    // dagre lays out no edge that ends at a group with cards in it. Such a relation — one stage before the next —
    // holds each card of one end before each card of the other instead, and its arrow is drawn between the two
    // boxes (geometry, below).
    const members = new Map(groups.filter(({ filled }) => filled).map(({ id }) => [id, []]))
    cards.forEach(({ id, group }) => members.get(group)?.push(id))
    const boxed = ({ from, to }) => members.has(from) || members.has(to)
    let held = 0
    labels.forEach((label) => {
      const { id, from, to, width, height } = label
      if (!boxed(label)) return graph.setEdge({ v: from, w: to, name: id }, { width, height, labelpos: "c" })
      if (from === to) return
      for (const v of members.get(from) ?? [from])
        for (const w of members.get(to) ?? [to]) if (v !== w) graph.setEdge({ v, w, name: `${HOLD}${++held}` }, {})
    })
    layout(graph)

    const geometry = labels.map((label) => {
      const { id, from, to, width, height } = label
      if (boxed(label)) {
        const [a, b] = [graph.node(from), graph.node(to)]
        const [start, end] = [border(a, b), border(b, a)]
        return { id, d: `M${start.x},${start.y}L${end.x},${end.y}`, x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 }
      }
      const edge = graph.edge({ v: from, w: to, name: id })
      // A label with nothing on it takes no room, and dagre then gives it no place: it sits mid-arrow.
      const at = edge.x === undefined ? edge.points[Math.floor(edge.points.length / 2)] : edge
      const d = from === to ? loop(graph.node(from), { x: at.x, y: at.y, width, height }) : curve(edge.points)
      return { id, d, x: at.x, y: at.y, width, height }
    })

    const { width, height } = graph.graph()
    const rules = [`${this.scope} .ehg-viewport { width: ${width}px; height: ${height}px; visibility: visible }`]
    groups.forEach(({ id }) => {
      const { x, y, width, height } = graph.node(id)
      rules.push(
        `${this.scope} [data-ehg-group=${quoted(id)}] ` +
          `{ left: ${x - width / 2}px; top: ${y - height / 2}px; width: ${width}px; height: ${height}px }`,
      )
    })
    this.places = new Map()
    cards.forEach(({ id, width, height }) => {
      const { x, y } = graph.node(id)
      this.places.set(id, { x, y })
      rules.push(`${this.scope} [data-ehg-node=${quoted(id)}] { left: ${x - width / 2}px; top: ${y - height / 2}px }`)
    })
    labels.forEach(({ id, width, height }, i) => {
      const { x, y } = geometry[i]
      rules.push(
        `${this.scope} [data-ehg-relation=${quoted(id)}] { left: ${x - width / 2}px; top: ${y - height / 2}px }`,
      )
    })
    this.layoutSheet.replaceSync(rules.join("\n"))

    this.drawArrows(geometry, width, height)
    this.size = { width, height }
  },

  // Each arrow is two paths: the line the reader sees, and a wide invisible one under it that takes the click.
  // No visible style reaches the second — a dash would cut gaps in it, a fill would draw it — so the stylesheet
  // styles them apart (.ehg-line, .ehg-hit).
  drawArrows(geometry, width, height) {
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
    const arrows = geometry.map(({ id, d }) => {
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

  // An arrow takes its label's states, and the line and the head the label names.
  paint(labels) {
    labels.forEach(({ el, id }) => {
      const arrow = this.arrows.get(id)
      if (!arrow) return
      const states = [...el.classList].filter((name) => name.startsWith("is-"))
      arrow.setAttribute("class", ["ehg-arrow", ...states].join(" "))
      arrow.setAttribute("data-line", el.dataset.line ?? "solid")
      arrow.setAttribute("data-head", el.dataset.head ?? "arrow")
    })
  },

  // The picture at a readable scale, never larger than its own size: whole and centred when it fits, otherwise from
  // where reading starts. The canvas is as tall as the picture at that scale, so a small picture takes little room;
  // the stylesheet's max-height holds a tall one and its min-height a tiny one. Not while the canvas has no width:
  // the ResizeObserver tries again when it has one.
  fit() {
    const wide = this.canvas.getBoundingClientRect().width
    if (!this.size || !wide) return
    const { width, height } = this.size
    const across = Math.max(READABLE, Math.min(1, (wide - 32) / width))
    const tall = Math.ceil(height * across + 32)
    if (tall !== this.tall) {
      this.tall = tall
      this.sizeSheet.replaceSync(`${this.scope} .ehg-canvas { height: ${tall}px }`)
    }
    const box = this.canvas.getBoundingClientRect()
    const k = Math.max(READABLE, Math.min(1, (box.width - 32) / width, (box.height - 32) / height))
    const start = (room, size) => (size * k <= room - 32 ? (room - size * k) / 2 : 16)
    const at = zoomIdentity.translate(start(box.width, width), start(box.height, height)).scale(k)
    select(this.canvas).call(this.zoom.transform, at)
    this.fitted = true
  },

  // The zoom's buttons: closer, farther, the readable start, or the whole picture however small.
  zoomTo(how) {
    const canvas = select(this.canvas)
    if (how === "read") {
      this.touched = false
      this.fit()
      return
    }
    if (how === "in") canvas.call(this.zoom.scaleBy, 1.25)
    else if (how === "out") canvas.call(this.zoom.scaleBy, 0.8)
    else if (how === "all" && this.size) {
      const box = this.canvas.getBoundingClientRect()
      const { width, height } = this.size
      const k = Math.min(1, (box.width - 32) / width, (box.height - 32) / height)
      canvas.call(
        this.zoom.transform,
        zoomIdentity.translate((box.width - width * k) / 2, (box.height - height * k) / 2).scale(k),
      )
    } else return
    this.touched = true
  },

  // Card `id` in the middle of the canvas, at the scale the reader has, or a readable one.
  reveal(id) {
    const place = id !== undefined && this.places?.get(id)
    if (!place) return
    const box = this.canvas.getBoundingClientRect()
    const k = Math.max(READABLE, this.at?.k ?? 1)
    select(this.canvas).call(
      this.zoom.transform,
      zoomIdentity.translate(box.width / 2 - place.x * k, box.height / 2 - place.y * k).scale(k),
    )
    this.touched = true
  },

  zoomed(at) {
    this.at = at
    const { x, y, k } = at
    this.zooming = hold(this.viewport(), this.zooming, { transform: `translate(${x}px, ${y}px) scale(${k})` })
  },

  // While a gesture lasts the viewport is a layer of its own (.ehg-moving, in the stylesheet). The class is on an
  // element the server renders, so a patch in the middle of a gesture takes it away, and `updated` puts it back.
  layer() {
    this.viewport().classList.toggle("ehg-moving", this.moving === true)
  },

  viewport() {
    return this.el.querySelector(".ehg-viewport")
  },
}
