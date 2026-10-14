# One explorable graph of the contracts — plan (working draft)

> **A working draft, not an implementation plan.** It says what we want, for whom and why. It lives on the branch
> `graph/explorer-plan` and is **deleted before that branch is merged**. Once it is agreed, it becomes a GitHub issue,
> and only then pull requests.
>
> **Comments:** write them anywhere between `%%%` markers. Sections and points are numbered so they can be
> referred to ("3.2", "decision 4").
>
> Client labels (Rehmed's, in Polish) are quoted as the client wrote them, with an English gloss on first use.

---

## 1. In one paragraph

Today the Graph screen is several separate pictures, one under another: the context map, the system, a contract's
full graph, and a picture of each unit and of its lifecycle. Each stops at its own edge, and moving between them
means scrolling the page and picking a contract from a list. We want **one canvas**:

- it starts from the whole application: its contexts, its contracts and what flows between them;
- going deeper is a click: into a contract, into a unit, down to a single command or event;
- nothing around is lost on the way.

The same canvas shows the **processes** that run through several contracts, and it lets a reader **trace what
follows from an event and what leads to it**. The side panel with the details stays as it is. **Nothing that can be
seen today may disappear.** What changes is how the content is organised and moved through, not how much of it there
is. There will be more, since the processes come back.

---

## 2. For whom, and why

The readers of the graph, as listed when the way of drawing it was chosen (`docs/adr/graph-renderer.md`, 7 October):

| # | Who | Why they look | The question they come with |
| --- | --- | --- | --- |
| 2.1 | **The developer and the reviewer of a change** | they read the contract as a picture rather than as code | "What does my change affect? What connects to what?" |
| 2.2 | **The process owner on the client's side** | they confirm the rules, the scenarios and the promises in their own words | "Is this how our business works?" |
| 2.3 | **Whoever watches for drift** | the same picture with the numbers from the log | "Where does the code do something other than the contract says?" |
| 2.4 | **The CTO in the EHOS Console** | every process of the application together | "What do we have, and how does it connect?" |

The graph is **for viewing only**: nobody drags, connects or edits anything on it.

---

## 3. What is in the way today

**3.1 Pictures with nothing between them.** A contract's picture stops at its edge: it shows that an event comes from
a sibling, but to see what the sibling does with it, the reader picks another contract from the list and searches
again.

**3.2 One event is several cards.** Scheduling's `visit_completed` ("Pacjent wyszedł z gabinetu", the patient left
the room) is a card in Scheduling and another card in Clinical documentation, which consumes it. Only the panel says
they are the same event.

