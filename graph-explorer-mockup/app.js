// A mock-up of one explorable graph (graph-explorer-plan.md, step 2): the test set's real graph.v1 documents and
// overlays, drawn with dagre and d3-zoom, as today's renderer is. Not the product: a page to see how it reads.
"use strict"
;(() => {
  const D = window.DATA
  const viewport = document.getElementById("viewport")
  const world = document.getElementById("world")
  const measureBox = document.getElementById("measure")
  const SVGNS = "http://www.w3.org/2000/svg"

  const h = (tag, cls, text) => {
    const e = document.createElement(tag)
    if (cls) e.className = cls
    if (text != null) e.textContent = text
    return e
  }
  const sv = (tag, attrs) => {
    const e = document.createElementNS(SVGNS, tag)
    for (const k in attrs || {}) e.setAttribute(k, attrs[k])
    return e
  }
  const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
  const nextFrame = () => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)))
  const circled = (i) => "①②③④⑤⑥⑦⑧⑨⑩"[i - 1] || `(${i})`

  // ------------------------------------------------------------------ words

  const KIND = {
    contract: ["Contract", "▣"], unit: ["Unit", "◫"], command: ["Command", "▶"], event: ["Event", "◆"],
    invariant: ["Rule", "§"], constraint: ["Constraint", "§"], state: ["State", "≡"], policy: ["Policy", "↳"],
    process_manager: ["Process manager", "⟳"], effect: ["Effect", "⇢"], timer: ["Timer", "⏱"],
    read_model: ["Read model", "▤"], query: ["Query", "?"], domain_service: ["Domain service", "ƒ"],
    actor: ["Actor", "☺"], external: ["External system", "⬡"], publication: ["From another app", "✉"],
    process: ["Process", "⟿"], domain: ["Domain", "◎"],
  }
  const kindWord = (e) => {
    if (!e) return ""
    if (e.kind === "unit") return e.facts?.unit_kind === "dcb" ? "Consistency boundary" : "Aggregate"
    if (e.kind === "actor") return e.facts?.actor_kind === "system" ? "System actor" : "Actor"
    return (KIND[e.kind] || [e.kind])[0]
  }
  const icon = (e) => (KIND[e.kind] || ["", ""])[1]

  const VERB = {
    emits: "emits", refused_on: "may refuse", constrained_by: "constrained by", may_issue: "issues",
    may_record: "records", may_ask: "asks", builds: "builds", handled_by: "", starts: "starts", ends: "ends",
    sets: "sets", cancels: "cancels", fires: "fires", issues: "issues", projected_into: "projected into",
    reads: "read by", consulted_by: "consulted", calls: "calls", depends_on: "depends on", backed_by: "stands for",
    received_as: "arrives as",
  }
  const STYLE = {
    refers_to: "dotted", depends_on: "dotted", backed_by: "dotted", includes: "dotted",
    refused_on: "rule", constrained_by: "rule",
    builds: "read", projected_into: "read", reads: "read", consulted_by: "read", may_ask: "read",
  }
  // What "follows" in a trace: the chain of causes. "Who reads it" is behind a switch.
  const CAUSE = new Set(["emits", "handled_by", "starts", "ends", "sets", "cancels", "fires", "issues", "received_as", "calls", "may_issue", "may_record"])
  const READING = new Set(["builds", "projected_into", "consulted_by", "reads", "may_ask", "depends_on"])

  // ------------------------------------------------------------------ model: one element, one home

  const M = {
    el: new Map(), kids: new Map(), rels: [], alias: new Map(), relOv: new Map(), nodeOv: new Map(),
    scen: new Map(), undeclared: [], ctx: new Map(), sd: new Map(), proc: new Map(),
    byFrom: new Map(), byTo: new Map(), anc: new Map(),
  }
  const add = (e) => {
    M.el.set(e.id, e)
    if (e.parent) {
      if (!M.kids.has(e.parent)) M.kids.set(e.parent, [])
      M.kids.get(e.parent).push(e.id)
    }
    return e
  }
  // An event consumed from a sibling is a link to its one card, never a card of its own.
  const res = (id) => (M.alias.has(id) ? M.alias.get(id).to : id)
  const short = (name) => String(name).replace(/^[^.]*\./, "")
  const labelOf = (id) => {
    const e = M.el.get(id)
    return e ? e.label || e.name : id
  }

  function loadContract(cid, doc, overlay, root) {
    if (!M.el.has(cid)) add({ id: cid, kind: "contract", label: short(doc.contract), name: doc.contract, parent: root, context: doc.context, facts: {} })
    const n = doc.nodes
    for (const c of n.context || []) if (!M.ctx.has(c.id)) M.ctx.set(c.id, c)
    for (const u of n.unit || []) {
      add({ id: u.id, kind: "unit", label: u.label || u.name, name: u.name, parent: cid, facts: u })
      add({ id: u.id + "#state", kind: "state", label: "State", name: u.name, parent: u.id, facts: u })
    }
    for (const c of n.command || []) add({ id: c.id, kind: "command", label: c.label || c.name, name: c.name, parent: c.unit || cid, facts: c })
    for (const e of n.event || []) {
      if (e.declared_as) {
        M.alias.set(e.id, { to: e.declared_as, as: e.name, contract: cid })
        continue
      }
      add({ id: e.id, kind: "event", label: e.label || e.name, name: e.name, parent: e.unit || cid, inbox: !e.unit, facts: e })
    }
    for (const i of n.invariant || []) add({ id: i.id, kind: "invariant", label: i.label || i.name, name: i.name, parent: i.of || cid, facts: i })
    for (const c of n.constraint || []) {
      const cmd = (n.command || []).find((x) => x.id === c.of)
      add({ id: c.id, kind: "constraint", label: c.label || c.name, name: c.name, parent: (cmd && cmd.unit) || cid, facts: c })
      M.rels.push({ id: null, type: "constrained_by", from: c.of, to: c.id, contract: cid, facts: {} })
    }
    for (const k of ["policy", "process_manager", "effect", "read_model", "query", "domain_service", "timer"])
      for (const x of n[k] || []) add({ id: x.id, kind: k, label: x.label || x.name, name: x.name, parent: cid, facts: x })
    for (const a of n.actor || []) if (!M.el.has(a.id)) add({ id: a.id, kind: "actor", label: a.label || a.name, name: a.name, parent: root, participant: true, facts: a })
    for (const x of n.external || []) if (!M.el.has(x.id)) add({ id: x.id, kind: "external", label: x.label || x.name, name: x.name, parent: root, participant: true, facts: x })
    for (const p of n.publication || []) if (!M.el.has(p.id)) add({ id: p.id, kind: "publication", label: p.label || p.name, name: p.name, parent: root, participant: true, facts: p })
    for (const [type, list] of Object.entries(doc.relations || {}))
      for (const r of list) {
        if (type === "transition" || type === "enters" || type === "allowed_in") continue
        let from = r.from
        let to = r.to
        if (type === "builds" || type === "consulted_by") to = r.to + "#state"
        if (type === "reads") [from, to] = [r.to, r.from]
        M.rels.push({ id: r.id, type, from, to, contract: cid, facts: r })
      }
    if (overlay) {
      for (const [id, v] of Object.entries(overlay.relations || {})) M.relOv.set(id, v)
      for (const [id, v] of Object.entries(overlay.nodes || {})) M.nodeOv.set(id, v)
      for (const u of overlay.observed?.relations?.undeclared || []) M.undeclared.push({ ...u, contract: cid })
    }
    for (const list of Object.values(doc.scenarios || {}))
      for (const sc of list) for (const rid of sc.covers || []) M.scen.set(rid, (M.scen.get(rid) || 0) + 1)
  }

  function loadAll() {
    const dom = D.domain
    add({ id: "domain", kind: "domain", label: dom.name, name: dom.name, parent: null, facts: dom })
    for (const s of dom.nodes.subdomain || []) M.sd.set(s.id, s)
    for (const c of dom.nodes.context || []) M.ctx.set(c.id, c)
    for (const c of dom.nodes.contract || []) add({ id: c.id, kind: "contract", label: c.label || short(c.name), name: c.name, parent: "domain", context: c.context, facts: c })
    for (const x of dom.nodes.external || []) add({ id: x.id, kind: "external", label: x.label || x.name, name: x.name, parent: "domain", participant: true, facts: x })
    for (const p of dom.nodes.publication || []) add({ id: p.id, kind: "publication", label: p.label || p.name, name: p.name, parent: "domain", participant: true, facts: p })
    for (const a of dom.nodes.actor || []) add({ id: a.id, kind: "actor", label: a.label || a.name, name: a.name, parent: "domain", participant: true, facts: a })
    for (const p of dom.nodes.process || []) add({ id: p.id, kind: "process", label: p.label || p.name, name: p.name, parent: "domain", facts: p })
    for (const [cid, c] of Object.entries(D.contracts)) loadContract(cid, c.doc, c.overlay, "domain")
    // "Who holds whose number": drawn from the unit's contract to the one holding its number.
    for (const r of dom.relations.refers_to || []) M.rels.push({ id: r.id, type: "refers_to", from: r.to, to: r.from, units: r.units, facts: r })
    for (const r of dom.relations.includes || []) M.rels.push({ id: r.id, type: "includes", from: r.from, to: r.to, facts: r })
    for (const [pid, p] of Object.entries(D.processes)) M.proc.set(pid, p)
    add({ id: "scale", kind: "domain", label: "Scale test (AppUnite)", name: "scale", parent: null, facts: {} })
    loadContract("contract:" + D.scale.contract, D.scale, null, "scale")
    for (const r of M.rels) {
      r.a = res(r.from)
      r.b = res(r.to)
      if (!M.byFrom.has(r.a)) M.byFrom.set(r.a, [])
      M.byFrom.get(r.a).push(r)
      if (!M.byTo.has(r.b)) M.byTo.set(r.b, [])
      M.byTo.get(r.b).push(r)
    }
  }

  const ancestors = (id) => {
    if (M.anc.has(id)) return M.anc.get(id)
    const a = []
    let p = id
    while (p != null && a.length < 12) {
      a.push(p)
      p = M.el.get(p)?.parent ?? null
    }
    M.anc.set(id, a)
    return a
  }
  const under = (id, x) => ancestors(id).includes(x)
  const contractOf = (id) => ancestors(id).find((a) => M.el.get(a)?.kind === "contract")
  const subdomainOf = (cid) => {
    const c = M.el.get(cid)
    const cx = c && M.ctx.get(c.context)
    return cx ? M.sd.get(cx.subdomain) : null
  }
  const countKinds = (id) => {
    const c = {}
    const walk = (x) => {
      for (const k of M.kids.get(x) || []) {
        const e = M.el.get(k)
        c[e.kind] = (c[e.kind] || 0) + 1
        walk(k)
      }
    }
    walk(id)
    return c
  }
  const descendants = (id) => {
    const out = [id]
    const walk = (x) => (M.kids.get(x) || []).forEach((k) => (out.push(k), walk(k)))
    walk(id)
    return out
  }

  // ------------------------------------------------------------------ the log's numbers

  const ovOf = (r) => (r.id ? M.relOv.get(r.id) : null)
  function driftOf(id) {
    const e = M.el.get(id)
    const test = e.kind === "contract" ? (r) => r.contract === id : (r) => under(r.a, id) || under(r.b, id)
    const d = { never: 0, fails: 0, waits: 0, undeclared: 0 }
    for (const r of M.rels) {
      if (!test(r)) continue
      const o = ovOf(r)
      if (!o) continue
      if (o.untraversed) d.never++
      if (o.fails) d.fails++
      if (o.waits) d.waits++
    }
    d.undeclared = M.undeclared.filter((u) => (e.kind === "contract" ? u.contract === id : under(u.event, id))).length
    return d
  }
  // A unit records only when it has events and none of its commands can be refused (EhOsContract.Refusals).
  function recordsOnly(uid) {
    const kids = M.kids.get(uid) || []
    const hasEvent = kids.some((k) => M.el.get(k).kind === "event")
    const refuses = kids.some((k) => M.el.get(k).kind === "command" && (M.byFrom.get(k) || []).some((r) => r.type === "refused_on"))
    return hasEvent && !refuses
  }
  function procInfo(pid) {
    const p = M.proc.get(pid)
    if (!p) return null
    const ov = p.overlay.nodes || {}
    const promises = (p.doc.nodes.promise || []).map((pr) => ({ pr, v: ov[pr.id] || {} }))
    return {
      doc: p.doc, ov, runs: ov[pid]?.runs ?? 0, promises,
      broken: promises.reduce((s, x) => s + (x.v.violated || 0), 0),
      pending: promises.reduce((s, x) => s + (x.v.pending || 0), 0),
      contracts: (p.doc.nodes.contract || []).map((c) => c.id),
      events: (p.doc.nodes.event || []).map((e) => e.id),
      stages: p.doc.nodes.stage || [],
    }
  }
  const inAnyProcess = (cid) => [...M.proc.keys()].some((pid) => procInfo(pid).contracts.includes(cid))

  // ------------------------------------------------------------------ settings (the open choices, as switches)

  const DEFAULTS = { deeper: "flight", around: "doors", subdomains: "frames", start: "contracts", arrows: "selected", rules: false, actors: true, numbers: true, readers: false }
  const SET = { ...DEFAULTS }
  try {
    Object.assign(SET, JSON.parse(localStorage.getItem("graph-mockup") || "{}"))
  } catch {}
  const saveSet = () => {
    try {
      localStorage.setItem("graph-mockup", JSON.stringify(SET))
    } catch {}
  }
  let OVR = {} // a view's own override of a layer, e.g. focus shows the rules
  const layer = (k) => (k in OVR ? OVR[k] : SET[k])

  // ------------------------------------------------------------------ views: a home's inside, its neighbours

  const isMapF = (F) => M.el.get(F)?.kind === "domain"
  function shown(e, F) {
    if (!e) return false
    const map = isMapF(F)
    switch (e.kind) {
      case "actor": return !map && layer("actors")
      case "invariant":
      case "constraint": return layer("rules")
      case "process": return map && SET.start !== "contracts"
      case "contract": return !(map && SET.start === "processes" && inAnyProcess(e.id))
      case "external":
      case "publication": return !(map && SET.start === "processes")
      default: return true
    }
  }
  function relShown(r, F) {
    const map = isMapF(F)
    if (r.type === "includes") return map && SET.start === "both"
    if (r.type === "refers_to") return map && SET.start !== "processes" && SET.numbers
    if (r.type === "backed_by") return !map
    return true
  }
  // Where an element shows when the reader stands in F: the child of F it is inside, a participant (actor,
  // external system, another application) drawn beside, or a door: the neighbour at a level above it is in.
  function lift(id, F) {
    const chain = ancestors(id)
    const i = chain.indexOf(F)
    if (i > 0) return { node: chain[i - 1], role: "inside" }
    if (i === 0) return null
    const e = M.el.get(id)
    if (!e) return null
    if (e.participant) return { node: id, role: "participant" }
    const fa = ancestors(F)
    for (let k = 1; k < fa.length; k++) {
      const j = chain.indexOf(fa[k])
      if (j > 0) return { node: chain[j - 1], role: "door" }
    }
    return null
  }
  const endShown = (L, F) => L.role === "door" || shown(M.el.get(L.node), F)
  // Every event builds its unit's state, and reading through a door (a read model of a sibling) is no step of
  // the chain: both are drawn only with the "who reads it" layer.
  const readingHidden = (r, A, B) =>
    !layer("readers") && (r.type === "builds" || (READING.has(r.type) && r.type !== "consulted_by" && (A.role === "door" || B.role === "door")))

  function computeView(F, over) {
    OVR = over || {}
    try {
      const fe = M.el.get(F)
      if (fe.kind === "process") return processView(F)
      const map = fe.kind === "domain"
      const nodes = new Map()
      const edges = new Map()
      const put = (id, role, extra) => {
        if (!nodes.has(id)) nodes.set(id, { id, role, ...extra })
        return nodes.get(id)
      }
      for (const k of M.kids.get(F) || []) if (shown(M.el.get(k), F)) put(k, "inside")
      for (const r of M.rels) {
        if (!relShown(r, F)) continue
        const A = lift(r.a, F)
        const B = lift(r.b, F)
        if (!A || !B || A.node === B.node) continue
        if (A.role !== "inside" && B.role !== "inside") continue
        if (!endShown(A, F) || !endShown(B, F)) continue
        if (readingHidden(r, A, B)) continue
        const from = A.role === "door" ? "in:" + A.node : A.node
        const to = B.role === "door" ? "out:" + B.node : B.node
        if (A.role === "door") put(from, "door-in", { target: A.node })
        else if (A.role === "participant") put(from, "participant")
        if (B.role === "door") put(to, "door-out", { target: B.node })
        else if (B.role === "participant") put(to, "participant")
        const style = STYLE[r.type] || "flow"
        const key = from + "→" + to + "|" + style
        if (!edges.has(key)) edges.set(key, { id: key, from, to, style, rels: [] })
        edges.get(key).rels.push(r)
      }
      if (map && SET.start === "processes") processLinks(nodes, edges)
      if (map && SET.start !== "processes" && F === "domain")
        for (const cx of D.domain.nodes.context)
          if (![...nodes.keys()].some((id) => M.el.get(id)?.context === cx.id))
            nodes.set("empty:" + cx.id, { id: "empty:" + cx.id, role: "inside", placeholder: true, context: cx.id })
      return { F, kind: map ? "map" : fe.kind, nodes, edges }
    } finally {
      OVR = {}
    }
  }

  // Processes as nodes (decision 1's other answer): lines between them are computed, never declared — a shared
  // event, or else a shared contract.
  function processLinks(nodes, edges) {
    const pids = [...nodes.keys()].filter((id) => M.el.get(id)?.kind === "process")
    for (let i = 0; i < pids.length; i++)
      for (let j = i + 1; j < pids.length; j++) {
        const a = procInfo(pids[i])
        const b = procInfo(pids[j])
        const shared = a.events.filter((e) => b.events.includes(e))
        const sharedC = a.contracts.filter((c) => b.contracts.includes(c))
        if (!shared.length && !sharedC.length) continue
        const key = pids[i] + "→" + pids[j] + "|link"
        edges.set(key, {
          id: key, from: pids[i], to: pids[j], style: shared.length ? "link" : "dotted", rels: [], noArrow: true,
          names: shared.length ? shared.map((e) => "shares " + (M.el.get(e)?.name || e)) : sharedC.map((c) => "both in " + labelOf(c)),
        })
      }
  }

  // A process opened: its declared shape, the picture the process pull request (#301) draws.
  function processView(pid) {
    const info = procInfo(pid)
    const nodes = new Map()
    const edges = new Map()
    const card = pid + "#card"
    nodes.set(card, { id: card, role: "inside", ref: pid, procCard: true })
    for (const a of info.doc.nodes.actor || []) nodes.set(a.id, { id: a.id, role: "participant" })
    for (const ev of info.doc.nodes.event || []) nodes.set(ev.id, { id: ev.id, role: "inside", stage: ev.stage, terminal: !!ev.terminal })
    const R = info.doc.relations
    for (const pr of info.doc.nodes.promise || []) {
      const opens = (R.opens || []).filter((r) => r.to === pr.id).map((r) => r.from)
      const keeps = (R.fulfils || []).filter((r) => r.to === pr.id).map((r) => r.from)
      const orElse = (R.or_else || []).filter((r) => r.to === pr.id).map((r) => r.from)
      for (const o of opens) {
        for (const f of keeps) edges.set(`p:${pr.id}:${f}`, { id: `p:${pr.id}:${f}`, from: o, to: f, style: "promise", promise: pr, rels: [] })
        for (const f of orElse) edges.set(`o:${pr.id}:${f}`, { id: `o:${pr.id}:${f}`, from: o, to: f, style: "orelse", promise: pr, rels: [] })
      }
    }
    for (const r of R.accountable_for || [])
      edges.set("acc:" + r.from, { id: "acc:" + r.from, from: r.from, to: card, style: "dotted", rels: [], names: ["accountable"] })
    return { F: pid, kind: "process", nodes, edges, info }
  }

  // Focus (#297): the card and what is directly tied to it, the rest put away. The trace's one step, hiding.
  function focusView(V, id) {
    const keep = new Set([id])
    for (const e of V.edges.values()) {
      if (e.from === id) keep.add(e.to)
      if (e.to === id) keep.add(e.from)
    }
    return {
      ...V,
      nodes: new Map([...V.nodes].filter(([k]) => keep.has(k))),
      edges: new Map([...V.edges].filter(([, e]) => keep.has(e.from) && keep.has(e.to))),
      focused: id,
    }
  }

  // ------------------------------------------------------------------ cards

  function summary(e) {
    const c = countKinds(e.id)
    if (e.kind === "contract") {
      const reactions = (c.policy || 0) + (c.process_manager || 0) + (c.effect || 0)
      const reads = (c.read_model || 0) + (c.query || 0)
      return [
        plural(c.unit || 0, "unit", "units"), plural(c.command || 0, "command", "commands"), plural(c.event || 0, "event", "events"),
        reactions && plural(reactions, "reaction", "reactions"), reads && plural(reads, "read model or query", "read models and queries"),
      ].filter(Boolean).join(" · ")
    }
    if (e.kind === "unit") {
      const rules = (c.invariant || 0) + (c.constraint || 0)
      return [plural(c.command || 0, "command", "commands"), plural(c.event || 0, "event", "events"), rules && plural(rules, "rule", "rules")].filter(Boolean).join(" · ")
    }
    return ""
  }
  function marksFor(e) {
    const m = h("div", "marks")
    const add1 = (cls, text, title) => {
      const s = h("span", "mark " + cls, text)
      if (title) s.title = title
      m.append(s)
    }
    const d = driftOf(e.id)
    if (d.never) add1("never", `${d.never} never taken`, "Declared paths the log never saw taken")
    if (d.undeclared) add1("undeclared", `${d.undeclared} undeclared`, "Moves that happened but the contract does not declare")
    if (d.fails) add1("fail", `${d.fails} failing`, "Steps that fail now")
    if (d.waits) add1("wait", `${d.waits} waiting`, "Timers or effects still waiting")
    const core = subdomainOf(contractOf(e.id))?.type === "core"
    if (e.kind === "unit" && recordsOnly(e.id)) add1("ro" + (core ? " core" : ""), core ? "records only · in the core" : "records only", "No command of it can be refused: it decides nothing")
    if (e.kind === "contract") {
      const ro = (M.kids.get(e.id) || []).filter((k) => M.el.get(k).kind === "unit" && recordsOnly(k)).length
      if (ro) add1("ro" + (core ? " core" : ""), `${plural(ro, "unit", "units")} records only`, "A unit whose commands cannot be refused")
    }
    return m.childNodes.length ? m : null
  }
  function head(e, extra) {
    const hd = h("div", "head")
    hd.append(h("span", "badge", `${icon(e)} ${kindWord(e)}`))
    if (extra) hd.append(extra)
    return hd
  }
  function enterButton(id, text) {
    const b = h("button", "enter", text || "▸ enter")
    b.dataset.enter = id
    b.title = "Enter (or double-click the card)"
    return b
  }
  function boxCard(e) {
    const c = h("div", `card box k-${e.kind}`)
    c.append(head(e, enterButton(e.id)))
    c.append(h("div", "title", e.label))
    if (e.kind === "contract") c.append(h("div", "name", e.name))
    c.append(h("div", "sub", summary(e)))
    const m = marksFor(e)
    if (m) c.append(m)
    return c
  }
  function procCard(pid, opened) {
    const e = M.el.get(pid)
    const info = procInfo(pid)
    const c = h("div", "card box k-process")
    c.append(head(e, opened ? null : enterButton(pid, "▸ open")))
    c.append(h("div", "title", e.label))
    c.append(h("div", "name", e.name))
    const dl = e.facts.deadline || info.doc.nodes.process?.[0]?.deadline
    c.append(h("div", "sub", [plural(info.stages.length, "stage", "stages"), plural(info.contracts.length, "contract", "contracts"), plural(info.runs, "run", "runs"), dl && `deadline ${dl.amount} ${dl.unit}${dl.amount > 1 ? "s" : ""}`].filter(Boolean).join(" · ")))
    const m = h("div", "marks")
    for (const { pr, v } of info.promises) {
      if (v.violated) m.append(h("span", "mark broken", `${v.violated} broken`))
      if (v.pending) m.append(h("span", "mark wait", `${v.pending} pending`))
      if (!v.violated && v.satisfied) m.append(h("span", "mark ok", `${v.satisfied} kept`))
    }
    if (m.childNodes.length) c.append(m)
    return c
  }
  function leafCard(e, n, V) {
    const c = h("div", `card k-${e.kind}`)
    const occ = M.nodeOv.get(e.id)?.occurrences ?? (V.kind === "process" ? V.info.ov[e.id]?.occurrences : undefined)
    c.append(head(e, occ != null ? h("span", "count", "×" + occ) : null))
    if (e.kind === "state") {
      c.append(h("div", "title", "State"))
      const f = (e.facts.state || []).map((x) => x.name)
      c.append(h("div", "name", f.slice(0, 4).join(", ") + (f.length > 4 ? ` +${f.length - 4}` : "")))
      return c
    }
    c.append(h("div", "title", e.label))
    if (e.name && e.name !== e.label) c.append(h("div", "name", e.name))
    const f = e.facts || {}
    const sub = []
    if (e.kind === "timer") sub.push(f.at ? `fires at its state's ${f.at}` : f.wait ? `fires after ${f.wait.amount} ${f.wait.unit}` : "")
    if (e.kind === "event" && e.inbox) sub.push("arrives in the inbox")
    if (["policy", "process_manager", "effect", "read_model"].includes(e.kind) && f.delivery === "at_least_once") sub.push("after the transaction")
    if (e.kind === "external" && f.expected_latency) sub.push(`answers in ~${f.expected_latency.amount} ${f.expected_latency.unit}`)
    if (sub.filter(Boolean).length) c.append(h("div", "sub", sub.filter(Boolean).join(" · ")))
    if (V.kind === "process" && e.kind === "event") {
      if (n.terminal) c.classList.add("terminal")
      const ft = h("div", "foot", "in " + labelOf(contractOf(e.id)) + " ")
      const b = h("button", "enter", "▸")
      b.dataset.enterContract = e.id
      b.title = "Enter its contract"
      ft.append(b)
      c.append(ft)
    }
    return c
  }
  function doorCard(n) {
    const t = M.el.get(n.target)
    const c = h("div", `card door ${n.role}`)
    const hd = h("div", "head")
    hd.append(h("span", "badge", n.role === "door-in" ? "⇤ comes from" : "goes to ⇥"))
    c.append(hd)
    c.append(h("div", "title", t ? t.label : n.target))
    const where = t && t.kind !== "contract" ? " · " + labelOf(contractOf(t.id)) : ""
    c.append(h("div", "name", kindWord(t) + where))
    c.title = "Go there"
    return c
  }
  function makeCard(n, V) {
    if (n.role === "door-in" || n.role === "door-out") return doorCard(n)
    if (n.placeholder) {
      const c = h("div", "card placeholder")
      c.append(h("div", "title", "no contract"))
      return c
    }
    if (n.procCard) return procCard(n.ref, true)
    const e = M.el.get(n.id)
    if (e.kind === "contract" || e.kind === "unit") return boxCard(e)
    if (e.kind === "process") return procCard(e.id, false)
    return leafCard(e, n, V)
  }

  // ------------------------------------------------------------------ arrows and their labels

  function ovClass(e) {
    const o = e.rels.map(ovOf).filter(Boolean)
    if (!o.length) return ""
    if (o.some((x) => x.fails)) return "fails"
    if (o.every((x) => x.untraversed)) return "never"
    if (o.some((x) => x.waits)) return "waits"
    return ""
  }
  function carried(r, e) {
    const A = M.el.get(r.a)
    const B = M.el.get(r.b)
    if (r.type === "calls") return "calls " + (r.facts?.operation || "")
    if (A?.kind === "event") {
      const al = M.alias.get(r.from)
      return al && al.as !== A.name ? `${A.name} → ${al.as}` : A.name
    }
    if (B?.kind === "event") return B.name
    if (e.to !== r.b && B) return B.name
    if (e.from !== r.a && A) return A.name
    return VERB[r.type] || r.type
  }
  function edgeLabel(e, V) {
    if (e.style === "promise" || e.style === "orelse") {
      if (e.style === "orelse") return { parts: [{ t: "or else" }], cls: "promise" }
      const pr = e.promise
      const v = V.info.ov[pr.id] || {}
      const w = pr.within ? `within ${pr.within.amount} ${pr.within.unit}${pr.within.amount > 1 ? "s" : ""}` : "promise"
      const parts = [{ t: w }]
      if (v.instances != null) parts.push({ t: ` · ${v.satisfied || 0} kept · ${v.violated || 0} broken · ${v.pending || 0} pending`, cls: "n" })
      return { parts, cls: "promise" + (v.violated ? " broken" : "") }
    }
    if (e.names) return { parts: [{ t: e.names.join(", ") }] }
    const rels = e.rels
    if (!rels.length) return null
    const r0 = rels[0]
    if (r0.type === "refers_to") return { parts: [{ t: "number of " + (r0.units || []).join(", ") }] }
    if (r0.type === "includes") return { parts: [{ t: "includes" }] }
    const direct = rels.length === 1 && e.from === r0.a && e.to === r0.b
    const parts = []
    if (direct) {
      if (VERB[r0.type]) parts.push({ t: VERB[r0.type] })
    } else {
      const names = []
      for (const r of rels) {
        const nm = carried(r, e)
        if (nm && !names.includes(nm)) names.push(nm)
      }
      if (names.length) parts.push({ t: names.length > 2 ? names.slice(0, 2).join(", ") + ` +${names.length - 2}` : names.join(", ") })
    }
    const ovs = rels.map(ovOf).filter(Boolean)
    if (ovs.length) parts.push({ t: (parts.length ? "  " : "") + "×" + ovs.reduce((s, o) => s + (o.taken ?? o.count ?? 0), 0), cls: "n" })
    if (direct && ["emits", "refused_on", "handled_by", "issues", "fires", "starts"].includes(r0.type)) {
      const sc = M.scen.get(r0.id) || 0
      parts.push({ t: ` · ${plural(sc, "scenario", "scenarios")}`, cls: "sc" })
    }
    return parts.length ? { parts, cls: ovClass(e) } : null
  }
  function labelEl(lab) {
    const l = h("div", "elabel " + (lab.cls || ""))
    for (const p of lab.parts) l.append(p.cls ? h("span", p.cls, p.t) : document.createTextNode(p.t))
    return l
  }
  const markerFor = (e, cls) =>
    e.style === "promise" || e.style === "orelse" ? "m-promise" : cls === "fails" ? "m-fail" : e.style === "read" ? "m-read" : e.style === "rule" ? "m-rule" : "m-def"

  // A path through dagre's points, smoothed as d3's curveBasis, as today's renderer draws it.
  function curve(points) {
    const [first, ...rest] = points
    if (rest.length < 2) return `M${first.x},${first.y}` + rest.map((p) => `L${p.x},${p.y}`).join("")
    let [x0, y0, x1, y1] = [first.x, first.y, rest[0].x, rest[0].y]
    let d = `M${x0},${y0}L${(5 * x0 + x1) / 6},${(5 * y0 + y1) / 6}`
    const step = (x, y) => {
      d += `C${(2 * x0 + x1) / 3},${(2 * y0 + y1) / 3} ${(x0 + 2 * x1) / 3},${(y0 + 2 * y1) / 3} ${(x0 + 4 * x1 + x) / 6},${(y0 + 4 * y1 + y) / 6}`
      ;[x0, y0, x1, y1] = [x1, y1, x, y]
    }
    rest.slice(1).forEach((p) => step(p.x, p.y))
    step(x1, y1)
    return d + `L${x1},${y1}`
  }
  // An arrow between two cards' sides, for what was moved after the layout (doors, the faded map).
  function bezier(a, b, arc) {
    let sx, sy, tx, ty
    if (b.x - b.w / 2 >= a.x + a.w / 2 - 10) [sx, sy, tx, ty] = [a.x + a.w / 2, a.y, b.x - b.w / 2, b.y]
    else if (a.x - a.w / 2 >= b.x + b.w / 2 - 10) [sx, sy, tx, ty] = [a.x - a.w / 2, a.y, b.x + b.w / 2, b.y]
    else if (b.y > a.y) [sx, sy, tx, ty] = [a.x, a.y + a.h / 2, b.x, b.y - b.h / 2]
    else [sx, sy, tx, ty] = [a.x, a.y - a.h / 2, b.x, b.y + b.h / 2]
    const horizontal = Math.abs(tx - sx) >= Math.abs(ty - sy) || sy === a.y
    const c = Math.max(40, (horizontal ? Math.abs(tx - sx) : Math.abs(ty - sy)) / 2)
    const dirx = tx >= sx ? 1 : -1
    const diry = ty >= sy ? 1 : -1
    let p1, p2
    if (arc) {
      const top = Math.min(sy, ty) - arc
      p1 = { x: sx + (tx - sx) * 0.25, y: top }
      p2 = { x: sx + (tx - sx) * 0.75, y: top }
    } else if (horizontal) {
      p1 = { x: sx + dirx * c, y: sy }
      p2 = { x: tx - dirx * c, y: ty }
    } else {
      p1 = { x: sx, y: sy + diry * c }
      p2 = { x: tx, y: ty - diry * c }
    }
    const at = (t) => {
      const u = 1 - t
      return {
        x: u * u * u * sx + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * tx,
        y: u * u * u * sy + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * ty,
      }
    }
    const mid = at(0.5)
    return { d: `M${sx},${sy} C${p1.x},${p1.y} ${p2.x},${p2.y} ${tx},${ty}`, lx: mid.x, ly: mid.y, at }
  }

  // ------------------------------------------------------------------ layout

  const rectOf = (p) => ({ x: p.x - p.w / 2, y: p.y - p.h / 2, w: p.w, h: p.h })
  function union(rects, pad = 0, padTop = pad) {
    let x1 = Infinity, y1 = Infinity, x2 = -Infinity, y2 = -Infinity
    for (const r of rects) {
      x1 = Math.min(x1, r.x); y1 = Math.min(y1, r.y)
      x2 = Math.max(x2, r.x + r.w); y2 = Math.max(y2, r.y + r.h)
    }
    if (!isFinite(x1)) return { x: 0, y: 0, w: 1, h: 1 }
    return { x: x1 - pad, y: y1 - padTop, w: x2 - x1 + 2 * pad, h: y2 - y1 + pad + padTop }
  }
  const homeTitle = (F) => {
    const e = M.el.get(F)
    return `${kindWord(e)} · ${e.label}`
  }

  function layoutView(V, sizes, lsizes) {
    if (V.kind === "process") return layoutProcess(V, sizes, lsizes)
    const map = V.kind === "map"
    const g = new dagre.graphlib.Graph({ compound: true, multigraph: true })
    g.setGraph({ rankdir: "LR", nodesep: map ? 26 : 22, ranksep: map ? 46 : 56, edgesep: 10, marginx: 40, marginy: 40 })
    g.setDefaultEdgeLabel(() => ({}))
    for (const id of V.nodes.keys()) {
      const z = sizes.get(id)
      g.setNode(id, { width: z.w, height: z.h })
    }
    const groups = []
    if (map && V.F === "domain" && SET.start !== "processes") {
      for (const cx of D.domain.nodes.context) {
        const members = [...V.nodes.values()].filter((n) => (n.context || M.el.get(n.id)?.context) === cx.id).map((n) => n.id)
        if (!members.length) continue
        const gid = "cx:" + cx.id
        g.setNode(gid, {})
        members.forEach((m) => g.setParent(m, gid))
        groups.push({ id: gid, kind: "cx", ctx: cx, members, pad: 16, padTop: 22 })
        if (SET.subdomains === "frames") {
          const sid = "sd:" + cx.subdomain
          if (!g.hasNode(sid)) {
            g.setNode(sid, {})
            groups.push({ id: sid, kind: "sd", sd: M.sd.get(cx.subdomain), members: [], pad: 14, padTop: 22 })
          }
          g.setParent(gid, sid)
          groups.find((x) => x.id === sid).members.push(gid)
        }
      }
    }
    for (const e of V.edges.values()) {
      const z = lsizes.get(e.id) || { w: 0, h: 0 }
      g.setEdge(e.from, e.to, { width: z.w, height: z.h, labelpos: "c", minlen: 1 }, e.id)
    }
    // An external system nothing calls stands by the context it is related to: an edge for the layout only.
    if (map)
      for (const list of Object.values(D.domain.relations))
        for (const r of list) {
          const [x, cx] = M.el.get(r.from)?.kind === "external" ? [r.from, r.to] : M.el.get(r.to)?.kind === "external" ? [r.to, r.from] : []
          if (!x || !V.nodes.has(x) || !M.ctx.has(cx)) continue
          if ([...V.edges.values()].some((e) => e.from === x || e.to === x)) continue
          const c = [...V.nodes.keys()].find((id) => M.el.get(id)?.context === cx)
          if (c) g.setEdge(c, x, { width: 0, height: 0, minlen: 1, weight: 2 }, "layout:" + r.id)
        }
    dagre.layout(g)
    const pos = new Map()
    for (const id of V.nodes.keys()) {
      const n = g.node(id)
      pos.set(id, { x: n.x, y: n.y, w: n.width, h: n.height })
    }
    const routes = new Map()
    for (const e of V.edges.values()) {
      const ge = g.edge(e.from, e.to, e.id)
      routes.set(e.id, { d: curve(ge.points), lx: ge.x, ly: ge.y })
    }
    const frames = []
    // Frames from their members, with room for a title: contexts first, then the subdomains around them.
    for (const gr of groups.filter((x) => x.kind === "cx")) frames.push({ ...gr, ...union(gr.members.map((m) => rectOf(pos.get(m))), gr.pad, gr.padTop) })
    for (const gr of groups.filter((x) => x.kind === "sd")) frames.push({ ...gr, ...union(gr.members.map((m) => frames.find((f) => f.id === m)), gr.pad, gr.padTop) })
    const L = { pos, routes, frames }
    if (!map) pinDoors(V, L)
    L.bbox = union([...[...pos.values()].map(rectOf), ...frames], 0)
    return L
  }

  // The home's outline, and its neighbours as doors pinned to its edges: what comes in on the left, what goes
  // out on the right.
  function pinDoors(V, L) {
    const inner = [...V.nodes.values()].filter((n) => n.role === "inside" || n.role === "participant").map((n) => n.id)
    const home = { id: "home", kind: "home", title: homeTitle(V.F) + (V.focused ? " · focus" : ""), members: inner, pad: 26, padTop: 30 }
    Object.assign(home, union(inner.map((id) => rectOf(L.pos.get(id))), home.pad, home.padTop))
    L.frames.push(home)
    for (const side of ["door-in", "door-out"]) {
      const ds = [...V.nodes.values()].filter((n) => n.role === side).map((n) => L.pos.get(n.id)).sort((a, b) => a.y - b.y)
      let last = -Infinity
      for (const p of ds) {
        p.x = side === "door-in" ? home.x - 150 - p.w / 2 : home.x + home.w + 150 + p.w / 2
        const top = Math.max(p.y - p.h / 2, last + 16)
        p.y = top + p.h / 2
        last = top + p.h
      }
    }
    for (const e of V.edges.values()) {
      const doorish = (id) => V.nodes.get(id).role.startsWith("door")
      if (doorish(e.from) || doorish(e.to)) L.routes.set(e.id, bezier(L.pos.get(e.from), L.pos.get(e.to)))
    }
  }

  // The declared shape, laid out by hand: the process, then its stages in order, each a column of its events.
  function layoutProcess(V, sizes) {
    const info = V.info
    const pos = new Map()
    const frames = []
    const routes = new Map()
    const card = V.F + "#card"
    const cz = sizes.get(card)
    pos.set(card, { x: cz.w / 2, y: 0, w: cz.w, h: cz.h })
    let ay = -cz.h / 2 - 50
    for (const n of V.nodes.values())
      if (n.role === "participant") {
        const z = sizes.get(n.id)
        pos.set(n.id, { x: cz.w / 2, y: ay - z.h / 2, w: z.w, h: z.h })
        ay -= z.h + 16
      }
    let x = cz.w + 120
    const columns = info.stages.map((st, i) => ({ id: st.id, title: `${circled(i + 1)} ${st.label || st.name}` }))
    const loose = [...V.nodes.values()].filter((n) => n.stage === undefined && !n.procCard && n.role === "inside")
    if (loose.length) columns.push({ id: undefined, title: "outside every stage" })
    for (const col of columns) {
      const evs = [...V.nodes.values()].filter((n) => !n.procCard && n.role === "inside" && n.stage === col.id)
      const colW = Math.max(190, ...evs.map((n) => sizes.get(n.id).w))
      const totalH = evs.reduce((s, n) => s + sizes.get(n.id).h, 0) + 22 * Math.max(0, evs.length - 1)
      let y = -totalH / 2
      for (const n of evs) {
        const z = sizes.get(n.id)
        pos.set(n.id, { x: x + colW / 2, y: y + z.h / 2, w: z.w, h: z.h })
        y += z.h + 22
      }
      frames.push({ id: "stage:" + col.id, kind: "stage", title: col.title, x: x - 20, y: -totalH / 2 - 34, w: colW + 40, h: totalH + 54 })
      x += colW + 40 + 110
    }
    for (const e of V.edges.values()) {
      const a = pos.get(e.from)
      const b = pos.get(e.to)
      if (!a || !b) continue
      routes.set(e.id, e.style === "promise" ? bezierArc(a, b, -110) : e.style === "orelse" ? bezierArc(a, b, 90) : bezier(a, b))
    }
    return { pos, frames, routes, bbox: union([...[...pos.values()].map(rectOf), ...frames, ...[...routes.values()].map((r) => ({ x: r.lx - 80, y: r.ly - 14, w: 160, h: 28 }))], 10) }
  }
  // A promise over the top (arc < 0), its "or else" under the bottom (arc > 0): out of the opening event's top or
  // bottom, into the keeping event's side, clear of the columns between.
  function bezierArc(a, b, arc) {
    const sx = a.x
    const sy = arc < 0 ? a.y - a.h / 2 : a.y + a.h / 2
    const tx = b.x - b.w / 2
    const ty = b.y
    const p1 = { x: sx + 40, y: arc < 0 ? sy + arc * 2.2 : sy + arc * 2.6 }
    const p2 = { x: tx - 120, y: ty + arc * 1.3 }
    const t = arc < 0 ? 0.3 : 0.5
    const u = 1 - t
    const lx = u * u * u * sx + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * tx
    const ly = u * u * u * sy + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * ty
    return { d: `M${sx},${sy} C${p1.x},${p1.y} ${p2.x},${p2.y} ${tx},${ty}`, lx, ly: ly - (arc < 0 ? 12 : -10) }
  }

  // ------------------------------------------------------------------ scenes

  function frameEl(f) {
    const d = h("div", "frame")
    const t = h("div", "ftitle", f.title || "")
    if (f.kind === "cx") {
      d.classList.add("cx")
      const sd = M.sd.get(f.ctx.subdomain)
      t.textContent = f.ctx.label || f.ctx.name
      if (SET.subdomains === "colour" && sd) {
        d.classList.add("tint-" + sd.type)
        t.append(h("span", "sdchip " + sd.type, sd.label || sd.type))
      }
    }
    if (f.kind === "sd") {
      d.classList.add("sd", "sd-" + (f.sd?.type || "generic"))
      t.textContent = f.sd ? `${f.sd.label || f.sd.name} · ${f.sd.type}` : ""
    }
    if (f.kind === "home") d.classList.add("home")
    if (f.kind === "stage") d.classList.add("stage")
    d.append(t)
    place(d, f)
    return d
  }
  const place = (el, r) => {
    el.style.left = r.x + "px"
    el.style.top = r.y + "px"
    el.style.width = r.w + "px"
    el.style.height = r.h + "px"
  }
  const placeCard = (el, p) => {
    el.style.left = p.x - p.w / 2 + "px"
    el.style.top = p.y - p.h / 2 + "px"
    el.style.width = p.w + "px"
  }

  // Measures the cards and labels as the page will show them, lays them out, and draws them.
  function buildPlain(entry, opts = {}) {
    let V = computeView(entry.F, entry.focusOn ? { rules: true } : null)
    if (entry.focusOn && V.nodes.has(entry.focusOn)) V = focusView(V, entry.focusOn)
    let cross = []
    if (opts.noDoors) {
      cross = [...V.edges.values()].filter((e) => V.nodes.get(e.from).role.startsWith("door") || V.nodes.get(e.to).role.startsWith("door"))
      const nodes = new Map([...V.nodes].filter(([, n]) => !n.role.startsWith("door")))
      const edges = new Map([...V.edges].filter(([, e]) => !cross.includes(e)))
      V = { ...V, nodes, edges }
    }
    measureBox.textContent = ""
    const cards = new Map()
    const labels = new Map()
    for (const n of V.nodes.values()) {
      const c = makeCard(n, V)
      c.dataset.id = n.id
      measureBox.append(c)
      cards.set(n.id, c)
    }
    for (const e of V.edges.values()) {
      const lab = edgeLabel(e, V)
      if (!lab) continue
      const l = labelEl(lab)
      measureBox.append(l)
      labels.set(e.id, l)
    }
    const sizes = new Map()
    const lsizes = new Map()
    for (const [id, c] of cards) sizes.set(id, { w: Math.ceil(c.offsetWidth) + 1, h: Math.ceil(c.offsetHeight) })
    for (const [id, l] of labels) lsizes.set(id, { w: Math.ceil(l.offsetWidth) + 8, h: Math.ceil(l.offsetHeight) + 4 })
    const L = layoutView(V, sizes, lsizes)
    const el = h("div", "scene")
    const main = h("div", "layer-main")
    el.append(main)
    draw(main, V, L, cards, labels)
    measureBox.textContent = ""
    return { el, main, V, L, cards, labels, entry, cross, off: { x: 0, y: 0 }, focusRect: L.bbox }
  }

  function draw(layerEl, V, L, cards, labels, opts = {}) {
    for (const f of L.frames) layerEl.append(frameEl(f))
    const svg = sv("svg", { class: "edges", width: 1, height: 1 })
    layerEl.append(svg)
    for (const e of V.edges.values()) {
      const r = L.routes.get(e.id)
      if (!r) continue
      const cls = ovClass(e)
      const broken = e.style === "promise" && (V.info?.ov[e.promise.id]?.violated || 0) > 0
      const p = sv("path", { d: r.d, class: `edge ${e.style} ${cls} ${broken ? "broken" : ""}` })
      if (!e.noArrow) p.setAttribute("marker-end", `url(#${markerFor(e, broken ? "fails" : cls)})`)
      p.dataset.id = e.id
      p.dataset.from = e.from
      p.dataset.to = e.to
      p.dataset.marker = p.getAttribute("marker-end") || ""
      svg.append(p)
      const l = labels.get(e.id)
      if (l) {
        l.style.left = r.lx + "px"
        l.style.top = r.ly + "px"
        l.dataset.id = e.id
        layerEl.append(l)
      }
    }
    for (const [id, c] of cards) {
      const p = L.pos.get(id)
      if (!p) continue
      placeCard(c, p)
      c.style.height = p.h + "px"
      layerEl.append(c)
      wireCard(c, id, V, opts)
    }
  }

  // The faded map (decision 2's other answer): the parent's picture stays around the home, faded and moved aside,
  // its arrows reaching the inside elements they touch.
  function buildComposed(entry, parentEntry) {
    const P = buildPlain({ F: parentEntry.F })
    const N = buildPlain(entry, { noDoors: true })
    const boxId = entry.via || entry.F
    const box = P.L.pos.get(boxId)
    if (!box) return buildPlain(entry)
    const nb = N.L.bbox
    const off = { x: box.x - nb.w / 2 - nb.x, y: box.y - nb.h / 2 - nb.y }
    const region = { x: nb.x + off.x, y: nb.y + off.y, w: nb.w, h: nb.h }
    const dx = Math.max(0, (nb.w - box.w) / 2 + 60)
    const dy = Math.max(0, (nb.h - box.h) / 2 + 60)
    const moved = new Map()
    for (const [id, p] of P.L.pos) {
      if (id === boxId) continue
      let { x, y } = p
      if (p.x - p.w / 2 >= box.x + box.w / 2 - 1) x += dx
      else if (p.x + p.w / 2 <= box.x - box.w / 2 + 1) x -= dx
      if (p.y - p.h / 2 >= box.y + box.h / 2 - 1) y += dy
      else if (p.y + p.h / 2 <= box.y - box.h / 2 + 1) y -= dy
      moved.set(id, { ...p, x, y })
    }
    const rectFor = (id) => (id === boxId ? region : moved.has(id) ? rectOf(moved.get(id)) : null)
    const movedFrames = []
    for (const f of P.L.frames) {
      const rs = f.kind === "sd" ? f.members.map((m) => movedFrames.find((x) => x.id === m)).filter(Boolean) : (f.members || []).map(rectFor).filter(Boolean)
      if (f.kind === "home") rs.push(region)
      movedFrames.push({ ...f, ...(rs.length ? union(rs, f.pad ?? 16, f.padTop ?? 22) : f) })
    }
    // the around layer: P's cards, frames and arrows, at their moved places
    const around = h("div", "layer-around faded")
    const frameEls = []
    P.L.frames.forEach((f, i) => {
      const el = frameEl(movedFrames[i])
      el.dataset.from = JSON.stringify({ x: f.x, y: f.y, w: f.w, h: f.h })
      el.dataset.to = JSON.stringify(movedFrames[i])
      around.append(el)
      frameEls.push(el)
    })
    const aroundSvg = sv("svg", { class: "edges", width: 1, height: 1 })
    around.append(aroundSvg)
    for (const e of P.V.edges.values()) {
      if (e.from === boxId || e.to === boxId) continue
      const a = moved.get(e.from)
      const b = moved.get(e.to)
      if (!a || !b) continue
      aroundSvg.append(sv("path", { d: bezier(a, b).d, class: `edge ${e.style}`, "marker-end": "url(#m-def)" }))
    }
    const aroundCards = []
    for (const [id, c] of P.cards) {
      if (id === boxId || !moved.has(id)) continue
      const from = P.L.pos.get(id)
      placeCard(c, moved.get(id))
      c.style.height = from.h + "px"
      c.dataset.fromLeft = from.x - from.w / 2
      c.dataset.fromTop = from.y - from.h / 2
      c.dataset.toLeft = moved.get(id).x - from.w / 2
      c.dataset.toTop = moved.get(id).y - from.h / 2
      c.classList.remove("selected")
      c.onclick = (ev) => {
        ev.stopPropagation()
        const n = P.V.nodes.get(id)
        goToElement(n.target || n.ref || id)
      }
      c.ondblclick = null
      around.append(c)
      aroundCards.push(c)
    }
    // the home's inside, moved into the box's place
    const el = h("div", "scene")
    el.append(around)
    N.main.style.transform = `translate(${off.x}px,${off.y}px)`
    el.append(N.main)
    // arrows between what is around and what is inside
    const crossSvg = sv("svg", { class: "edges cross", width: 1, height: 1 })
    const crossLabels = []
    for (const e of N.cross) {
      const doorId = N.V.nodes.has(e.from) ? e.to : e.from
      const target = doorId.replace(/^(in|out):/, "")
      const pid = moved.has(target) ? target : moved.has("in:" + target) ? "in:" + target : moved.has("out:" + target) ? "out:" + target : null
      if (!pid) continue
      const innerId = doorId === e.from ? e.to : e.from
      const ip = N.L.pos.get(innerId)
      if (!ip) continue
      const ipW = { ...ip, x: ip.x + off.x, y: ip.y + off.y }
      const r = doorId === e.from ? bezier(moved.get(pid), ipW) : bezier(ipW, moved.get(pid))
      crossSvg.append(sv("path", { d: r.d, class: "edge cross " + ovClass(e), "marker-end": "url(#m-def)" }))
      const lab = edgeLabel(e, N.V)
      if (lab) {
        // by the end that is around, not over the inside's cards
        const q = r.at(doorId === e.from ? 0.22 : 0.78)
        const l = labelEl(lab)
        l.style.left = q.x + "px"
        l.style.top = q.y + "px"
        crossLabels.push(l)
      }
    }
    const crossLayer = h("div", "layer-cross")
    crossLayer.append(crossSvg, ...crossLabels)
    el.append(crossLayer)
    // the camera takes in the inside and the neighbours its arrows reach, not the inside alone
    const near = [...new Set(N.cross.map((e) => (N.V.nodes.has(e.from) ? e.to : e.from).replace(/^(in|out):/, "")))]
      .flatMap((t) => [t, "in:" + t, "out:" + t]).filter((id) => moved.has(id)).map((id) => rectOf(moved.get(id)))
    const view = union([region, ...near], 30)
    const scene = { el, main: N.main, V: N.V, L: N.L, cards: N.cards, labels: N.labels, entry, off, focusRect: view, composed: true, around, aroundCards, frameEls, aroundSvg, crossLayer }
    // Plays the move: what is around goes aside and fades, the inside grows in the box's place.
    scene.play = async () => {
      around.classList.remove("faded")
      for (const c of aroundCards) {
        c.style.transition = "none"
        c.style.left = c.dataset.fromLeft + "px"
        c.style.top = c.dataset.fromTop + "px"
      }
      for (const f of frameEls) {
        f.style.transition = "none"
        place(f, JSON.parse(f.dataset.from))
      }
      aroundSvg.style.opacity = "0"
      crossLayer.style.opacity = "0"
      crossLayer.style.transition = "opacity .3s ease"
      aroundSvg.style.transition = "opacity .3s ease"
      N.main.style.opacity = "0"
      N.main.style.transition = "opacity .45s ease"
      await nextFrame()
      for (const c of aroundCards) {
        c.style.transition = ""
        c.style.left = c.dataset.toLeft + "px"
        c.style.top = c.dataset.toTop + "px"
      }
      for (const f of frameEls) {
        f.style.transition = ""
        place(f, JSON.parse(f.dataset.to))
      }
      around.classList.add("faded")
      N.main.style.opacity = "1"
      await sleep(520)
      aroundSvg.style.opacity = "1"
      crossLayer.style.opacity = "1"
    }
    scene.reverse = async () => {
      aroundSvg.style.opacity = "0"
      crossLayer.style.opacity = "0"
      N.main.style.transition = "opacity .35s ease"
      N.main.style.opacity = "0"
      around.classList.remove("faded")
      for (const c of aroundCards) {
        c.style.left = c.dataset.fromLeft + "px"
        c.style.top = c.dataset.fromTop + "px"
      }
      for (const f of frameEls) place(f, JSON.parse(f.dataset.from))
      await sleep(520)
    }
    return scene
  }

  function buildScene(entry) {
    const i = NAV.stack.indexOf(entry)
    const parent = i > 0 ? NAV.stack[i - 1] : null
    const kind = M.el.get(entry.F)?.kind
    if (SET.around === "faded" && parent && (kind === "contract" || kind === "unit") && !entry.focusOn && !(entry.via || "").startsWith("in:") && !(entry.via || "").startsWith("out:"))
      return buildComposed(entry, parent)
    return buildPlain(entry)
  }

  // ------------------------------------------------------------------ camera

  const zoom = d3.zoom().scaleExtent([0.02, 4]).on("zoom", (ev) => {
    const t = ev.transform
    world.style.transform = `translate(${t.x}px,${t.y}px) scale(${t.k})`
  })
  const vsel = d3.select(viewport)
  vsel.call(zoom).on("dblclick.zoom", null)
  const currentT = () => d3.zoomTransform(viewport)
  const camNow = (T) => {
    vsel.interrupt()
    vsel.call(zoom.transform, T)
  }
  const camTo = (T, ms) =>
    new Promise((resolve) => {
      vsel.transition().duration(ms).ease(d3.easeCubicInOut).call(zoom.transform, T).on("end", resolve).on("interrupt", resolve)
    })
  function fitRect(r, pad, minK, maxK) {
    const vw = viewport.clientWidth
    const vh = viewport.clientHeight
    let k = Math.min((vw - 2 * pad) / r.w, (vh - 2 * pad) / r.h)
    k = Math.min(maxK, k)
    if (k < minK) {
      // never shrunk below reading size: start where reading starts, on the left
      k = minK
      const y = r.h * k < vh - 2 * pad ? (vh - r.h * k) / 2 - r.y * k : pad - r.y * k
      return d3.zoomIdentity.translate(pad - r.x * k, y).scale(k)
    }
    return d3.zoomIdentity.translate((vw - r.w * k) / 2 - r.x * k, (vh - r.h * k) / 2 - r.y * k).scale(k)
  }
  // The map is the overview, so it fits whole; an inside is never shrunk below reading size.
  const readable = (scene) =>
    scene.V.kind === "map" ? fitRect(scene.focusRect, 30, 0.3, 1.1) : fitRect(scene.focusRect, 36, scene.composed ? 0.5 : 0.72, 1.1)
  const boxInWorld = (scene, id) => {
    const p = scene.L.pos.get(id)
    return p ? { x: p.x + scene.off.x, y: p.y + scene.off.y, w: p.w, h: p.h } : null
  }

  // ------------------------------------------------------------------ navigation

  const NAV = { stack: [{ F: "domain" }], scene: null, busy: false }
  const top = () => NAV.stack[NAV.stack.length - 1]
  const enterable = (id) => ["contract", "unit", "process"].includes(M.el.get(id)?.kind)

  function setScene(scene) {
    if (NAV.scene) NAV.scene.el.remove()
    world.append(scene.el)
    NAV.scene = scene
    SEL = null
    TRACE = null
    renderPanel()
    renderChrome()
  }
  async function run(fn) {
    NAV.busy = true
    SEL = null
    TRACE = null
    renderPanel()
    try {
      await fn()
    } finally {
      NAV.busy = false
      renderChrome()
    }
  }

  async function enter(id, via) {
    if (NAV.busy || !enterable(id)) return
    const cur = top()
    cur.cam = currentT()
    const next = { F: id, via: via || id }
    NAV.stack.push(next)
    await run(() => goIn(next))
  }
  async function leave() {
    if (NAV.busy || NAV.stack.length < 2) return
    const cur = NAV.stack.pop()
    await run(() => goOut(cur, top()))
  }
  async function jump(i) {
    if (NAV.busy || i >= NAV.stack.length - 1) return
    if (i === NAV.stack.length - 2) return leave()
    NAV.stack.length = i + 1
    const scene = buildScene(top())
    setScene(scene)
    camNow(top().cam || readable(scene))
  }
  // A door, a card around, a search hit: out to the common level, then in to where the element lives.
  async function goToElement(target) {
    if (NAV.busy) return
    const path = ancestors(target).slice().reverse().filter((a) => enterable(a))
    const select1 = enterable(target) ? null : target
    if (!path.length) return
    const cur = NAV.stack.slice(1).map((e) => e.F)
    let k = 0
    while (k < cur.length && k < path.length && cur[k] === path[k]) k++
    while (NAV.stack.length - 1 > k) await leave()
    for (let i = k; i < path.length; i++) await enter(path[i])
    if (select1) select(select1)
  }

  async function goIn(next) {
    const S = NAV.scene
    const box = boxInWorld(S, next.via)
    if (SET.deeper === "swap" || !box) {
      const scene = buildScene(next)
      setScene(scene)
      camNow(readable(scene))
      return
    }
    const N = buildScene(next)
    if (N.composed) return fadedIn(S, N)
    return flightIn(S, N, box)
  }
  async function goOut(cur, prev) {
    const S = NAV.scene
    if (SET.deeper === "swap") {
      const scene = buildScene(prev)
      setScene(scene)
      camNow(prev.cam || readable(scene))
      return
    }
    if (S.composed) return fadedOut(S, prev)
    return flightOut(S, cur, prev)
  }

  // Entering: the camera flies to the box while the rest fades; the inside comes up within the box's outline;
  // then the camera settles on the inside at a readable scale.
  async function flightIn(S, N, box) {
    S.el.classList.add("dimming")
    S.cards.get(N.entry.via)?.classList.add("target")
    await camTo(fitRect({ x: box.x - box.w / 2, y: box.y - box.h / 2, w: box.w, h: box.h }, 70, 0, 6), 650)
    const nb = N.L.bbox
    const s = Math.min(box.w / nb.w, box.h / nb.h)
    const ox = box.x - (nb.w * s) / 2 - nb.x * s
    const oy = box.y - (nb.h * s) / 2 - nb.y * s
    N.el.style.transform = `translate(${ox}px,${oy}px) scale(${s})`
    N.el.style.opacity = "0"
    world.append(N.el)
    await nextFrame()
    N.el.style.opacity = "1"
    S.el.style.opacity = "0"
    await sleep(330)
    S.el.remove()
    const T = currentT()
    N.el.style.transform = ""
    camNow(T.translate(ox, oy).scale(s))
    NAV.scene = N
    renderChrome()
    await camTo(readable(N), 650)
  }
  // Leaving: the inside shrinks back into its box as the camera flies out, and the level above comes back.
  async function flightOut(S, cur, prev) {
    const P = buildScene(prev)
    const box = boxInWorld(P, cur.via)
    if (!box) {
      setScene(P)
      camNow(prev.cam || readable(P))
      return
    }
    const nb = S.L.bbox
    const s = Math.min(box.w / nb.w, box.h / nb.h)
    const ox = box.x - (nb.w * s) / 2 - nb.x * s
    const oy = box.y - (nb.h * s) / 2 - nb.y * s
    const T = currentT()
    P.el.style.opacity = "0"
    P.el.classList.add("dimming")
    P.cards.get(cur.via)?.classList.add("target")
    world.prepend(P.el)
    S.el.style.transform = `translate(${ox}px,${oy}px) scale(${s})`
    camNow(T.scale(1 / s).translate(-ox, -oy))
    await camTo(fitRect({ x: box.x - box.w / 2, y: box.y - box.h / 2, w: box.w, h: box.h }, 70, 0, 6), 600)
    S.el.style.opacity = "0"
    P.el.style.opacity = "1"
    await sleep(330)
    S.el.remove()
    P.el.classList.remove("dimming")
    P.cards.get(cur.via)?.classList.remove("target")
    NAV.scene = P
    renderChrome()
    await camTo(prev.cam || readable(P), 600)
  }
  async function fadedIn(S, C) {
    // C's coordinates are the parent's plain picture's; S shows that picture at S.off.
    const T = currentT()
    if (S.composed && S.around) {
      S.around.style.transition = "opacity .3s ease"
      S.around.style.opacity = "0"
      S.crossLayer.style.opacity = "0"
      await sleep(300)
    }
    S.el.remove()
    world.append(C.el)
    camNow(T.translate(S.off.x, S.off.y))
    NAV.scene = C
    renderChrome()
    await Promise.all([C.play(), camTo(readable(C), 700)])
  }
  async function fadedOut(C, prev) {
    await Promise.all([C.reverse(), camTo(currentT(), 1)])
    const P = buildScene(prev)
    const T = currentT()
    P.el.style.opacity = "0"
    world.append(P.el)
    camNow(T.translate(-P.off.x, -P.off.y))
    await nextFrame()
    P.el.style.opacity = "1"
    C.el.style.opacity = "0"
    await sleep(320)
    C.el.remove()
    NAV.scene = P
    renderChrome()
    await camTo(prev.cam || readable(P), 600)
  }

  async function refocus(id) {
    const e = top()
    if (id) e.focusOn = id
    else delete e.focusOn
    const scene = buildScene(e)
    scene.el.style.opacity = "0"
    setScene(scene)
    if (id) select(id)
    camNow(readable(scene))
    await nextFrame()
    scene.el.style.opacity = "1"
  }

  // ------------------------------------------------------------------ selection, trace, hover

  let SEL = null
  let TRACE = null

  function wireCard(c, id, V) {
    const n = V.nodes.get(id)
    c.onclick = (ev) => {
      ev.stopPropagation()
      if (ev.target.dataset.enter) return enter(ev.target.dataset.enter, n.procCard ? id : id)
      if (ev.target.dataset.enterContract) return enter(contractOf(ev.target.dataset.enterContract), ev.target.dataset.enterContract)
      if (ev.target.dataset.trace) return traceFromButton(id, ev.target.dataset.trace)
      if (n.role.startsWith("door")) return goToElement(n.target)
      select(id)
    }
    c.ondblclick = (ev) => {
      ev.stopPropagation()
      const target = n.procCard ? null : n.role.startsWith("door") ? null : id
      if (target && enterable(target)) enter(target)
    }
    c.onmouseenter = () => hover(id, true)
    c.onmouseleave = () => hover(id, false)
    if (SET.arrows === "every" && !n.placeholder && !n.role.startsWith("door")) {
      const l = h("div", "mini l")
      const r = h("div", "mini r")
      for (const [k, t] of [["up-all", "◀◀"], ["up", "◀"]]) {
        const b = h("button", "", t)
        b.dataset.trace = k
        l.append(b)
      }
      for (const [k, t] of [["down", "▶"], ["down-all", "▶▶"]]) {
        const b = h("button", "", t)
        b.dataset.trace = k
        r.append(b)
      }
      c.append(l, r)
    }
  }
  function traceFromButton(id, k) {
    if (SEL !== id) select(id)
    applyTrace(id, k.startsWith("up") ? "up" : "down", k.endsWith("all"))
  }

  function select(id) {
    if (!NAV.scene || !NAV.scene.cards.has(id)) {
      SEL = null
      renderPanel()
      return
    }
    SEL = id
    clearTrace()
    for (const c of NAV.scene.cards.values()) c.classList.remove("selected")
    NAV.scene.cards.get(id).classList.add("selected")
    placeToolbar()
    renderPanel()
  }
  function deselect() {
    SEL = null
    clearTrace()
    if (NAV.scene) for (const c of NAV.scene.cards.values()) c.classList.remove("selected")
    placeToolbar()
    renderPanel()
  }
  function placeToolbar() {
    document.querySelectorAll(".tbar").forEach((t) => t.remove())
    if (!SEL || !NAV.scene) return
    const n = NAV.scene.V.nodes.get(SEL)
    if (!n || n.role.startsWith("door") || n.placeholder) return
    const p = NAV.scene.L.pos.get(SEL)
    const bar = h("div", "tbar")
    const items = SET.arrows === "selected"
      ? [["up-all", "◀◀"], ["up", "◀"], ["focus", NAV.scene.V.focused === SEL ? "⊙ all" : "⊙ focus"], ["down", "▶"], ["down-all", "▶▶"]]
      : [["focus", NAV.scene.V.focused === SEL ? "⊙ all" : "⊙ focus"]]
    for (const [k, t] of items) {
      const b = h("button", "", t)
      b.title = { "up-all": "Everything that leads here", up: "What leads here directly", focus: "Show only this and what is tied to it", down: "What follows directly", "down-all": "Everything that follows" }[k]
      if (TRACE && TRACE.key === k) b.classList.add("on")
      b.onclick = (ev) => {
        ev.stopPropagation()
        if (k === "focus") return refocus(NAV.scene.V.focused === SEL ? null : SEL)
        if (TRACE && TRACE.key === k) return clearTrace(), placeToolbar()
        applyTrace(SEL, k.startsWith("up") ? "up" : "down", k.endsWith("all"))
      }
      bar.append(b)
    }
    bar.style.left = p.x - p.w / 2 + "px"
    bar.style.top = p.y + p.h / 2 + 8 + "px"
    NAV.scene.main.append(bar)
  }

  // The fine-grained chain: event → reaction → command → event, timer → command; "who reads it" behind a switch.
  function traceFine(start, dir) {
    const types = new Set([...CAUSE, ...(SET.readers ? READING : [])])
    const els = new Set(start)
    const rels = new Set()
    let frontier = [...start]
    while (frontier.length) {
      const next = []
      for (const x of frontier)
        for (const r of (dir === "down" ? M.byFrom.get(x) : M.byTo.get(x)) || []) {
          if (!types.has(r.type)) continue
          rels.add(r)
          const y = dir === "down" ? r.b : r.a
          if (!els.has(y)) {
            els.add(y)
            next.push(y)
          }
        }
      frontier = next
    }
    return { els, rels }
  }
  function applyTrace(id, dir, whole) {
    const S = NAV.scene
    const V = S.V
    const litNodes = new Set([id])
    const litEdges = new Set()
    if (!whole) {
      for (const e of V.edges.values()) {
        if (dir === "down" && e.from === id) litEdges.add(e.id), litNodes.add(e.to)
        if (dir === "up" && e.to === id) litEdges.add(e.id), litNodes.add(e.from)
      }
    } else {
      const n = V.nodes.get(id)
      const ref = n.procCard ? n.ref : id
      const start = M.el.get(ref)?.kind === "process" ? procInfo(ref).events : descendants(ref)
      const t = traceFine(start, dir)
      for (const x of t.els) {
        if (V.nodes.has(x)) litNodes.add(x)
        const L = lift(x, V.F)
        if (!L) continue
        if (L.role === "door") {
          if (V.nodes.has("in:" + L.node)) litNodes.add("in:" + L.node)
          if (V.nodes.has("out:" + L.node)) litNodes.add("out:" + L.node)
        } else if (V.nodes.has(L.node)) litNodes.add(L.node)
      }
      for (const e of V.edges.values()) if (e.rels.some((r) => t.rels.has(r))) litEdges.add(e.id)
    }
    TRACE = { id, key: (dir === "up" ? "up" : "down") + (whole ? "-all" : ""), litNodes, litEdges }
    paintTrace()
    placeToolbar()
  }
  function paintTrace() {
    const S = NAV.scene
    if (!S) return
    for (const [id, c] of S.cards) {
      c.classList.toggle("dim", !!TRACE && !TRACE.litNodes.has(id))
      c.classList.toggle("lit", !!TRACE && TRACE.litNodes.has(id) && id !== TRACE.id)
      c.classList.toggle("continues", !!TRACE && TRACE.litNodes.has(id) && S.V.nodes.get(id)?.role.startsWith("door"))
    }
    S.main.querySelectorAll("path.edge").forEach((p) => {
      const on = TRACE && TRACE.litEdges.has(p.dataset.id)
      p.classList.toggle("dim", !!TRACE && !on)
      p.classList.toggle("lit", !!on)
      p.setAttribute("marker-end", on ? "url(#m-lit)" : p.dataset.marker)
      if (!p.dataset.marker) p.removeAttribute("marker-end")
    })
    for (const [id, l] of S.labels) {
      l.classList.toggle("dim", !!TRACE && !TRACE.litEdges.has(id))
      l.classList.toggle("lit", !!TRACE && TRACE.litEdges.has(id))
    }
    const banner = document.getElementById("banner")
    const focused = S.V.focused
    if (TRACE && TRACE.key.endsWith("all")) {
      const doors = [...TRACE.litNodes].filter((x) => S.V.nodes.get(x)?.role.startsWith("door")).map((x) => labelOf(S.V.nodes.get(x).target))
      banner.hidden = false
      banner.textContent = (TRACE.key.startsWith("up") ? "Everything that leads here" : "Everything that follows") + (doors.length ? ` — continues in ${doors.join(", ")}` : "") + (SET.readers ? " (who reads it included)" : "")
    } else if (focused) {
      banner.hidden = false
      banner.textContent = `Focus on ${labelOf(S.V.nodes.get(focused)?.ref || focused)} — Escape shows everything`
    } else banner.hidden = true
  }
  function clearTrace() {
    TRACE = null
    paintTrace()
  }
  function hover(id, on) {
    const S = NAV.scene
    if (!S || TRACE) return
    S.main.querySelectorAll("path.edge").forEach((p) => {
      if (p.dataset.from !== id && p.dataset.to !== id) return
      p.classList.toggle("hl", on)
      p.setAttribute("marker-end", on ? "url(#m-hl)" : p.dataset.marker)
      if (!on && !p.dataset.marker) p.removeAttribute("marker-end")
      const other = p.dataset.from === id ? p.dataset.to : p.dataset.from
      S.cards.get(other)?.classList.toggle("hover-near", on)
    })
  }

  // ------------------------------------------------------------------ the side panel

  function renderPanel() {
    const P = document.getElementById("panel")
    P.textContent = ""
    if (!SEL || !NAV.scene) {
      P.hidden = true
      return
    }
    const n = NAV.scene.V.nodes.get(SEL)
    if (!n) {
      P.hidden = true
      return
    }
    P.hidden = false
    const id = n.procCard ? n.ref : n.role.startsWith("door") ? n.target : SEL
    const e = M.el.get(id)
    const close = h("button", "close", "×")
    close.onclick = deselect
    P.append(close, h("div", "pk", `${icon(e)} ${kindWord(e)}`), h("h2", "", e.label), h("div", "pn", e.name || id))
    const acts = h("div", "actions")
    const btn = (t, fn, primary) => {
      const b = h("button", primary ? "primary" : "", t)
      b.onclick = fn
      acts.append(b)
    }
    if (enterable(id) && id !== top().F) btn(e.kind === "process" ? "▸ Open" : "▸ Enter", () => enter(id), true)
    if (!n.role.startsWith("door")) {
      btn(NAV.scene.V.focused === SEL ? "⊙ Show all" : "⊙ Focus", () => refocus(NAV.scene.V.focused === SEL ? null : SEL))
      btn("◀◀", () => applyTrace(SEL, "up", true))
      btn("◀", () => applyTrace(SEL, "up", false))
      btn("▶", () => applyTrace(SEL, "down", false))
      btn("▶▶", () => applyTrace(SEL, "down", true))
    } else btn("Go there", () => goToElement(n.target), true)
    P.append(acts)
    const rows = []
    const f = e.facts || {}
    if (e.kind === "contract") {
      const cx = M.ctx.get(e.context)
      const sd = subdomainOf(id)
      rows.push(["Context", cx ? cx.label || cx.name : "—"], ["Subdomain", sd ? `${sd.label} (${sd.type})` : "—"], ["Holds", summary(e)])
      const procs = [...M.proc.keys()].filter((pid) => procInfo(pid).contracts.includes(id)).map(labelOf)
      if (procs.length) rows.push(["In processes", procs.join("; ")])
    }
    if (e.kind === "unit") rows.push(["Kind", kindWord(e)], ["Identity", (f.identity || []).join(", ")], ["State", (f.state || []).map((x) => x.name).join(", ")], ["Holds", summary(e)])
    if (e.kind === "process") {
      const info = procInfo(id)
      rows.push(["One run per", (f.correlate || []).join(" + ")], ["Runs", String(info.runs)])
      for (const { pr, v } of info.promises)
        rows.push([`Promise`, `${pr.within ? `within ${pr.within.amount} ${pr.within.unit}` : pr.name}: ${v.satisfied || 0} kept, ${v.violated || 0} broken, ${v.pending || 0} pending`])
    }
    if (["command", "event", "read_model", "process_manager"].includes(e.kind)) {
      const fields = f.fields || f.state || []
      if (fields.length) rows.push(["Fields", fields.map((x) => x.name + (x.required ? "" : "?")).join(", ")])
    }
    if (e.kind === "event") {
      const occ = M.nodeOv.get(id)?.occurrences
      if (occ != null) rows.push(["Happened", `${occ} times`])
      const consumers = [...M.alias.entries()].filter(([, a]) => a.to === id).map(([, a]) => labelOf(a.contract) + (a.as !== e.name ? ` (as ${a.as})` : ""))
      if (consumers.length) rows.push(["Consumed by", consumers.join(", ")])
      const procs = [...M.proc.keys()].filter((pid) => procInfo(pid).events.includes(id)).map(labelOf)
      if (procs.length) rows.push(["In processes", procs.join("; ")])
    }
    if (["policy", "process_manager", "effect", "read_model"].includes(e.kind) && f.delivery) rows.push(["Runs", f.delivery === "in_transaction" ? "in the dispatch's transaction" : "after the transaction, at least once"])
    if (f.source) rows.push(["Source", f.source])
    if (rows.length) {
      const t = h("table")
      for (const [k, v] of rows) {
        const tr = h("tr")
        tr.append(h("td", "", k), h("td", "", v))
        t.append(tr)
      }
      P.append(t)
    }
    if (e.kind === "unit" && recordsOnly(id)) {
      const core = subdomainOf(contractOf(id))?.type === "core"
      P.append(h("div", "note", `Records only: it has events, and none of its commands can be refused, so it decides nothing.${core ? " It is in the core, where the business makes its decisions — worth a look." : ""}`))
    }
    const leaves = descendants(id)
    const outs = leaves.flatMap((x) => M.byFrom.get(x) || []).filter((r) => !leaves.includes(r.b))
    const ins = leaves.flatMap((x) => M.byTo.get(x) || []).filter((r) => !leaves.includes(r.a))
    const list = (title, rs, end) => {
      if (!rs.length) return
      P.append(h("h4", "", title))
      const ul = h("ul")
      for (const r of rs.slice(0, 14)) ul.append(h("li", "", `${VERB[r.type] || r.type.replace(/_/g, " ")} ${labelOf(end(r))}`))
      if (rs.length > 14) ul.append(h("li", "", `+${rs.length - 14} more`))
      P.append(ul)
    }
    list("Leads here", ins, (r) => r.a)
    list("Goes out", outs, (r) => r.b)
  }

  // ------------------------------------------------------------------ the page around the canvas

  function renderChrome() {
    const crumbs = document.getElementById("crumbs")
    crumbs.textContent = ""
    NAV.stack.forEach((e, i) => {
      if (i) crumbs.append(h("span", "sep", "›"))
      const b = h("button", i === NAV.stack.length - 1 ? "here" : "", labelOf(e.F))
      b.onclick = () => jump(i)
      crumbs.append(b)
    })
    document.getElementById("leave").hidden = NAV.stack.length < 2
    paintTrace()
  }

  function renderSwitches() {
    const box = document.getElementById("switches")
    box.textContent = ""
    const seg = (title, key, options, hint) => {
      const w = h("div", "sw")
      w.append(h("span", "", title))
      const s = h("div", "seg")
      if (hint) w.title = hint
      for (const [v, t] of options) {
        const b = h("button", SET[key] === v ? "on" : "", t)
        b.onclick = () => {
          SET[key] = v
          saveSet()
          renderSwitches()
          rebuild()
        }
        s.append(b)
      }
      w.append(s)
      box.append(w)
    }
    seg("Going deeper", "deeper", [["flight", "Camera flight"], ["swap", "Swap picture"]], "Our plan's flight, or #297's likely reading (EventCatalog)")
    seg("Around a home", "around", [["doors", "Doors"], ["faded", "Faded map"]], "Decision 2")
    seg("Subdomains", "subdomains", [["frames", "Frames"], ["colour", "Colour"]], "Decision 3")
    seg("Start", "start", [["contracts", "Contracts"], ["processes", "Processes"], ["both", "Both (#301)"]], "Decision 1")
    seg("Trace arrows", "arrows", [["selected", "On the selected card"], ["every", "On every card"]], "Decision 4")
    const layers = h("div", "sw")
    layers.append(h("span", "", "Layers"))
    for (const [k, t] of [["rules", "Rules"], ["actors", "Actors"], ["numbers", "Numbers held"], ["readers", "Who reads it"]]) {
      const l = h("label")
      const c = h("input")
      c.type = "checkbox"
      c.checked = !!SET[k]
      c.onchange = () => {
        SET[k] = c.checked
        saveSet()
        rebuild()
      }
      l.append(c, document.createTextNode(t))
      layers.append(l)
    }
    box.append(layers)
  }

  function rebuild() {
    if (NAV.busy) return
    const scene = buildScene(top())
    setScene(scene)
    camNow(readable(scene))
  }

  function renderLeft() {
    const left = document.getElementById("left")
    left.textContent = ""
    left.append(h("h3", "", "Processes"))
    const pl = h("div", "plist")
    for (const pid of M.proc.keys()) {
      const info = procInfo(pid)
      const b = h("button")
      b.append(h("div", "pl", labelOf(pid)))
      const m = h("div", "pm", `${plural(info.runs, "run", "runs")}`)
      if (info.broken) m.append(document.createTextNode(" · "), h("span", "bad", `${info.broken} broken`))
      if (info.pending) m.append(document.createTextNode(` · ${info.pending} pending`))
      b.append(m)
      b.onclick = () => openProcess(pid)
      pl.append(b)
    }
    left.append(pl)
    left.append(h("h3", "", "Legend"))
    const lg = h("div", "legend")
    for (const [k, t] of [["command", "Command"], ["event", "Event"], ["invariant", "Rule"], ["state", "State"], ["policy", "Policy"], ["process_manager", "Process manager"], ["effect", "Effect"], ["timer", "Timer"], ["read_model", "Read model"], ["query", "Query"], ["actor", "Actor"], ["external", "External system"], ["publication", "From another app"], ["process", "Process"]]) {
      const i = h("i", "k-" + k)
      i.style.background = "var(--kc)"
      lg.append(i, h("span", "", t))
    }
    const line = (cls, t) => {
      const s = sv("svg", { width: 16, height: 8 })
      s.append(sv("path", { d: "M0,4 L16,4", class: "edge " + cls }))
      lg.append(s, h("span", "", t))
    }
    line("flow", "what follows")
    line("never", "never taken in the log")
    line("fails", "failing now")
    line("dotted", "number of / depends on / includes")
    line("rule", "may be refused by")
    line("read", "who reads it")
    left.append(lg)
    left.append(h("h3", "", "Scale"))
    const sb = h("button", "scale-btn", "AppUnite's computer: a unit of about 40 cards (outside the test set)")
    sb.onclick = openScale
    left.append(sb)
    left.append(h("h3", "", "How"))
    const ul = h("ul", "tips")
    for (const t of ["Click selects a card; the panel opens.", "▸ or a double-click enters a contract, a unit or a process.", "Escape: focus off, trace off, then leave.", "A door goes to the neighbour.", "Drag to pan, wheel to zoom.", "Switches at the top are the open decisions."]) ul.append(h("li", "", t))
    left.append(ul)
  }
  async function openProcess(pid) {
    if (NAV.busy) return
    if (top().F === pid) return
    if (NAV.stack.length > 1) {
      NAV.stack.length = 1
      const s = buildScene(top())
      setScene(s)
      camNow(top().cam || readable(s))
    }
    if (NAV.scene.cards.has(pid)) return enter(pid)
    top().cam = currentT()
    NAV.stack.push({ F: pid, via: null })
    await run(async () => {
      const s = buildScene(top())
      s.el.style.opacity = "0"
      setScene(s)
      camNow(readable(s))
      await nextFrame()
      s.el.style.opacity = "1"
    })
  }
  function openScale() {
    if (NAV.busy) return
    const cid = "contract:" + D.scale.contract
    NAV.stack = [{ F: "scale" }, { F: cid, via: cid }]
    const s = buildScene(top())
    setScene(s)
    camNow(readable(s))
  }

  // ------------------------------------------------------------------ start

  function markers() {
    const s = sv("svg", { width: 0, height: 0, style: "position:absolute" })
    const defs = sv("defs")
    for (const [id, color] of [["m-def", "#7d8796"], ["m-fail", "#d33b3b"], ["m-read", "#8fbf9d"], ["m-rule", "#d98c8c"], ["m-promise", "#9333ea"], ["m-hl", "#2f6fed"], ["m-lit", "#e0a100"]]) {
      const m = sv("marker", { id, viewBox: "0 0 10 10", refX: 9, refY: 5, markerWidth: 10, markerHeight: 10, markerUnits: "userSpaceOnUse", orient: "auto-start-reverse" })
      m.append(sv("path", { d: "M0,0 L10,5 L0,10 z", fill: color }))
      defs.append(m)
    }
    s.append(defs)
    document.body.append(s)
  }

  document.getElementById("leave").onclick = () => leave()
  viewport.addEventListener("click", (ev) => {
    if (ev.target === viewport || ev.target === world || ev.target.classList.contains("frame") || ev.target.tagName === "svg") deselect()
  })
  document.addEventListener("keydown", (ev) => {
    if (ev.key !== "Escape") return
    if (NAV.scene?.V.focused) return refocus(null)
    if (TRACE) return clearTrace(), placeToolbar()
    if (SEL) return deselect()
    leave()
  })

  loadAll()
  markers()
  renderSwitches()
  renderLeft()
  const first = buildScene(top())
  setScene(first)
  camNow(readable(first))
  window.__mock = { M, NAV, SET, enter, leave, goToElement, select, applyTrace, refocus, openProcess, openScale, rebuild }
})()
