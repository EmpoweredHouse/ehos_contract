# Changelog

The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

**Every change a user of this package can see gets a line under `## [Unreleased]`, in its own pull
request.** A user is a host application's developer: what they see is the package's public API, its
Mix tasks, what it writes, what it verifies and what the dashboard reports; its tests, docs and CI
are not. A pull request with no such line says why on a line of its description,
`No changelog: <why>`, and CI's Changelog check (`.github/workflows/changelog.yml`) fails it
otherwise. A line for a breaking change, one a host has to act on when it upgrades, starts with
`**Breaking:**`, under the subsection it belongs to.

This package keeps its own version; the repository's tag, `vX.Y.Z`, follows the engine's, and
releases every package at its own version. Between releases the version in `mix.exs` ends in `-dev`;
at a release, a package with lines under `## [Unreleased]` moves to its next version. Every release
moves the engine, whose version the tag is: a release of other packages alone moves it by a patch
from its last release, and that version's section says so under `### Changed` ("Released with
eh_os_contract_auth 0.1.1; nothing in the engine changed."). How a release is made is written in
eh-os's [`docs/releases.md`](https://github.com/EmpoweredHouse/eh-os/blob/main/docs/releases.md),
and the `ehos-dev:release` skill makes one.

## [Unreleased]

### Added

- **Cards of their kind, and a legend** (plan DD, stage G1, #297): every card has a badge with its kind's icon and
  name, the client's label, the name in code, which may break after a dot, an underscore or a colon, and a footer
  saying where the element lives when the picture does not: the contract that declares an event of a process, the
  sibling contract an event is consumed from, or another application it is received from. Each kind has a colour
  in Event Storming's families, a process's among them, on the design system's surfaces, in a dark and a light
  theme. Under the canvas, a legend lists the kinds, the cards drawn other than their kind (an event that ends a
  run, a final status) and the looks of the arrows the view draws, each look said in words to a screen reader
  (`View.legend/1`).
- **A unit that records only is marked** (plan DD, stage C1, #304): when the document says `records_only`, the
  unit's card and its box say "records only" beside its kind, and its panel says "Records only: no command it
  takes can be refused."
- **A process module's picture** (plan DD, stage P2e, #220): the view `:process` draws a process module's
  `graph.v1` document top to bottom — the process, with what one run is and its deadline, and the actor
  accountable for it; its stages as boxes in their order, each after the one before; in each, the events it
  includes, each naming the contract that declares it, those that end a run in green; each promise a heavy arrow
  from the event that opens it to the one that keeps it, with its window, and a dotted one to the event that keeps
  it the other way; and the external systems the events rest on, whose outage suspends a promise, hung off them
  by a dotted line. With the process's overlay, the process card counts its runs, each event how often it happened
  (×0 included), and a promise's arrow its verdicts — "3 kept, 1 broken, 2 pending", in the
  error colour when a run broke it. A promise the owner has yet to confirm, which no run is judged against, reads
  "unconfirmed", with or without an overlay. The panels say a process's run, deadline, accountable actor, contracts, stages, promises and runs; a
  stage's place and events; a promise's window, events and verdicts; and an event's contract and stage, its fields
  being in the contract's own document.
- **The system view draws a domain's process modules** (plan DD, stage P2e, #220): a card for each, a dotted
  "includes" arrow to each contract whose events it includes, the actor accountable for it, and its runs from the
  domain's overlay. A process's panel names its module and the contracts it includes, and a contract's the
  processes that include its events.
- **A contract keeping the number of a sibling's unit, drawn** (plan DD, stage L3, #286). The system view draws a
  dotted arrow from the sibling to the contract keeping its unit's number, "number of visit", the way the number
  travels, as a consumed event's arrow does; its panel says which units, and a contract's panel lists the units
  whose numbers it keeps ("Keeps the number of") and the contracts keeping its units' ("Its units' numbers are
  kept by"). It reads the domain document's `refers_to` relations, which the engine writes from this release.

### Changed

- **Breaking:** a card of the `:process` view names the contract that declares its event in `foot`, a new key of a
  view's node, rather than in `lines` (plan DD, stage G1, #297). A host reading `View.build/3`'s nodes reads it there.
- **Breaking:** the custom properties `--eh-os-contract-graph-fill` and `--eh-os-contract-graph-stroke` are gone
  (plan DD, stage G1, #297). A card is drawn on the host's surface in its kind's hue,
  `--eh-os-contract-graph-hue`, taken from the palette's properties on `.ehg` (`--eh-os-contract-graph-event`,
  `--eh-os-contract-graph-command`, …, one set for each theme); a host that recoloured a kind overrides those
  instead. Its ink is the host's `--text-primary`, no longer black.

### Removed

- **Breaking:** the view `:declared`, a contract's process (plan DD, stage P2e, #220). A contract declares no
  process since the engine's #221, so the view was always empty; draw a process module's document with `:process`
  instead. A contract's full graph no longer draws an event because a process includes it, and the system view's
  contract card no longer names a process, both of which only a contract's own process gave.

## [0.1.0] - 2026-10-11

### Added

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
