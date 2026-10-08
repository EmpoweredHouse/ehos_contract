# Changelog

The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

- **E13b, batch 4: the panels.** `EhOsContract.GraphRenderer.Panel` says what is selected, from the document
  alone, through the joins of `EhOsContract.GraphRenderer.Lookup`: a command's fields, who may issue it and the
  grant EHOS gives, its scope, the statuses it is allowed in and the rules it may be refused on; an event's
  fields, who records it, where it comes from, whether it ends the run, the systems it rests on and everything
  that depends on it; a policy's, a process manager's and an effect's triggers, commands, timers, rules,
  delivery and idempotency, and their scenarios with their data, a manager's by what triggers them; a read
  model's and a query's fields, parameters, readers and scenarios; a context's terms, relations, contracts and
  entities; an external system's outage and operations; an actor's role, responsibilities and what the role may
  do; a relation's ends and the scenarios that cover it. A field reads the same everywhere: personal data, a
  pointer at a person, a domain value's members and unit, an entity, the system that gives its value. A name in
  the panel selects that node, drawn or not. `EhOsContract.GraphRenderer.Actors` lists a domain's actors, people
  and systems apart, a row selecting one in a canvas. A policy, a process manager and a query say on their card
  how many scenarios pin them. A canvas is as tall as its picture fitted to its width, up to `min(72vh, 760px)`,
  and is fitted again when its width changes unless the reader has zoomed or panned it. The panel is a sidebar at
  the right of the window, as tall as it and scrolled inside, one for the page, closed by Escape, lying over the
  page so that no canvas is resized by it; it opens `--eh-os-contract-graph-panel-width` wide, and the reader
  drags its edge to set its width, once a frame, which the browser keeps. A canvas is contained, and a pan or a zoom
  moves the graph as a layer of its own. The zoom and the panel's width while it is dragged are Web Animations,
  not a stylesheet written on every frame, after which WebKit styles the whole page again: Safari stuttered.
- **E13b, batch 3: the views.** `EhOsContract.GraphRenderer.View` builds the six pictures the engine drew as
  Mermaid diagrams from the graph of facts — a contract's full graph, its process's declared shape, a unit, an
  aggregate's lifecycle, a domain's context map and its system — with the words and the lines those pictures
  had; `View.views/1` lists those a document has, and `Canvas` takes the one to draw as `view`
  (`:contract`, `:declared`, `{:unit, id}`, `{:lifecycle, id}`, `:context_map`, `:system`; `:all`, the test
  bed, when it is left out). The drawing layer gains what the pictures need: groups as boxes around their
  cards, with a title that selects them; a view laid out top to bottom; an arrow between two groups; a dotted,
  a heavy and a headless arrow; a state card listing its fields, an end of a process in green, a lifecycle's
  end drawn heavier and its start a dot; and a label with nothing to say that takes no room. Where the facts
  are finer than the picture, the view follows the facts: a process manager's start, end and an event it takes
  during its run are arrows of their own, and two arrows of one type between the same two cards say which is
  which.
- **E13b, batch 1: the package and its drawing layer.** `EhOsContract.GraphRenderer.Canvas` draws a
  `graph.v1` document and its overlay: every node a card and every relation a label, rendered in HEEx, laid
  out by the `EhOsContractGraph` hook with dagre and its arrows drawn in SVG; pan and zoom with d3-zoom; a
  click on a card, a label or an arrow selects it and opens a raw panel. A relation from a card to itself is a
  loop out of the card. The graph is fitted to the canvas when its cards change, and the reader's zoom is kept
  otherwise. An overlay of another version of the document is not drawn, and an update that names only some
  attributes keeps the rest. It draws one view for now, everything in the document. The script is an ES module
  and the stylesheet a plain file under `priv/static/`, built by esbuild and committed; nothing in them needs
  more than `default-src 'self'`.
