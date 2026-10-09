# Changelog

The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

- **The first version: a `graph.v1` document drawn in a LiveView** (plan E13, #217). It does not depend on the
  engine: a document is plain data, the same from `EhOsContract.Graph.Document` as from `GET <mount>/graph/…`
  decoded.
  - `EhOsContract.GraphRenderer.Canvas` draws a document and, optionally, its overlay: every node a card and every
    relation a label, rendered in HEEx, laid out by the `EhOsContractGraph` hook with dagre, the arrows drawn in
    SVG, pan and zoom with d3-zoom. `view` picks the picture — `:contract`, `:declared`, `{:unit, id}`,
    `{:lifecycle, id}`, `:context_map`, `:system`, the six the engine drew as Mermaid, with their words and lines —
    or `:all`, every node and relation; `EhOsContract.GraphRenderer.View.views/1` lists those a document has. An
    overlay of another version of the document is not drawn.
  - A click on a card, a group's title, a label or an arrow selects it and opens a panel that says what it is, from
    the document alone: a command's fields, who may issue it and the grant EHOS gives, what its decision reads
    and the one person who may issue it; an event's fields, who records it, where it comes from, whether it ends
    the run; a reaction's triggers, commands, timers, rules, delivery and idempotency; a query's parameters and
    answers; a context's terms with their word in code; an actor's role and what it may do; the scenarios behind an
    arrow, with their data, the person, the rows read and when each given happened. A field reads the same
    everywhere. The panel is a sidebar at the right of the window, lying over the page, its width set by
    dragging its edge and kept by the browser.
  - `EhOsContract.GraphRenderer.Actors` lists a domain's actors as a table, people and systems apart, a row
    selecting one in a canvas.
  - The script is an ES module and the stylesheet a plain file under `priv/static/`, built by esbuild and
    committed; nothing in them needs more than `default-src 'self'`. `NOTICE` names dagre, graphlib and d3,
    which the script carries.
  - Only `GraphRenderer`, `Canvas`, `Actors` and `View` are published; `mix check` holds their docs with
    `--warnings-as-errors` and a doc coverage test.
