# Changelog

The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

**Every change a user of this package can see gets a line under `## [Unreleased]`, in its own pull
request.** A user is a host application's developer: what they see is the package's public API, its
Mix tasks, what it writes, what it verifies and what the dashboard reports; its tests, docs and CI
are not. A pull request with no such line says why on a line of its description,
`No changelog: <why>`, and CI's Changelog check (`.github/workflows/changelog.yml`) fails it
otherwise. A line for a breaking change, one a host has to act on when it upgrades, starts with
`**Breaking:**`, under the subsection it belongs to.

This package keeps its own version; the repository's tag, `vX.Y.Z`, is the engine's, and one tag
releases each package whose version has left `-dev`, at its own version; the others stay unreleased at
that tag, though `release.json` lists their versions. Between releases the version in `mix.exs` ends in `-dev`;
at a release, a package with lines under `## [Unreleased]` moves to its next version. Every release
moves the engine, whose version the tag is: a release of other packages alone moves it by a patch
from its last release, and that version's section says so under `### Changed` ("Released with
eh_os_contract_auth 0.1.1; nothing in the engine changed."). The maintainers make a release by
their release procedure, and pushing the tag publishes it (`.github/workflows/release.yml`).

## [Unreleased]

### Added

- **A box that leads somewhere says so** (#488): the title of a box whose panel offers to open a host's page or a
  picture inside ends in a mark, "›", and shows when it is pointed at or reached by the keyboard; a landscape's
  domain box with nothing on the wire says inside it that it publishes and subscribes to nothing. A view's
  groups gain a `note`, `nil` but for such a box. The canvas calls the host's `link` for each box when it draws
  the picture, not only for a selected one; a `link` that throws or exits, as one that raises, offers nothing for
  that box.
- **A host can open a canvas at an element**: `Canvas` takes `select`, the id of a card, a group or an
  arrow of the view, which it selects over the whole picture, opens the panel of and brings into view, as the
  search's Enter does. It is read when the host gives one other than the last it gave, so rendering again with
  the same leaves what the reader selected since; `nil` lets the host ask for the same again, and an id the
  document does not have yet applies once it has it. `Landscape.box/2` names an application's first box, to
  open a landscape at it.
- **A landscape draws an application no domain document describes** (#487): `Landscape.join/1` takes
  `{application, :none}` for an application the host knows is there but has no document of, and the canvas draws
  it as a dashed, see-through box in the place of its entry, titled "no graph described", empty and with no arrow.
  Its panel says what is not known and offers "Open this application", for which the canvas calls the host's
  `link` with `nil` for the domain; a host that joins no such entry is never called so, and one that does
  answers for a `nil` domain, since the panel offers whatever path its `link` builds. The landscape's `nodes`
  gain an `"application"` list, empty without such entries.

### Changed

- **The explorer has one path, says what each place shows, and no switch of who reads** (#490): the tabs
  "Structure" and "Processes" are gone; the path is the one way through, with the step to the processes beside
  the domain. A line under the path says what the place shows, and where it can be drawn two ways — "Contracts"
  or "Contexts and their relations", "Commands and events" or "Lifecycle" — both stay offered there with the
  chosen one's line. The reader's "Engineering" / "Owner" switch is gone: a host that wants the owner's view
  alone still passes `audience={:owner}`.

- **The zoom is one control in the picture's corner** (#489): the row of "−", "+", "Readable" and "Whole picture"
  over the canvas is gone; a button over the picture's top right corner opens a menu of "Closer", "Farther",
  "Readable" and "Whole picture", which stays open while it is used and closes on a press elsewhere or Escape.
  The canvas sits in a new `.ehg-stage`, which a host styling the canvas's surroundings may meet.

### Fixed

- **A box with no card no longer grows on each update** (#488): the hook measured such a box at the size its
  last layout gave it, one pixel more each time, and laid the picture out anew whenever the host rendered it
  again; it now measures each at its own size.

## [0.8.0] - 2026-10-26

### Added

- **A value's panel lists the scenarios its invariants refuse** (#458): a command's scenario refused before any
  decision on the invariant of a domain value its data breaks, read from a unit scenario's new, optional
  `rejected_on_value` in `graph.v1`, and a recording refused on one. Each says which invariant is broken, by its
  label for the owner. A command's scenario refused so is never shown as one in which nothing is recorded.
- **A scenario that records an event is drawn** (#430): on the arrow from the actor who may record it, the panel
  says who records which event after which events, and what is appended or the invariant of a domain value the
  recording breaks, by its label for the owner. It reads the `record` group of a `graph.v1` document's
  `scenarios`; a document without it draws as before.

## [0.7.1] - 2026-10-24

### Changed

- **`esbuild` is no longer a host's dependency** (#421). Only `mix assets.build` runs it, in this package's own
  development, and its output is committed.

## [0.7.0] - 2026-10-23

### Changed

- **A domain with nothing on the wire has its box in the landscape** (#412): the `:landscape`
  view draws a box for every domain `EhOsContract.GraphRenderer.Landscape.join/1` is given, where it drew none
  for a domain whose contracts publish and subscribe to nothing. Such a box holds no card and its title says how
  many contracts the domain has ("ledger · ledger · 2 contracts"); its panel offers "Open this domain" as any
  box's does, so a landscape of applications that are not yet joined to one another is no longer empty.

## [0.6.0] - 2026-10-22

### Added

- **A landscape leads to a host's page of each domain** (#404): `EhOsContract.GraphRenderer.Canvas` takes a
  `link`, a function of an application's name, its domain's module and a contract's id (`nil` for the domain)
  answering a path or a URL. In the `:landscape` view, the panel of a domain's box offers "Open this domain"
  and that of a contract in it "Open this contract", a plain link to that address. Without `link`, or where it
  answers `nil`, raises, or answers anything but a path on the host's site or an `http` or `https` URL, the
  panel is as it was.
- **The explorer starts where the host says** (#404): `EhOsContract.GraphRenderer.Explorer` takes `at`,
  `{:contract, id}`, `{:process, id}` or `:processes`, and goes there once the domain's document names it. A
  place the domain does not name, or anything else, starts at the domain, as before.

## [0.5.0] - 2026-10-22

### Added

- **The package carries the schema of the `graph.v1` format it draws**, at
  `EhOsContract.GraphRenderer.schema_path/0`, the same file as the engine's
  `EhOsContract.Graph.Document.schema_path/0`, so a host that checks the documents it is sent no
  longer keeps a copy of its own (#400).

## [0.4.0] - 2026-10-17

### Added

- **The process view draws what a promise waits on through an earlier step** (plan DD, stage OW1, #355): a
  `graph.v1` document's `waits_on` relation is a dotted arrow, with no head, from the event that opens the promise
  to the external system. The promise's panel names the systems it waits on, and the system's panel the promises
  that wait on it; the owner's label of a promise ends with "waiting on" them.

## [0.3.0] - 2026-10-16

### Added

- **The explorer reads the model for the business owner** (plan DD, stage L4, #326): a switch "Engineering /
  Owner" over the canvas, and `audience={:owner}` on `EhOsContract.GraphRenderer.Explorer` to start there
  (`:engineering` by default, as before). `EhOsContract.GraphRenderer.Canvas` takes the same `audience`, and
  `EhOsContract.GraphRenderer.View.build/4` too. For the owner the cards and the panel say each declaration by
  its label, a field by its label alone, a contract by its context's label and a promise by its rule, and leave
  out names and modules in code, the stored type, delivery, idempotency, the keys runs are told by, grants,
  roles, scopes, identities, fields with no label, scenarios' data and the wire between applications. The
  numbers from the log stay.

- **A process's picture shows the stages runs entered out of order** (plan DD, stage O2, #319): a dotted arrow
  in the error look from the later stage's lane back to the earlier one, "entered first", with how many runs,
  from the overlay's `observed.relations.out_of_order`; its panel names the two stages.

## [0.2.0] - 2026-10-16

### Added

- **Several applications joined into one landscape** (plan DD, stage G1, #297):
  `EhOsContract.GraphRenderer.Landscape.join/1` takes `{application, domain_document}` pairs and matches what one
  publishes to what another subscribes to by the name on the wire; `Canvas` draws the result with
  `view={:landscape}`, a box per domain holding its contracts on the wire and saying how many others it has, and a
  card per name between them. A name some document subscribes to and none of the set publishes is drawn as coming
  from outside the set. Two domains of one application are joined as two applications are.

- **A contract's card on the domain's map says its drift** (plan DD, stage G1, #297): "2 never taken, 1 move not
  allowed", from the domain's overlay, in the error colour; nothing where the log found none. An event a
  contract consumes takes the contract that declares it from the document's `declared_in`, and reads it out of
  the sibling event's id only in a document from before it.
- **An explorer of a domain** (plan DD, stage G1, #297): `EhOsContract.GraphRenderer.Explorer` is one canvas
  with two viewpoints, the structure (the domain's system with a switch to its context map, a contract, a unit
  with a switch to its lifecycle) and the processes, a path back up, and the panel's "Open" where a card leads —
  across the viewpoints, from a process's event to its contract. Its documents and overlays come from a loader
  the host implements (`EhOsContract.GraphRenderer.Loader`), called in the background when the reader enters a
  picture, an overlay only where the picture draws it; one that fails is said in place of the picture and loaded
  again when the reader comes back. `Canvas` takes `open`, the component the
  panel's "Open" goes to.
- **A bar over the canvas: search, focus, the log's switch and zoom** (plan DD, stage G1, #297). The search dims
  the cards it does not find and on Enter selects the first one and moves the view to it (`View.matches/2`);
  "Focus on the selection" draws a card or a group with what its relations reach, laid out again
  (`View.around/2`); a switch draws the declaration alone or with what the log says; buttons zoom in and out,
  return to the readable start, or show the whole picture.
- **A picture starts at a readable scale** (plan DD, stage G1, #297): a picture that does not fit the canvas is no
  longer shrunk until its cards cannot be read; it starts at the edge it overflows from, its left or its top, and
  the reader pans, or asks for the whole picture.
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