**3.3 Processes are not shown at all.** In early October processes moved out of contracts into modules of their own,
since one run (a visit, say) goes through several contracts. On 13 October a contract lost the ability to declare a
process at all (#221), and the "declared shape" picture left the Graph screen. The graph does not know process
modules yet. That is a regression to be repaired anyway, and it has a planned stage (#220) with three pull requests:
processes in the graph document, their picture on the screen, their pages and Mix tasks.

**3.4 A large contract cannot be read.** The full graph of AppUnite's computers is 33 cards and 49 arrows in one
picture (the whole contract has 62 elements and 111 relations; the rest is on the unit's and the lifecycle's
pictures). Nothing can be put away.

**3.5 Nothing says where to start.** The numbers from the log (what was never taken, what happened without being
declared) are on each contract's picture. Finding a problem means going through every contract in turn.

---

## 4. The structure: what belongs to what

### 4.1 Every element has exactly one home

An element's home is where it is declared. It is a tree: every element has one parent.

```
Domain — the client's whole application (e.g. Rehmed); one application is one domain
├── Subdomain — core / supporting / generic
│   └── Context — a part with its own language and glossary  ← in one subdomain
│       └── Contract                                          ← in one context; a context may have several
│           ├── Unit — aggregate or dynamic consistency boundary  ← in one contract, never in several
│           │   ├── Commands (each with its own constraints)
│           │   ├── Events                                    ← EVERY event in one unit
│           │   ├── Invariants (the rules a command may be refused on)
│           │   ├── State (fields)
│           │   └── Lifecycle (statuses) — aggregates only
│           ├── Reactions: policies, process managers (with timers), effects  ← the contract's, not a unit's
│           ├── Read side: read models, queries
│           ├── Domain services
│           ├── Ways in and out: consumed from a sibling, received from another application, published to one
│           └── Scenarios (examples that are tests)
├── Relations between contexts — one of the eight context-mapping patterns (e.g. customer/supplier)
├── Actors — roles of people and systems                     ← the domain's; an actor may be tied to one context
├── External systems
├── Values, entities, subjects whose personal data is protected
└── Processes — each with stages, promises and scenarios     ← the domain's, not a context's: they cut across
```

A process is only a module of its own: since 13 October a contract can no longer declare one (#221).

A glossary, worded after the library's documentation:

- **Unit:** what a command is sent to. It holds the rules, reads what it decided before, and answers each command with
events or a refusal. Two kinds:
  - **aggregate:** decides over one stream, the events that carry its identity, e.g. Scheduling's `visit`;
  - **dynamic consistency boundary** (`dcb`): decides over a query of the log, its own events and the events of other
  units it consults.
- **Policy:** "when X happens, issue Y". Stateless: it sees one event and issues a command of its own contract.
- **Process manager:** steers one run over time: remembers, waits, gives up. It has timers. Example: Clinical
documentation's `documentation_chase` ("Pogoń za dokumentacją wizyty", chasing the visit's documentation).
- **Effect:** the only reaction that touches the world outside the database, e.g. calls an external system. When the
world's answer matters, the effect records it as an event, as a system actor.
- **Read model:** rows built from events, for reading. It decides nothing.
- **Entity:** a thing with an identity whose life the application's code or another system keeps, outside the log
(a period, a catalogue item).

**A unit belongs to exactly one contract and is never shared.** Only the actors and reactions of its own contract
issue its commands. Another contract cannot issue it anything directly: it can only consume the unit's event and
react, and then its policy issues a command to **its own** unit. A consistency boundary may read other contracts'
events, but it still belongs to one contract.

**One business thing is often several units in several contracts**, tied by a shared identifier. A patient's visit
at Rehmed is four units, each in another contract and each deciding something else:

| Contract | Unit | What it decides | Identifier |
| --- | --- | --- | --- |
| Scheduling | `visit` | the appointment, a cancellation, a no-show | `visit_id` |
| Clinical documentation | `visit_documentation` | ICD codes, the clinical close | `visit_id` |
| Settlement | `visit_settlement` | services, payment, corrections | `visit_id` |
| Statutory reporting | `p1_report` | the report to the medical events register (P1) | `visit_id` |

Since 12 October the tie is declared (#286): the `visit_id` field in Clinical documentation, Settlement and
Statutory reporting says it holds the number of Scheduling's `visit` (`{:id, :visit}` in the code). A contract does
not compile when that name matches nothing, or two things. Since 13 October the system picture draws it as a dotted
arrow, "number of visit", from Scheduling to each of the three. A command still cannot read another contract's unit:
its state is what happened to it, which only its own contract decides.

The clinical visit process joins three of these units by `visit_id`: Scheduling, Clinical documentation and Statutory
reporting. The visit's settlement belongs to another process (payer settlement), which joins its events by payer and
period. On the graph these are four cards in four homes, tied by process lines (5.4) and the trace (6), not by a
shared box.

### 4.2 Away from home, an element is used in many places

| How an event is related | How many | Example from the test material |
| --- | --- | --- |
| declared in a unit (its home) | **exactly 1** | `visit_completed` in Scheduling's `visit` |
| emitted by a command, or recorded by a person or a system | 1 or more (otherwise it does not compile) | recorded by the specialist |
| builds its unit's state | an aggregate's: always | part of the `visit`'s history |
| consumed by other contracts of the same application | 0 or more | consumed by Clinical documentation |
| in a stage of a process | 0 or more processes, one stage in each | stage 1 of the clinical visit process |
| sent to other applications | 0 or more publications | TaxVision sends the month opened as `taxvision.accounting_month.opened.v1` |
| starts reactions | 0 or more | starts the `documentation_chase` process manager |
| consulted by a consistency boundary | 0 or more | `visit_booked` is consulted by `visit_documentation` |
| opens, keeps or ends (a process, a promise) | 0 or more | opens the promise "report to P1 within 2 days" |
| projected into read models | 0 or more | |
| moves a lifecycle status | 0 or more transitions | |
| depends on an external system | 0 or 1 | the P1 report being sent depends on the P1 register |

**The exception:** an event received from another application has no home in this one. It arrives in the inbox of
the contract that subscribes to it, never in the log, and only a policy takes it.

The other elements:

- **Command:** one unit. Issued by actors, policies, process managers and timers of its own contract.
- **Reaction:** one contract. It takes its own contract's events and those the contract consumes from siblings; an
event from another application only a policy takes.
- **Actor:** one domain, touching many contracts. It may be tied to one context, and then acts only in that context's
contracts.
- **External system:** one domain, touching many contracts.
- **A unit, away from home:** fields of other contracts may hold its number (0 or more), as three Rehmed contracts hold
the visit's. That is a reference, not a copy: the unit still has one home.
- **Process:** one domain, taking events from many contracts. One event may be in several processes.

### 4.3 What follows for the graph

- **The home is one and fixed, so a card always stands in its home:** an event in its unit, a unit in its contract.
That gives a fixed geography: once you know where something is, it stays there.
- **Everything else is a link, not a copy.** A contract that consumes an event gets an arrow to it, not a card of its
own. Today it is a copy (3.2).
- **Keeping an event inside its aggregate is right**, since the aggregate is its only home. It would be wrong only if a
closed box hid the links. So the links of what is inside a closed box go to the box itself, as one arrow with a count
("3 events").
- **A process is not a box.** Its events already have homes elsewhere, and one event may be in several processes. A
process is a **line** through the cards, like a metro line through its stations.

---

## 5. The idea: one canvas

### 5.1 The start: the application's map

- Contexts, with their contracts in them. A context with one contract is one box.
- The subdomain (core, supporting, generic) shows on every context. A frame or a colour is decision 3.
- External systems, and publications: what leaves for other applications.
- Arrows between contracts: which events one consumes from another; and dotted ones: which one holds the number of
whose unit ("number of visit").
- On every contract, **badges with numbers from the log**: how many paths were never taken, how many transitions were
not declared, how many promises were broken. The badges say where it is worth going in (3.5).

```
┌ Scheduling · core ┐  visit_booked,       ┌ Clinical documentation · core ┐
│  Scheduling  [▸]  │─ visit_completed ───▶│  Clinical documentation  [▸]  │
│  ⚠ 2 never taken  │                      └───────────────┬───────────────┘
└───────────────────┘               visit_closed_clinically │
                                                            ▼
┌ Settlement ┐  visit_charged_to_payer  ┌ External payers ┐   ┌ Statutory reporting ┐ ─ ─▶ [P1 register]
│ Settlement │─────────────────────────▶│ External payers │   │ Statutory reporting │
└────────────┘                          └─────────────────┘   └─────────────────────┘
```

At Rehmed that is about 8 boxes: 6 contexts (one without a contract) and 2 external systems. It fits on the screen.

### 5.2 Going deeper: entering a home

Filip's decision (14 October): **entering, with the camera flying in, and a home's inside hidden until it is
entered.** Rejected: expanding in place (the box swells, the rest of the map moves aside, cards jump) and zooming with
the wheel as on Google Maps (it has to be clicks).

**The rule:** at every level only the homes' boxes show, never their insides. A box shows its name, a short summary
("visit · 3 commands · 5 events"), the badges from the log and the "records only" mark (5.8). Its inside appears only
after entering, and goes when the reader leaves.

**The levels:**

| Level | What shows | Homes that can be entered |
| --- | --- | --- |
| The application's map (5.1) | contexts, contracts, external systems, publications, what flows between contracts | contracts |
| Inside a contract | units (closed), reactions with their timers, read models, queries, the actors and systems that touch it | units |
| Inside a unit | state, commands, events, rules, the number of scenarios on each arrow (today's unit picture); the "lifecycle" switch (5.5) | — |

**What entering looks like:**

```
1. The map. Click "enter" on Clinical documentation (the ▸ button, or a double click)

┌ Scheduling ┐ ─────▶ ┌ Clinical doc. ┐ ─────▶ ┌ Statutory reporting ┐
└────────────┘        └───────────────┘        └─────────────────────┘

2. The flight (about half a second): the camera flies to Clinical documentation, the rest fades,
   the inside comes up within the box's outline

   ░Scheduling░ ─ ─ ▶ ┌──────── Clinical documentation ─────────┐ ─ ─ ▶ ░Statutory░
                      │ [visit_documentation] [documentation_chase] │
                      └─────────────────────────────────────────┘

3. Inside: the home fills the screen, its neighbours are "doors" on the edges

 Rehmed › Clinical documentation                                              [✕ leave]
┌─────────────────────────────────────────────────────────────────────────────────────┐
│ ◀ Scheduling: visit_completed ──▶ [documentation_chase] ─▶ [documentation_due]      │
│                                                                                     │
│ ◀ Scheduling: visit_booked ──▶ ┌ visit_documentation ┐                              │
│                                │ 3 commands · 3 events│ ──▶ Statutory reporting ▶    │
│              [Specialist]      └──────────────────────┘    visit_closed_clinically   │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

- **Doors:** the neighbouring contracts, pinned to the edges. What comes in is on the left, what goes out on the right.
Each door names the event that passes through it and is tied to the element inside it reaches. A click on a door
goes to the neighbour: the camera flies out and into it.
- **Leaving:** Escape, a click on the path "Rehmed › …", or ✕. The animation runs the other way.
- **A click** selects an element and opens the panel, as today. **Entering** is a gesture of its own.
- **Nothing lost:** inside a contract, a button "show every unit's inside" gives today's full contract graph (7.5).
The reader asks for it, so it does not break the rule of hidden insides.

**Why this way:**

- **Every level has a small layout of its own.** The map is laid out once and never moves; there are no boxes in boxes
in boxes. The risk of jumping cards (12.1) all but goes.
- **One home on the screen at a time.** The design notes' limit, a graph is unreadable past fifteen to twenty nodes,
holds by itself.
- **The animation hides the server's answer time.** The camera moves at once, and the inside arrives meanwhile.
- **The reader keeps their bearings.** The flight shows where they came from; the path and the doors say where they are.
- **The cost:** two contracts' details are never shown at once; neighbours are doors.

### 5.3 Layers

Switches at the top of the canvas, each showing or hiding one kind of thing:

- actors;
- external systems;
- the read side (read models and queries);
- rules (off by default; for AppUnite's computers they are 10 more cards);
- relations between contexts (customer/supplier, anticorruption layer, partnership…);
- events flowing between contracts;
- references to siblings' units ("who holds whose number");
- the numbers from the log.

### 5.4 Processes as metro lines

- A list of the application's processes on the left.
- Turning a process on draws a **coloured line** in the order of its stages, through several contracts at once. For the
clinical visit process: ① `visit_completed` → ② `visit_closed_clinically` → ③ the report to P1.
- **On the map** the line runs through the contracts' boxes: the stations are contracts, and a box shows the numbers of
the stages in it ("①" on Scheduling). **Inside a contract** the line runs through the events themselves and leaves by
a door to the next contract.
- The line carries the **promise's arc** ("within 2 days") and a dotted "or else" for the other way of keeping it (the
service needs no report to P1).
- The line also carries the process's numbers from the log: how many runs, how many broken promises.
- Several lines can be on at once.

### 5.5 Lenses: pictures of another shape

Two of today's pictures are laid out differently from the rest, so they stay as a "show as" switch:

- **on an aggregate:** "commands and events" or **"lifecycle"**, its statuses and the moves between them;
- **on a process:** "line on the map" or **"declared shape"**, its stages in order, with the promise's window.

### 5.6 Finding things

- **A path, "you are here"**, e.g. "Rehmed › Settlement › visit_settlement".
- **Search:** type "cancel" (in the client's words: "odwołaj") and the camera enters where it has to (Scheduling, then
`visit`) and selects the command `cancel_visit`.

### 5.7 The side panel

Unchanged. It already shows every element and every arrow, a contract, a context, a process, a stage and a promise
included.

### 5.8 The "records only" mark

Added recently, with the rules about the core (#272). A unit "records only" when it has events but none of its commands
can be refused, so it decides nothing. In the core, where the business makes its decisions, that is suspicious. The
programme's plan wants the mark on the graph. The subdomain's colour together with the mark shows "a core that decides
nothing" at a glance. In the test material two units get it: Rehmed's `p1_report` and TaxVision's KSeF inbox. Neither
is in the core.

### 5.9 Highlighting on hover (a note, to be worked out later)

Hovering over an element highlights it and its nearest neighbours: its incoming and outgoing arrows, and the elements
at their other ends.

---

## 6. The trace: what follows and what leads here (Filip's idea)

### 6.1 The idea

An event (and other cards) has arrows on both sides:

```
        ◀◀    ◀    [ visit_completed ]    ▶    ▶▶
       whole  one                        one   whole
       chain  step                       step  chain
        up     up                        down  down
```

- ▶ highlights what follows **directly** from the element, ◀ what leads directly to it.
- ▶▶ and ◀◀ show **the whole chain**, across contracts too, at the level the reader is on. On the map, the contracts on
the way and the arrows between them light up. Inside a contract, the cards light up, and the doors the chain leaves
by, with "continued in Statutory reporting". The rest fades.

### 6.2 Is it useful? Very, I think

- It is the developer's question from 2.1: "what does my change affect?". The design notes from August name that very
view for the developer ("dependencies: what does my change affect", `docs/adr/technology-notes.md`).
- The graph cannot answer it today, since every picture stops at its contract's edge.
- EventCatalog has the same in two forms: a focus mode (what comes in, what goes out) and a "how far from the selected
one" slider.
- **The most telling part is comparing a trace with a process.** A real example from Rehmed:
  - The clinical visit process says: ① `visit_completed` → ② `visit_closed_clinically` → ③ the report to P1.
  - ▶▶ from `visit_completed`: the `documentation_chase` process manager starts → sets the `documentation_due` timer →
  when it fires, `create_documentation_overdue_task` → `documentation_overdue_task_created`. **And the chain ends
  there.** Nothing in the system leads to stage ②: a person (the specialist) closes the visit.
  - ▶▶ from `visit_closed_clinically`: it ends the process manager, and through Statutory reporting's policy leads to
  `queue_p1_report`, and an effect sends it to the register. The register's answer (`p1_report_sent`, or the report
  rejected) is recorded by the effect as the system actor `p1_integration`.
  - So the trace shows **where a process depends on a person or an external system**: where a promise can be broken.
  The process owner (2.2) and whoever watches for drift (2.3) get an answer nobody sees today.

### 6.3 What is to be settled

- **Where the arrows are:** on every card it is four buttons times thirty cards, clutter. Proposed: **on the selected
card only**, and the same buttons in the side panel.
- **One step and the whole chain:** both make sense, so two arrows on each side, as in the idea.
- **What counts as "follows":**
  - By default only the chain of causes: event → reaction → command → event, timer → command.
  - Separately, behind a switch, "who reads it": read models, building a unit's state, the boundaries that consult the
  event. Dependencies too, but they trigger no further step.
- **Cycles:** the chain stops at an element already visited.
- **A gap in the data: an external system's answer.** The contract does not declare which event an effect records as
the world's answer, so in the graph's data the trace ends at the effect and the system it calls. It can be carried on
indirectly: the effect calls system X, a system actor stands for X, and that actor records event Y. Whether to show
such an indirect link, and whether as a weaker one ("the system's answer"), is open.
- **Not only events:** a trace makes sense for a command, a reaction and an actor too ("what the reception can set
off").

### 6.4 When

Second, after the basic canvas. A trace is a highlight over a graph already drawn, so it adds well to a finished
canvas. The data is there: every relation it needs is in the graph documents.

---

## 7. Nothing is lost: what shows today, and where it will be

| # | Today | What it shows | Where in the new canvas |
| --- | --- | --- | --- |
| 7.1 | Context map (per domain) | subdomains with their kind, contexts, every external system, the relations between contexts named by pattern (direction, symmetry, separate ways) | the start (5.1) with the "relations between contexts" layer; the subdomain as decision 3 says |
| 7.2 | The actors' table under the map | people and systems apart; a row opens the actor's panel | the "actors" layer and a list of actors in the left bar (people, systems); a click opens the same panel |
| 7.3 | System (per domain) | contracts in their contexts, who consumes whose events (names on the arrows), who holds the number of whose unit, publications and subscriptions, numbers from the log | the start (5.1) with the "events between contracts" and "references to units" layers and the badges |
| 7.4 | Declared shape of a process | stages in order, the events in them, the ending events, "no order claimed inside", promises with their windows and "or else", the systems the events depend on | the process line (5.4) and the "declared shape" lens (5.5). **Off the screen since 13 October; it comes back**, so a gain |
| 7.5 | A contract's full graph with the log | units with commands and events, siblings' events, policies, process managers (start, during the run, end), effects, timers (when they fire), read models, queries, actors (issues, records, asks), systems (called, depended on, gives a field, stands behind an actor), scenario counts ("0" included), what runs after the transaction, numbers on the arrows | inside a contract, with "show every unit's inside" and every layer on (5.2, 5.3) |
| 7.6 | A unit's picture | the state card with its fields (identity, optional), commands, events, siblings' events it consults, invariants, constraints, "emits" and "may be refused" arrows with their scenario counts, "builds" | inside a unit, with the "rules" layer (5.2) |
| 7.7 | An aggregate's lifecycle with the log | the start, statuses (final ones marked), moves named by their event, counts, moves not allowed that happened | the "lifecycle" lens on an aggregate (5.5) |
| 7.8 | The side panel | the details of every element and every arrow | unchanged (5.7) |
| 7.9 | Picking a contract from a list | | search (5.6) and a click on the map; the list may stay |
| 7.10 | Navigation and the access badge above the pictures | moving between screens, "Access: all / read only" | unchanged |

**New content, not shown today:**

- processes and their promises (5.4);
- chains across contracts (6);
- the "records only" mark (5.8);
- badges summing up the drift on the map (5.1).

**Out of scope:** the "Contract status" screen (drift in tables) stays as it is. It is a screen of its own, with the
four questions about whether the code does what the contract says.

---

## 8. Typical questions: today and then

| Question | Today | Then |
| --- | --- | --- |
| What happens after the patient leaves the room? | the system picture → the arrow to Clinical documentation → pick it from the list → find the process manager in its full graph → nothing further shows | select the event → ▶▶ |
| Which way does the clinical visit go, and do we keep the 2 days? | impossible (processes are not on the graph) | turn the process's line on |
| Who may cancel a visit? | pick the contract → find the command in the full graph → click | search "cancel" → the panel |
| Where is something wrong in the application? | go through every contract | the badges on the map → enter the one with a badge |
| Which statuses does a computer have, and how does it move through them? | scroll to the lifecycle under the unit's picture | enter the unit → "show as: lifecycle" |

---

## 9. What we do not build

- **Editing:** the graph is for viewing.
- **The state of the client's business** ("which company has no open July"). The dashboard shows whether the code
matches the contract, not the company's data (`CLAUDE.md`).
- **EventCatalog's newer force-directed layout:** positions drift, and cards with fields do not fit.
- **EventCatalog's focus-mode window:** we have the side panel.
- **A minimap:** judged unnecessary before. Revisited if the canvas turns out too big.
- **A link to a particular view, for now** (Filip's decision, 12 October). When it is needed, e.g. in the EHOS Console,
it is cheap: where the reader is and what is on is held by the server anyway, so it only has to be written into the
page's address.

---

## 10. Is today's way of drawing enough?

### 10.1 How we draw today

On 7 October one of three ways was chosen (`docs/adr/graph-renderer.md`, option C):

- The server renders the cards and the panel, as it renders the rest of the page.
- In the browser only a small script runs: it measures the cards, places them (with the dagre library), draws the
arrows, and pans and zooms.
- Ready graph libraries were set aside: React Flow, which the older EventCatalog is built on, and JointJS.

Why:

- the graph is for viewing only;
- a minimap, zoom buttons and keyboard access were judged unnecessary;
- it is the lightest and fastest;
- the cards and the panel are written in one language.

The record of that decision says outright: **revisit it if the interaction grows well past that**. This plan does.

### 10.2 Assessment

- **Clicks that change what is shown** (enter, leave, a layer, a process, a trace): today's way is enough. A click
goes to the server and a new picture comes back. Locally that is milliseconds; in the Console, over the network, an
estimate (not measured) is 0.1 to 0.3 seconds. Acceptable for a click.
- **What must be immediate** (highlighting on hover, the camera's flight on entering) has to happen in the browser.
The small script can do it, since every card and arrow is on the page. It is an addition to the script, not another
approach.
- **The camera's flight is in the library already.** The pan-and-zoom library we use (d3-zoom) has a smooth flight
built in, as on maps. Nothing has to be added. On entering: the camera moves at once and fades the rest; meanwhile
the server sends the inside; the script lays it out (a small graph, a fraction of a moment), fits it into the box's
outline and cross-fades the outline into it.
- **Laying the cards out stops being a big risk.** Expanding in place, the layout library (dagre) would lay
everything out again on every click, and it handles frames in frames poorly. Entering, every level has a small layout
of its own with no nesting, and the map is laid out once. Should a layout still look poor, ELK is in reserve (another
layout library, better at nesting, but heavy: over 1 MB, the exact size to be checked).

### 10.3 Recommendation

Do not change the way of drawing in advance. First build a **prototype of the hardest part**: entering a home with the
camera's flight and doors on the edges, on the test set (11), and on Rehmed and AppUnite's computers until it exists.
The prototype shows whether the flight is smooth and the insides lay out well; at worst it decides for another
library. The fact documents, the panel and the screen do not depend on it. Another way of drawing would replace only
the script and the cards.

---

## 11. A test set for drawing

### 11.1 Why

Filip's idea (12 October), given its shape on 14 October: one new set in the sandbox, made **only** to test the drawing
on: **a copy of Rehmed, changed to cover the cases the clients' material lacks**. The new graph is checked on it alone;
TaxVision, Rehmed and AppUnite are not mixed with it on one canvas. It is the plan's first step (14).

Because:

- **The clients' material does not cover every case.** It has no:
  - event in two processes at once;
  - event consumed by more than one contract;
  - event renamed when consumed from a sibling;
  - event received from another application;
  - domain with more than five contracts.
- **They must not be forced into the clients' material.** The repository's rule: a client's contracts come from the
workshop material, not from what a test needs.
- **A copy of Rehmed is the simplest start.** Rehmed already has most of what the graph has to show, in a domain we
know.
- **One canvas is always one domain anyway**, one application. That the sandbox's dashboard shows three clients on one
page today is only because one sandbox host registers all three.

### 11.2 What it holds

A copy of Rehmed under a domain of its own, with what Rehmed lacks added:

| Case | In Rehmed | In the copy |
| --- | --- | --- |
| all three kinds of subdomain | yes | kept |
| a context with no contract | yes (configuration) | kept |
| a context with several contracts | no | added |
| more than five contracts | no (five) | at least one more |
| an aggregate with a lifecycle | no | added to one aggregate |
| an aggregate without one | yes | kept |
| dynamic consistency boundaries | yes (two) | kept |
| a contract with several units | no | added |
| policies, process managers with timers, effects, read models, queries, rules, scenarios | yes | kept |
| a unit that records only, outside the core | yes (`p1_report`) | kept |
| a field holding another contract's unit's number, held by several contracts | yes (`visit_id`, three) | kept |
| an event consumed by two or three contracts | no | added |
| an event renamed when consumed | no | added |
| a publication to another application | no | added |
| an event received from another application | no | added |
| two processes sharing an event (crossing metro lines) | no | added |
| a process over one contract | no | added |
| a process with no end | no | added |
| promises with "or else" | yes | kept |
| a large contract, like AppUnite's computers | no (the largest has 28 elements) | grown if cheap; otherwise the scale is tested on AppUnite |

And:

- **Data in the log.** Without it every number is zero, since the development database is empty today. It needs
sample traffic with deliberate drift:
  - a path never taken;
  - a move the lifecycle does not allow;
  - a broken promise;
  - a step that fails;
  - things that wait.
- **Labels.** The copy keeps Rehmed's Polish labels, and what is added is labelled in Polish too, so that the set reads
as one client. The pitfalls of Polish text in `CLAUDE.md` apply. (This follows from copying Rehmed; say so if it should
be otherwise.)
- **Its first line says what it is:** a copy of Rehmed changed to test the graph, not a client's material, as the
invented medical domain in the engine's tests says of itself.

### 11.3 Conditions: on this branch, correct, and in the gate

- **Committed on this branch** (Filip's decision, 14 October, replacing "in `.gitignore`" of 12 October). What becomes
of it is decided when the branch is merged: deleted, moved to a package's tests, or kept as standing material for
drawing.
- **A domain of its own:** its own `name:`, so that no id of it collides with Rehmed's (e.g. `graph_lab.scheduling`),
its own module namespace and its own boundaries.
- **Correct, and in the gate.** It compiles with `--warnings-as-errors` and `mix check` passes, locally and on CI,
since it is committed.
  - **The gain:** three of the sandbox's graph tests go through every registered document. They check that every element
  has a card and a panel, that the log's numbers lay over it, and that the document matches the schema. The set gets
  those checks for free.
  - **The count:** one sandbox test compares the exact count of `mix eh_os_contract.check` findings for the whole
  sandbox (today "0 errors, 31 warnings, 22 notices", `sandbox/test/e10_outputs_test.exs`). The copy brings Rehmed's
  warnings and notices with it, so the branch updates that count, and the update goes with the set when the branch is
  merged.
- **No migration.** Rehmed's read model keeps its rows in a table of its own, and a migration on an unmerged branch
changes the test database of every checkout on the machine (`CLAUDE.md`). The copy's read models must need no new
table.
- **The host's configuration stays as it is.** The sandbox has one supplier of host-given fields, Rehmed's, for the
whole host. The copy either uses no host-given field or works with that supplier unchanged.
- **Traffic goes into the development database**, never the test one (no `MIX_ENV=test mix run`, `CLAUDE.md`).
- **The dashboard shows only the set**, through the existing "exclude a namespace" configuration, as Rehmed is shown
alone today.

### 11.4 What it does not solve

- **A second Rehmed to keep.** Changes to Rehmed are not mirrored in the copy, and the two drift apart. That does not
matter for drawing, and it is weighed when the branch is merged.
- **The renderer package's own tests** still run on documents once taken from the clients' material. Whether to add the
set's documents to them is part of deciding what becomes of it.

---

## 12. Risks

- **12.1 A poor or jumping layout.** Small when entering, since every level has a small layout of its own (10.2). The
prototype checks it.
- **12.2 Processes are not in the graph's data yet.** Without them there are no metro lines and no declared shape. They
have to be added to the graph document first (#220, unblocked: a contract no longer declares a process).
- **12.2a #220 plans a process picture on today's screen itself** (one of its three pull requests: renderer and
screen). That overlaps with this plan's process lines and "declared shape" lens (decision 10).
- **12.3 The graph document's format is released (0.3.0).** Processes and the mark are added to it. First the rule
"the format changes only by addition" has to be written down, so that a reader on an older version (the Console, say)
keeps working.
- **12.4 An assumption in the design notes.** From August: "navigation is per-process, never global"
(`docs/adr/technology-notes.md`). One canvas changes that. The repository's rules ask for a dated amendment, not a
rewrite. The reason behind it, readability, is kept by hidden insides.
- **12.5 Too much at once.** The plan has many parts, and a pull request that cannot be read with attention is not
really reviewed. Hence the stages (14).
- **12.6 The test set is a second Rehmed** (11.4): it drifts from Rehmed and raises the sandbox's count of `check`
findings while it lives on the branch.

---

## 13. Decisions to make

Comment by number.

1. **What the start shows.** The contracts' map with processes as lines (recommended), or processes as nodes with lines
between them? Nobody declares links between processes: they can only share an event or a contract, so lines between
process nodes would be computed, not declared. And the two contracts in no process (TaxVision's document intake,
AppUnite's demands) would not show.
2. **How to go deeper — settled 14 October:** entering with the camera's flight, the inside hidden until entered (5.2).
One detail is open: what shows around a home once inside — doors on the edges (recommended), or the rest of the map,
faded, around it.
3. **Subdomains: frames as today, or a colour and a label on the context?** On the map it is the one place frames could
nest (subdomain → context → contract). A colour is the simpler layout; a frame is today's look.
4. **The trace (6):**
   - in the first version or the second;
   - arrows on the selected card or on every card;
   - whether "who reads it" counts by default.
5. **Today's pictures:** do they go at once, or stay for a while, e.g. as a "classic view"?
6. **The "records only" mark on the graph:** with something else, or as a small step of its own?
7. **The way of drawing:** agree to a prototype before deciding (10.3)?
8. **A mock-up:** before the issue, a clickable HTML mock-up outside the repository, to see how it reads? On the test
set's data (11), and on Rehmed's until it exists.
9. **The test set (11) — settled 14 October:** a copy of Rehmed with the missing cases added, committed on this branch,
its fate decided when the branch is merged. Assumed, to be objected to if wrong: its labels are Polish, as Rehmed's.
10. **How does this fit with #220, "a process module gets a picture"?** Its first pull request (processes in the graph
document) is common to both plans. Its second (a process picture on the screen) can either:
    - be built at once as this plan's process lines and "declared shape" lens in the new canvas (less double work, but
    #220 waits for the canvas);
    - or be built first on today's screen, as #220 plans, and moved into the new canvas later (processes come back to
    the screen sooner, but the picture is built twice).

---

## 14. Order (provisional, no technical detail)

1. The test set for drawing (11): a copy of Rehmed with the missing cases, and traffic in the development database,
committed on this branch.
2. The mock-up, and a prototype of the hardest part on that set (decisions 7 and 8).
3. The decisions of 13.
4. A GitHub issue with this plan, and a short paragraph in `PLAN.md`.
5. Stages, each with its own pull request:
   1. the rule for changing the format, then processes in the graph document (#220's first pull request) and the
   "records only" mark;
   2. the map and entering homes, with today's panel;
   3. layers, search, lenses;
   4. processes as lines;
   5. the trace;
   6. switching the Graph screen over, and the amendment to the design notes.
