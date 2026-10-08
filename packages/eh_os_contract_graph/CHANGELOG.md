# Changelog

The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

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
