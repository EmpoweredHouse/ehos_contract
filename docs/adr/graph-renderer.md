# The graph renderer — what draws a `graph.v1` document

> **Status: accepted**, 7 October 2026: C, as recommended under "Decision". Proposed the same day; the options
> and their costs come first, then the decision. Stage: E13b, step 1 (`PLAN.md`, "E13b — renderer i ekran"),
> pull request [#219](https://github.com/EmpoweredHouse/eh-os-contract/pull/219).

## The problem

After E13a the engine publishes each contract and each domain as a `graph.v1` document, which is a graph of
facts with nodes, relations and scenarios and no pictures, plus a separate overlay with numbers from the log.
E13b builds the package that draws them, `eh_os_contract_graph`. The dashboard (`eh_os_contract_web`) and the
EHOS Console will both use it. The package needs a way to put nodes and arrows on the screen, and this file
compares the ways that were found.

### Who looks at the graph, and for what

Taken from the design record (`docs/adr/architecture.md`, "The approach" and decision 2;
`docs/adr/contract-v2.md` §3; the owner's view, DD L4, in `PLAN.md`):

1. **The developer and the reviewer of a change** read the contract as a picture rather than as code: what
  connects to what, with descriptions and fields. No log is needed.
2. **The process owner on the client's side** confirms the rules, the scenarios and the promises in the
  client's own words. For this reader the contract is the agreement about the logic.
3. **Whoever watches for drift**, later on, reads the same picture with the overlay laid over it: paths never
  taken, numbers on the arrows.
4. **The CTO in the Console** sees every process of an application together.

The graph is **for viewing only**. Nobody drags, connects or edits anything on it.

### What every option must do

- Lay out the nodes and arrows automatically from the document, for any contract or domain, including ones
not written yet.
- Draw a **card** for each node: the rectangle for a command, an event or a policy, with its label, its name
and its fields.
- Draw each relation as an arrow with a label, plus the overlay's marks (counts, "never taken").
- On a click on a card or an arrow, open its panel. **Panels are HEEx on the server** (decided 5 October): a
click goes to the LiveView, and the LiveView renders the panel.
- Pan, zoom, and highlight what touches the current selection.



### Fixed constraints

- **The CSP** `default-src 'self'`**.** EHOS sets it, and the sandbox host sets it too. The browser refuses
scripts and styles from elsewhere, inline `<style>`, a `style` attribute written as markup or through
`setAttribute`, and `eval`. Setting a style through the CSSOM (`element.style.x = …`, a constructed
stylesheet) is allowed.
- **The host installs nothing JavaScript.** The package's JS is built with esbuild by this repository and
committed under `priv/static`, as `eh_os_contract_web` does today. A host adds the Mix dependency, serves the
file and registers the hook.
- **The package depends on** `phoenix_live_view` **only**, not on the engine. Both hosts run LiveView.
- **It is redistributed.** The bundle ships inside a package installed by others, from git and later from
Hex, so every library in it must allow redistribution.



## What is the same whatever is chosen

- **Positions come from a layout library, not from the drawing library.** dagre (MIT) today, ELK (EPL-2.0)
if groups such as stages and units need it. Given the same document and the same card sizes, every option
puts the nodes in the same places. In the prototype A and C produced identical layouts.
- **The look is ours** in every option: card content, colours, kinds, labels, CSS.
- **Bundle size is a cost, not a limit.** Hex allows 16 MiB compressed and 128 MiB uncompressed (the
`hex_core` defaults), and `eh_os_contract_web` ships a 3.5 MB `mermaid.min.js` today. What size changes is
the first visit to the screen: the download, then the parse. After that the file is cached until the next
release of the package. The sandbox serves static files with `gzip: false`, so unless a proxy compresses
them, the minified size is what travels, not the gzipped size.
- **Readability of a large contract is a matter of views, not of the library.** AppUnite `computers` (62
nodes, 111 relations) was equally unreadable fitted to the screen in A and in C. A large contract needs
filtering, grouping and focus. That belongs to the specification of the views, which is not settled.



## The options



### A. React Flow (`@xyflow/react`)

**How it works.** React Flow is a library for node graphs built on React. The whole canvas, with its cards,
arrows, pan and zoom, is a React component tree mounted by our LiveView hook into a container LiveView
ignores (`phx-update="ignore"`). Cards are React components written in JSX, which esbuild turns into plain
JS. A click is pushed to the LiveView, which renders the panel.

**For**

- **Interaction and visual behaviour come ready made.** Zoom controls, a minimap, animated moves of the
viewport, several edge shapes, hover and selection states, keyboard access and ARIA, and rendering only what
is on screen for large graphs. Anything visual beyond the cards is usually a prop or a documented example.
- **Mature and widely used**, well documented, MIT.
- **No conflict with LiveView under the CSP.** React owns its part of the page, so LiveView's patches never
touch it. The prototype had no violation.

**Against**

- **What the reader sees is written in two places.** The cards are JSX components, while the panels and the
rest of the dashboard are HEEx. Every option has some JS. The difference is what the JS describes: in A it
describes the cards themselves (their markup, their content, their states), so a change to what a card shows
is a change in JSX. Components of the design system (`ehos_design`, HEEx) cannot be used in a card. They are
rebuilt in JSX, and only the CSS is shared.
- **State in two places.** React holds the selection, and the server learns of it through an event. When the
server needs to change the graph (a new overlay, a selection made from the panel), it sends an event to the
hook, which hands it to React.
- **Dependencies to maintain.** React, React Flow and their releases and security fixes reach a host only
through a new release of this package. A host that uses React itself would load two copies.
- **Attribution, asked rather than required.** A small "React Flow" link shows under the graph. Nothing
enforces it: the MIT licence allows removing it, and one option (`proOptions.hideAttribution`) does. The
authors ask that whoever removes it in a commercial product subscribes to React Flow Pro (from $169 a month).
It is a request, and whether to honour it is a matter of fairness, not of law.
- **A large bundle**, close to B's and about four times C's on top of LiveView (below).



### B. JointJS (`@joint/core`)

**How it works.** JointJS is a diagramming library in plain JS, with no framework, drawing in SVG. Our hook
builds a JointJS graph from the document. Cards are JointJS elements defined in JS: in the prototype, HTML
inside SVG (`foreignObject`), built with `textContent` so that the client's text is never parsed as HTML.
Layout comes from `@joint/layout-directed-graph`, which is dagre (MPL-2.0). The `manhattan` router then routes
each arrow around the cards. A click on a card or an arrow is pushed to the LiveView, and selection comes back
as JointJS highlighters.

**For**

- **The most capable arrows of the three, out of the box.** Its free core has routers that take an arrow
around cards instead of through them (`manhattan`, `metro`), orthogonal and right-angle routing, connectors
that jump over crossing lines, highlighters (class, stroke, mask, opacity) and tools on links. In A and C each
of these is our own work. A click on an arrow needed no code beyond the event handler.
- **No React**, so one runtime less than A.
- **Mature**, a library made for diagrams of exactly this kind.

**Against**

- **Cards are not HEEx.** They are defined in JS as SVG or HTML templates, so the design system has the same
problem as in A, without JSX.
- **State in two places**, as in A: the JointJS model in the browser, the selection on the server.
- **MPL-2.0.** Using it unmodified in a closed product is allowed, but a change to one of its files must be
published. Many ready interface pieces (a navigator or minimap, inspectors, more than 40 components) are in
the paid JointJS+, at $2,990 per developer.
- **The CSP needs one override.** The paper prepends a `<style>` to its SVG, which the CSP refuses (one
violation per page). The scan of the bundle missed it. A subclass with `stylesheet: null`, and the one rule
moved to our CSS, removed it.
- **Routing around cards costs time, and the routes need care.** The router runs after the layout, so dagre
leaves room for labels where the arrows no longer go, and some labels land on cards. Many arrows share one
orthogonal trunk, which makes it hard to follow one of them. Mounting took 0.3 to 0.4 s for a typical
contract and 1.2 to 2 s for AppUnite `computers` (111 relations), depending on the router's step, against
under 35 ms in A and C. Each of these is tunable, but it is tuning.
- **The largest bundle of the three**, since dagre comes again through the layout package (below).



### C. Cards in HEEx and our own thin drawing layer

**How it works.** The server renders every card and every arrow's label in HEEx, as it renders the panels.
A hook of about 100 lines of plain JS measures them, runs dagre, places them, draws the arrows in SVG,
and pans and zooms with `d3-zoom`. Selection and the overlay are classes the server puts in the HEEx.

**For**

- **One UI language.** Cards, labels and panels are HEEx and can use the design system's components
directly.
- **State on the server alone.** A selection or an overlay is a class in the template, and LiveView sends the
difference.
- **Arrows follow the layout's routes exactly**, including ELK's orthogonal routes and groups, without extra
work.
- **The smallest bundle**, and two small dependencies (dagre, `d3-zoom`), both MIT. No attribution.

**Against**

- **Every interaction and visual effect beyond the basics is ours to write.** Zoom buttons, a minimap,
animated moves of the viewport, keyboard access, rendering only what is on screen, edge shapes, routes that
avoid cards, hover effects. Each is possible in HEEx, CSS and a few lines of JS, but each costs time that A
or B do not spend, and its quality is ours to keep. Three examples from the prototype: clickable arrows and
arrow labels took about 50 lines (HEEx and JS) and one round of fixes; the labels follow a smoothed curve
that sometimes runs beside them rather than through them; and an animation of the arrows touching the
selection, dashes flowing in the arrow's direction, took five lines of CSS (and stops for a reader who asks
the system for reduced motion).
- **LiveView and the CSP need care.** LiveView patches the cards it rendered, and resets a position set in a
`style` attribute. Its own remedy, `JS.ignore_attributes`, restores the attribute through `setAttribute`,
which the CSP refuses: one violation per card in the prototype. Positions therefore live in a constructed
stylesheet (CSSOM), the same means EG3 used for Mermaid. That is a rule of the package to keep, with a test.
- **Defects of a kind a library has already met.** Writing the prototype hit three: the one above, a
dashed-line style that also cut gaps in the arrows' invisible click area, and that click area left without
`fill: none` and drawn black. Each was a line to fix. Each would have stayed unseen without looking at the
page in a browser.



## Side by side


|                                         | A. React Flow                    | B. JointJS                            | C. HEEx cards                                                   |
| --------------------------------------- | -------------------------------- | ------------------------------------- | --------------------------------------------------------------- |
| Cards written in                        | JSX (React)                      | JS: SVG or HTML templates             | HEEx, like the panels                                           |
| Design-system components in cards       | rebuilt in JSX, CSS shared       | rebuilt in JS, CSS shared             | used directly                                                   |
| Who holds what is selected              | React, synced with the server    | JointJS model, synced with the server | the server                                                      |
| Interactions and visual effects         | many ready                       | many ready, some paid (JointJS+)      | ours to write, more time per feature                            |
| Arrows                                  | curves between handles; the layout's routes with a small custom edge | routes that avoid cards, jump-overs   | exactly the layout's routes                                     |
| Animated arrows                         | a prop (`animated`)              | CSS                                   | CSS, five lines (checked)                                       |
| CSP under LiveView                      | no violation                     | no violation, with `stylesheet: null` | no violation, with the stylesheet rule                          |
| Click on an arrow                       | not built in the prototype       | ready (an event handler)              | built: an invisible wide stroke, about 50 lines with the labels |
| Mount, largest document (111 relations) | under 35 ms                      | 1.2 to 2 s (router)                   | under 35 ms                                                     |
| Bundle on top of LiveView, gzip         | +142 KB                          | +148 KB                               | +33 KB                                                          |
| Same, minified, uncompressed            | about 450 KB                     | about 480 KB                          | about 100 KB                                                    |
| Licences                                | MIT, attribution asked           | MPL-2.0 (core), paid add-ons          | MIT                                                             |
| Large graphs                            | renders only what is visible     | SVG, no virtualisation in core        | all cards in the DOM; `content-visibility` would help           |




## Measured in the prototype (7 October 2026)

Not committed. It was a temporary LiveView on the sandbox host under `default-src 'self'`, given the same
documents, the same dagre layout, the same card CSS and the same HEEx panel in A, B and C. The overlay numbers
were invented, since the dev database has no runs. Headless Chrome went through 14 documents (11 contracts, 3
domains) in each variant.

- Laid out without an error: 14 of 14 in each variant.
- CSP violations: A 0; B 0 (before `stylesheet: null`: one per page); C 0 (before the stylesheet rule: one per
card).
- A click on a card gives the server's panel, and positions survive LiveView's patch: all three. A click on
an arrow gives the relation's panel: B and C (not built in A).
- Labels overlapping a card or another label: C 0 on 10 documents, the largest with 111 relations. B: some, by
eye, where the router moved an arrow away from the room dagre left for its label.
- Mount: A and C under 35 ms; B 0.3 to 0.4 s typical, 1.2 to 2 s on the largest, almost all of it routing.
- Bundles, minified / gzip: LiveView alone 141 / 43 KB; A 587 / 185 KB; B 622 / 191 KB; C 238 / 76 KB.



## Set aside, and why


| Candidate                      | Why it is not an option                                                                                                                                                                                                                                                                                                               |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `@eventcatalog/visualiser`     | Built on React Flow, so A with EventCatalog's opinions. Its kinds are EventCatalog's (service, channel, flow…), and process managers, timers, stages, promises and statuses are missing. It is made for the EventCatalog application, its 5.0 was in beta on this date, it bundles Mermaid (4.7 MB minified) and it injects `<style>` |
| Svelte Flow (`@xyflow/svelte`) | A without React, but Svelte needs a compiler plugin, which the Elixir `esbuild` package cannot run. A Node build script would be needed                                                                                                                                                                                               |
| Cytoscape.js, sigma.js         | Draw on canvas or WebGL: for network analysis and very large graphs. Cards with fields, selectable text and CSS are hard                                                                                                                                                                                                              |
| maxGraph                       | Uses `eval`, injects `<style>` and sets `style` attributes; still 0.x                                                                                                                                                                                                                                                                 |
| AntV X6                        | Possible, but injects its CSS at run time, is heavier (168 KB gzip) and its documentation is mostly Chinese                                                                                                                                                                                                                           |
| GoJS, yFiles                   | Commercial per-developer licences that do not allow redistribution in a published package                                                                                                                                                                                                                                             |




## What the choice turns on

- **How much interaction beyond viewing will be wanted, and how soon.** Animations, a minimap, routes around
cards, editing one day. The more of it, the more A and B save. Viewing alone is what C covers.
- **Whether the design system is to be used inside the cards** or only in the panels and screens.
- **How much the arrows matter**: routes that avoid cards are ready in B and are work in A and C.
- **Whether one UI language on the server** is worth writing the visual layer ourselves.
- **For B, whether routes around cards are worth the routing time and its tuning** (labels, shared trunks).



## Decision

**C: cards and labels in HEEx, our own thin drawing layer**, with dagre for the layout and `d3-zoom` for pan
and zoom. Recommended on 7 October 2026, for the user to confirm.

> **7 October 2026: accepted by the user.** One correction, found when the libraries were fetched for the
> package: `d3-zoom` and seven of the eight d3 modules it pulls in are ISC, and `d3-ease` is BSD-3-Clause, not
> MIT. Both are as permissive and ask for the same notice, so nothing above changes.

**Why, given what the graph is for.** The graph is for viewing only, and the user ruled out what A and B
mostly save: zoom buttons, a minimap and keyboard access are not needed, and nothing is dragged, connected or
edited. What is wanted beyond the basics proved cheap in C in the prototype: clickable arrows and labels
(about 50 lines) and animated arrows (five lines of CSS). That leaves the differences that last:

- what the reader sees is written once, in HEEx, with the design system's components, where the panels are;
- what is selected and what the overlay says live on the server alone;
- arrows follow the layout's routes exactly, which keeps ELK's groups and orthogonal routes open without a
  custom edge;
- the lightest and fastest of the three (+33 KB gzip, under 35 ms on the largest document), two MIT
  dependencies, and no attribution.

**Why not B.** Its one clear advantage, arrows routed around cards, cost 1.2 to 2 s on the largest document
and left labels on cards and many arrows on shared trunks. It is not needed to read a contract, and it is
tuning before it is a gain. Its cards are not HEEx either.

**Why not A.** Its strength is ready interaction, and what the graph needs of it is either not needed or cheap
in C. It would put the cards in JSX, the selection in React, and React's releases into this package's
maintenance.

**What C has to carry into the package (E13b, step 2).**

- Positions in a constructed stylesheet, never in a `style` attribute, with a test that the rendered page sets
  none: LiveView's patches and the CSP are why.
- An arrow's click area that no visible style reaches (no dash, no fill), and labels as HEEx elements measured
  before the layout.
- Each change to the drawing layer looked at in a browser under `default-src 'self'`: all three defects of the
  prototype passed the numeric checks and showed only on screen.

**When to revisit.** If the graph is to be edited, or if interaction grows past what a few lines each can
give (a minimap, keyboard navigation, very large graphs that need rendering only what is visible). The
document, the panels and the screens do not depend on the drawing layer, so A or B would replace the hook and
the cards, not the package.

## Amendment, 8 October 2026: what moves on every frame is a Web Animation

"Positions in a constructed stylesheet" (above) held for what the layout sets once, and was wrong for what
changes on every frame. The zoom was a rule written to a constructed stylesheet on every frame of a pan or a
zoom, and so, later, was the panel's width while its edge was dragged. Chrome restyles only what a changed rule
can match; WebKit styles the whole page again whenever a stylesheet changes, so on AppUnite's `computers` (nine
canvases, about 1,250 elements) Safari stuttered on every pan, zoom and drag while Chrome ran smoothly. A Web
Animation (`element.animate(…, {duration: 0, fill: "forwards"})`, its keyframes set again on each frame) holds
the value instead: the policy allows it, being neither an attribute nor a stylesheet, LiveView's patches keep
it, being no attribute, and a change restyles the one element. So the rule the package carries is now:
**positions and sizes in a constructed stylesheet, written when the layout changes; what changes on every frame
in a Web Animation; never a `style` attribute.** The user confirmed the difference in Safari. A custom property
on `:root`, written on every frame, cost Chrome too — every element inherits it — and was replaced the same day
by a rule on the one element. Recorded in `PLAN.md`, "E13b, batch 4 — the panels (8 October)";
[#219](https://github.com/EmpoweredHouse/eh-os-contract/pull/219).

## Amendment, 9 October 2026: the dependencies' licences

The decision gave C "two MIT dependencies, and no attribution". Both halves were wrong. dagre, with the
graphlib it carries, is MIT; d3-zoom and the d3 modules it imports are ISC, and d3-ease BSD-3-Clause. All three
licences ask that their notice travel with the code. The renderer's `NOTICE` has carried them since the package
was built. The dashboard's `NOTICE` has carried them since 9 October: its `app.js` bundles the renderer's script,
and it had named only the fonts. Neither fact moves the choice, since all three licences are permissive.
Recorded in `PLAN.md`, "E13 — pushed, `main` merged again, and an audit against `main`'s conventions (9 October)";
[#217](https://github.com/EmpoweredHouse/eh-os-contract/pull/217).

## Amendment, 15 October 2026: one canvas, two viewpoints, and the Console draws with the same package

The decision drew one picture at a time, chosen from a list, and left open where a reader moves between them.
Three things were decided for stage G1, the user's decisions of 15 October.

**Two viewpoints.** The canvas shows either the **structure**, the context map, then a contract, then a unit
(with an aggregate's lifecycle as a switch on it), or the **processes**, a list, then one process laid out by
its stages. A path, the search and the legend are common to both, and the two are linked both ways: an event's
card in a process leads to its contract, and a contract to the processes its events take part in. The two
answer different questions and need different layouts. The structure says who owns what, what is sent and who
listens, does not change over time, and is grouped by owner. A process says what happens, in order, in one case
(a visit, a month), and runs across several contracts at once. An event has one home in the structure and may
stand in a stage of several processes. EventCatalog separates the same two: a flow has a page and a diagram of
its own, whose steps point at services and messages documented elsewhere. *Rejected:* processes drawn as lines
across the structure's map (the plan on #302), since one picture cannot have both layouts and several processes
become crossing lines; a page per element as EventCatalog has, since we keep one canvas with navigation.

**The renderer holds the navigation.** The canvas, its path, its viewpoints and the links between them are a
component of this package, not of the dashboard's Graph screen, and draw only what the `graph.v1` documents and
their overlays say. An application shows its own contracts in its dashboard; the EHOS Console reads the same
documents from each application's JSON API and draws them with the same component, so the two never differ.
*Rejected:* navigation on the dashboard's screen, which the Console would have to write again.

**The Console joins applications; the package says how.** One application is one domain, and a domain knows of
others only what it publishes and what it subscribes to. A function of this package joins several applications'
domain documents by publication name into one landscape the same canvas draws; the Console fetches the documents
and owns the screen. A process across applications does not exist in the model: between applications there is
only publication and subscription. Since the Console reads documents from applications on different versions of
the library, `graph.v1` changes only by addition.

Recorded on [#297](https://github.com/EmpoweredHouse/eh-os-contract/issues/297).

## Amendment, 15 October 2026 (evening): the landscape joins domains, not applications

The amendment above said one application is one domain. It is not: the sandbox is one application to EHOS with
four domains, and nothing in the engine stops an application from having several. A publication's name on the
wire is the same fact whether the two domains that share it are in one application or two, so the joining
function (`EhOsContract.GraphRenderer.Landscape.join/1`) takes each application's name with one of its domain
documents, a box per domain document, and joins every pair by the name on the wire. A box holds only the contracts
that publish or subscribe, and says how many others its domain has. *Rejected:* joining only documents of
different applications, which would hide a publication between two domains of one; every contract of every
domain in its box, hundreds of cards with no arrow once the Console sees a dozen applications.

Recorded on [#297](https://github.com/EmpoweredHouse/eh-os-contract/issues/297#issuecomment-6202758132).

## Amendment, 19 October 2026: the Console takes the documents with a deployment

The first amendment of 15 October says the Console reads each application's documents from its JSON API and
fetches them. EHOS decided otherwise, in [D-123](https://github.com/EmpoweredHouse/eh-os/blob/main/docs/adr/0123-ehos-takes-each-application-s-domain-graph-documents-with-its-deployment-and-joins-them-into-a-landscape-when-someone-reads-it.md), which the user accepted on 19 October. An
application's pipeline writes each domain's `graph.v1` document from the commit it builds
(`mix eh_os_contract.graph --domain <name>`) and submits them with the deployment, beside the image and the
manifest. EHOS keeps them with that deployment and, when someone reads an environment's landscape, joins the
documents of each application's latest active deployment there with `Landscape.join/1`, keeping nothing joined.
EHOS calls no application's JSON API for them: an application's `GET <mount>/graph/…`, where it mounts the JSON
API, serves whoever its resolver lets in, and its own dashboard reads the engine directly.

What follows on this side:

- `graph.v1` still changes only by addition, since EHOS keeps what it knows of a document and drops the rest.
- A document's `schema` keeps the form `eh_os_contract.graph.v<n>`: EHOS skips, rather than refuses, one that
  names another version, so a newer engine does not stop a deployment by its version alone, and refuses one of
  any other form.
- The rule that only the domain named as the application publishes, under names that begin with the
  application's name and a dot, stays as the engine holds it: the prefix when the contracts compile, the
  publishing domain when the application starts (`EhOsContract.Auth`). EHOS holds each document to the same
  rule as it arrives, and refuses the deployment otherwise.
- A release's `release.json` names the document's version among what the engine produces,
  `eh_os_contract.graph/v1`, as EHOS's `releases.md` names the interface.

Recorded on [#344](https://github.com/EmpoweredHouse/eh-os-contract/issues/344).

## Sources

- npm registry, versions, licences and dependencies as of 7 October 2026; bundles built and scanned with
esbuild in a scratch directory.
- [React Flow — remove attribution](https://reactflow.dev/learn/troubleshooting/remove-attribution)
- [JointJS pricing](https://www.jointjs.com/pricing); `@joint/core` 4.3.3 source (`src/routers`,
`src/connectors`, `src/highlighters`)
- [EventCatalog licences](https://eventcatalog.dev/docs/development/deployment/licenses)
- `hex_core` [defaults](https://github.com/hexpm/hex_core/blob/main/src/hex_core.erl) (`tarball_max_size`,
`tarball_max_uncompressed_size`)

