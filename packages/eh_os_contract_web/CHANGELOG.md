# Changelog

The rule this package follows is the one written in `packages/eh_os_contract/CHANGELOG.md`:
a change that can move something the dashboard reports raises the minor version and
gets a line here.

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

## [0.11.0] - 2026-11-22

### Changed

- **Breaking:** **the graph renderer is required at `~> 0.10.0`**, however it is fetched: by version
  from Hex, and also when this package comes from git or a path. A host with an older renderer is
  refused at `mix deps.get`, so a host moves this package and the renderer together. The engine is
  still required at `~> 0.15.0`.

### Fixed

- The dashboard's script has the client of Phoenix LiveView 1.2.14 and of Phoenix 1.8.17. It had the
  clients of 1.2.10 and 1.8.12, so with a server of 1.2.14 the browser console showed a warning that
  the versions of LiveView differ. If your application uses another version of LiveView, the console
  still shows this warning: the script holds one client.

### Security

- **Breaking:** this package requires Phoenix LiveView `~> 1.1.34 or >= 1.2.14 and < 2.0.0`, not
  `~> 1.1`. Earlier versions let a client skip the `on_mount` hooks of a `live_session`
  (EEF-CVE-2026-126334, GHSA-v4p7-3pm2-wq6c). The client joins a LiveView without its `"url"`. If
  your lock holds an earlier version, `mix compile` refuses it until you run `mix deps.get`, which
  moves the lock to a fixed version. If another requirement holds the old version, `mix deps.get`
  fails, and `mix deps.tree` shows which requirement (#659, #660).
- The dashboard was not exposed to this advisory. On the dashboard, only a client that loaded the
  page with access can skip the hooks. The access check is the `on_mount` hook that
  `eh_os_contract_dashboard/2` installs. This hook also sets the access and the base path that both
  screens read. Without the hook, each screen fails before it sends anything to the client. A test
  now holds this (#660).

## [0.10.0] - 2026-11-20

### Changed

- **Breaking:** **the engine is required at `~> 0.15.0`**, however it is fetched: by version from Hex, and also
  when this package comes from git or a path. A host with an older engine is refused at `mix deps.get`.
  The engine 0.15.0 needs its storage at version 6: add a migration that calls
  `EhOsContract.Migrations.up(version: 6)`.

## [0.9.0] - 2026-11-05

### Changed

- **Breaking:** **the engine is required at `~> 0.14.0`**, however it is fetched: by version from Hex, and also
  when this package comes from git or a path. A host with an older engine is refused at `mix deps.get`.
- **The README is split into pages by what a reader asks** (#517). The README says what the dashboard
  shows. Two how-tos, `docs/mount-the-dashboard.md` and `docs/who-can-see-it.md`, and a Reference
  page, `docs/api.md`, take the rest, and hexdocs shows them. The pages now say that
  `/api/conformance` also takes `process=<id>`, and that it answers 400, not 404, for a contract or
  a process module it does not know. They also say that `/api/model` is an index with the schema
  `eh_os_contract.model-index.v2`, and that only a graph document answers 304 to `If-None-Match`.
  The options of the macro, the redirect of the mount path and the exact `at:` of the assets are
  new on the pages. Links change: the section of the README on the API is now `docs/api.md`.

## [0.8.0] - 2026-10-29

### Changed

- **Breaking:** **the engine is required at `~> 0.13.0` and the graph renderer at `~> 0.9.0`**, however they are
  fetched: by version from Hex, and also when this package comes from git or a path. A host with an older engine
  or renderer is refused at `mix deps.get`. The dashboard's committed `priv/static/assets/` carry the renderer's
  hook, which needs 0.9.0's markup, so a host moves the two together.
- **The dashboard's graph has its zoom in one control in the picture's corner, and a box that opens a contract, a
  unit or a process ends its title in a mark** (#489, #488), as the renderer it draws with now does; a box with
  no card no longer widens on each update.
- **The dashboard's panel folds the facts of the code under "Technical details"** (#490), as the renderer it draws
  with now does; `priv/static/assets/app.css` is rebuilt with it.
- **The dashboard's graph has one path and no switch of who reads** (#490): the explorer it draws with lost its
  "Structure" / "Processes" tabs, the processes being a step of the path, and its "Engineering" / "Owner"
  switch; each place says in a line what it shows. `priv/static/assets/app.css` is rebuilt with it.

## [0.7.0] - 2026-10-27

### Changed

- **Breaking:** **the engine is required at `~> 0.12.0`**, however it is fetched: by version from Hex, and also
  when this package comes from git or a path. A host with an older engine is refused at `mix deps.get`.

## [0.6.0] - 2026-10-26

### Changed

- **Breaking:** **the engine is required at `~> 0.11.0` and the graph renderer at `~> 0.8.0`**, however they are
  fetched: by version from Hex, and also when this package comes from git or a path. A host with an older engine
  or renderer is refused at `mix deps.get`. The dashboard draws what they add: a command's scenario refused on a
  value's invariant (#458) and a scenario that records an event (#430).

## [0.5.0] - 2026-10-24

### Changed

- **Breaking:** **the engine is required at `~> 0.10.0` and the graph renderer at `~> 0.7.0`** (#421), however they are fetched:
  by version from Hex, and also when this package comes from git or a path, where Mix now holds their versions to
  these. A host with an older engine or renderer is refused at `mix deps.get`.
- **`esbuild` is no longer a host's dependency** (#421). Only `mix assets.build` runs it, in this package's own
  development, and its output is committed.

### Fixed

- **The dashboard draws the graph as `eh_os_contract_graph` 0.7.0 does.** Its bundled script and stylesheet were
  built from the renderer as it stood on 16 October, so three of its later changes were missing here: a landscape
  of domains with nothing on the wire lay its empty boxes on top of one another, an empty box's title could be cut
  short by a fraction of a pixel, and a panel's link to a host's page was styled as plain text.

## [0.4.0] - 2026-10-16

### Added

- **The Graph screen has a switch "Engineering / Owner"** (plan DD, stage L4, eh-os-contract#326): read as the
  owner, the pictures and the panel show the client's labels and the numbers from the log, and nothing of the
  engineering — no delivery, idempotency, correlation keys or names in code. The screen starts as the engineer
  reads it, as before.

- **A contract's status page says what changed since the previous deployment** (plan DD, stage V5,
  eh-os-contract#322), as the text report does, and a deploy that changed only the words says so: "Only the words
  changed since the previous deployment, not the agreement". A process module's says it too.

- **The Graph screen's process picture shows the stages runs entered out of order** (plan DD, stage O2,
  eh-os-contract#319): an arrow from the later stage back to the earlier one, with how many runs, beside the
  sentence the status page already gave.

## [0.3.0] - 2026-10-16

### Added

- **The graph screen's map says where to go in** (plan DD, stage G1, eh-os-contract#297): each contract's card
  on a domain's system says how many of its declared paths were never taken and how many moves it does not allow
  happened. Moves no verdict.

- **The graph screen is one explorer per domain** (plan DD, stage G1, eh-os-contract#297): the structure and the
  processes as two tabs of one canvas with a path, instead of every domain's map and system, a selector, the
  selected contract's pictures and each unit stacked on one page; the panel opens a contract, a unit or an
  event's contract. Each picture's document and the log's numbers over it are built when the reader enters
  it, in the background — the log only for a picture that draws it — so opening the screen counts the log for
  each domain's system alone, not for a contract the reader never opens. Moves no verdict.

- **The graph screen's pictures can be searched, focused and zoomed** (plan DD, stage G1, eh-os-contract#297):
  each has a bar with a search that finds a card by its words and moves to it, focus on the selection's
  neighbourhood, a switch between the declaration alone and with the log, and zoom buttons; a large picture
  starts at a readable scale instead of shrunk to fit. Moves no verdict.

- **The graph screen draws cards of their kind, with a legend** (plan DD, stage G1, eh-os-contract#297): each card
  has a badge with its kind's icon, the client's label, the name in code and, where the picture does not say it,
  the contract it is declared in or that it comes from another application; each kind has a colour in both themes;
  a legend under each picture says what its colours, icons and arrows mean. Moves no verdict.

- **The graph screen draws process modules** (plan DD, stage P2e, eh-os-contract#220). Its selector lists them
  beside the contracts, each kind in a group of its own and each by its id; a process module selected is drawn as
  its stages, the events each includes and its promises, with its runs, each event's occurrences and each
  promise's verdicts from the log. Each domain's system view draws its process modules, the contracts whose
  events each includes, the actor accountable for each and their runs. Moves no verdict.

- **A process module's graph over HTTP** (plan DD, stage P2e, eh-os-contract#220): `GET <mount>/graph/process/<id>`
  serves its `graph.v1` document, with its digest as the `ETag` and `304` for a request that holds it, and
  `GET <mount>/graph/process/<id>/overlay?since=…&until=…` what the log says over it: its runs, how often each event
  happened and each promise's verdicts. A process module has its own path because its id may be a contract's. An
  id no process module has is `404`. The `/graph` index lists the process modules under `processes`. Moves no
  verdict.

- **The status screen shows each process module's report** (plan DD, stage P2e, eh-os-contract#220), after the
  contracts, in the sentences of `mix eh_os_contract.report`: its version and since when it is deployed, the actor
  accountable for it, its runs in the period and what one run is ("one per visit_id"), its confirmed deadline and
  the runs measured against it, the runs that entered a stage out of order, and each confirmed promise with its
  verdict, coloured as a contract's promise was, and what changed since the previous version. The process modules'
  reports are computed once the page connects; the static render says they will be. Moves no verdict.

### Changed

- **Breaking:** `<mount>/graph/<contract>` serves a contract's document without the kinds of a process — no
  `process`, `stage` or `promise` nodes, no `accountable_for`, `opens`, `fulfils` or `or_else` relations, all empty
  since a contract declares no process (engine, plan DD, stage P2e, eh-os-contract#220). A reader holding the
  document to the schema shipped with the engine's 0.3.0 refuses it: take the schema with the engine. Moves no
  verdict.
- **Breaking:** `<mount>/graph/domain/<module>` serves the domain's document with its process modules — a
  `process` node each, an `includes` relation to each contract whose events it includes, the actor
  `accountable_for` it — and its overlay with each one's runs (engine, plan DD, stage P2e, eh-os-contract#220). A
  reader holding the document to the schema shipped with the engine's 0.3.0 refuses the new keys: take the schema
  with the engine. The index's domain digests are those of these documents. Moves no verdict.

### Removed

- **Breaking:** `<mount>/model/<id>` serves a contract's model without `process`, and its events without `stage`
  and `terminal`, because a contract can no longer declare a process (engine, plan DD, stage P2h,
  eh-os-contract#221). A consumer of the model reads a run's stages, endings and promises from a process module
  once the API serves process documents. The digests and versions of existing contracts do not move. `graph.v1`
  keeps its process, stage and promise kinds, empty in a contract's document. Moves no verdict.
- **The contract status screen no longer shows a contract's process** — its runs, accountable, duration and
  promises — and the graph screen no longer draws a contract's declared process shape or names the process beside
  the contract in its selector (plan DD, stage P2h, eh-os-contract#221). A contract has none any more; a process
  module's screens come with P2e (eh-os-contract#220). Moves no verdict.

## [0.2.0] - 2026-10-11

### Added

- **The graph documents over HTTP** (plan E13, #217). `eh_os_contract_api/2` serves `GET <mount>/graph` (an index
  of contracts — each `contract`, its id, with its `module` — and domains, with their versions and digests),
  `<mount>/graph/<contract id>` (the contract's `graph.v1` document, its digest as the `ETag`, `304` on
  `If-None-Match`), `<mount>/graph/<contract id>/overlay?since=…&until=…` (what the log says over it), and
  `<mount>/graph/domain/<domain module>` with its overlay, behind the same resolver as `/model`. A contract is
  named by its `id:`, as the other APIs name it, and a module's name is an unknown contract; a domain, which has
  no id, by its module. What the registry does not hold is `404`, and an overlay whose `since` is after its
  `until` is `400`. Moves no verdict.

- **`<mount>/conformance?process=<id>` serves a process module's report** (plan DD, P2w, eh-os-contract#259, agreed
  with EHOS). The report keeps the schema `eh_os_contract.conformance.v3` and has
  `"process"` where a contract's has `"contract"`. An unknown process is 400, and so is naming a contract and a
  process at once. A request with neither, or with `contract=`, answers as before.

- **The API mount serves OpenAPI 3.1.2 documents** at `/openapi` and `/openapi/:contract`, with one
  command-and-query document per v2 contract and its digest as the `ETag`. The host's existing resolver
  protects both routes. Repeated query keys are the documented list encoding; structured parameters use
  deep-object keys, and erased personal fields in rows are nullable.

- **The API mount serves v2 model documents** at `/model` and `/model/:contract`. Each document is
  `eh_os_contract.model.v1`, includes the derived capability surface, and carries its digest as an `ETag`;
  the host's existing resolver protects both routes. Personal values in exported examples and defaults are
  `null`, including fields nested in domain values.

- **The graph screen draws each domain's context map and system** above the per-process panels (engine
  EG2), a v2 process's full graph — steps, actors, read side, external systems — with the log in the second
  panel, and each unit of that process's contract below it (engine EG1).

- **The graph screen opens on a v2 process**, and shows its declared shape — stages, endings, promises — in the
  first panel, as for a v1 process, with its steps and the log in the second.

- **The screens read v2 contracts** (engine E7c). The contract status screen renders a v2 contract's report —
  its steps, with what waits under a heading of its own, its promises, its wiring version and its scenarios —
  in `EhOsContract.Report.Sentence`'s words, as it renders a v1 one; the drift line is the shared sentence too.
  The graph screen draws a v2 process as its steps, declared and with the log laid over it. The conformance
  API serves a v2 contract as `eh_os_contract.conformance.v2`; with more than one contract registered a request
  names one, as before.

### Changed

- **The Graph screen draws with `eh_os_contract_graph`, and no Mermaid is left** (plan E13, #217). Each picture of
  the screen — a domain's context map and system, a contract's declared shape, full graph, units and lifecycles —
  is the renderer's view of the engine's `graph.v1` document, with the log over the same pictures as before, read
  once connected. A click on a card or an arrow opens a panel at the right of the window that says what it is,
  from the document alone; a domain's actors are a table under its map, a row opening the actor's panel; a page
  with graphs takes the window's width. Contract status says what one run of a process is beside the count of
  runs ("Runs in this period: 3, one per visit_id."), from the process's `correlate`. The dashboard serves no
  `mermaid.min.js`, and every page works under `default-src 'self'` with no exception. **The dashboard depends on
  `eh_os_contract_graph`**, which a host fetching from git gets as it gets the engine; its script and stylesheet
  are bundled into the dashboard's `app.js` and `app.css`, so a host serves and registers nothing new, but the
  bundled script reads the markup the renderer's component renders: **update the two together**
  (`mix deps.update eh_os_contract_web eh_os_contract_graph`). `NOTICE` names the renderer's dagre and d3, which
  the bundle carries. Moves no verdict.

- **The graph page selects a contract, by its id, whether or not it has a process** (plan DD, P1b,
  eh-os-contract#186). A contract without a process could not be opened there. The selector lists each contract's
  id, with its process's label where it has one; the declared shape of a process shows only when there is one; the
  contract's graph, its units and its lifecycles show always. The LiveView event is `select_contract` with
  `"contract" => <id>`, where it was `select_process` with `"<module>:<process>"`.

- **Breaking:** **The APIs name a contract by its `id:`, and the conformance report is `conformance.v3`** (plan DD, P1a,
  eh-os-contract#183). `GET <mount>/conformance?contract=lending.circulation`, `<mount>/model/<id>`,
  `<mount>/openapi/<id>` and `<mount>/asyncapi/<id>` take the contract's id; a module's name is an unknown contract,
  and a parameter given as a list or a map is a bad request. The indexes list `"contract"` as the id and add
  `"module"`; the model index is `eh_os_contract.model-index.v2`. OpenAPI and AsyncAPI documents carry the id as
  `info.x-eh-os-contract-id`. The conformance screen heads each contract with its id and shows its steps apart from
  its processes. A host's callers pass ids; readers of the conformance JSON move to v3 (the engine's CHANGELOG has
  the shape).

- **The design system's tokens and fonts come from the `ehos_design` package** (`ehos_design-v0.1.0`,
  EHOS's design system) instead of a copy kept in `assets/css/vendor/empoweredhouse/`, which is gone. It is a
  `:dev` dependency of the asset build only; the built stylesheet and fonts are unchanged, byte for byte,
  and a host fetches nothing new.

- **The AsyncAPI endpoint now serves v2 contracts and their declared `publish` boundaries.** Its index lists
  only v2 contracts; each document exposes public messages as AsyncAPI `send` operations and does not leak
  internal domain events. A message component is keyed by the exact versioned publication name.

- **The dashboard looks like the EHOS console**: the EmpoweredHouse design system's tokens, Albert Sans and
  JetBrains Mono served beside the stylesheet, dark by default and light when the system prefers it. The
  host adds nothing — the fonts come through the `Plug.Static` line it already has. A breached verdict
  stays in the error colour; a met or in-progress one is no longer green or amber, because the design
  system has no colour for either and the sentence already says which. Diagrams follow the theme. The
  `--eh-os-contract-*` properties now point at the tokens; as before, no host stylesheet reaches the
  dashboard's pages to override them.

- `EhOsContract.Web.Live.Graph` reads contracts through `EhOsContract.Model`, so this package needs an engine
  that has it: the engine's own "Unreleased" or later. Inside this repository, and over git from it, both
  packages come from one commit. Nothing the dashboard shows changes.

### Removed

- **E11: the engine's first DSL is gone, and so is what the dashboard drew of it.** The `/graph` screen has no
  "every contract" panel, which drew the first DSL's handler graph, and every list — the contract status, the
  graphs, the API indexes — is of the engine's `Registry.contracts/0`, which from 0.3.0 of `eh_os_contract`
  is the only kind of contract there is.

### Fixed

- **Breaking:** **The dashboard and the API work mounted in a scope with a path of its own, or with an alias.** Mounted in
  `scope "/admin"`, `/admin/dashboard` redirected to `/dashboard/contract`, a 404, and the screens linked outside
  the prefix; in `scope "/admin", MyAppWeb`, every route named `MyAppWeb.EhOsContract.Web.…` and failed. The
  redirect, the links and the `base_path` the resolver is given now carry every scope's prefix, and no trailing
  slash. **What a resolver receives changes** for a host mounted under a prefix: `base_path` was `"/dashboard"`
  and is `"/admin/dashboard"`, and the API's `"/admin/api"`; a resolver matching the old value refuses until it is
  updated. Mounted in `scope "/"`, nothing changes. A router may now mount the dashboard more than once.

- **The graph screen works under a strict Content-Security-Policy** (plan EG3), `default-src 'self'` as EHOS
  serves it: the diagrams were black boxes there. The hook draws with `mermaid.render` and hands the SVG's
  stylesheet and `style` attributes to the CSSOM — a constructed stylesheet and `element.style` — which such a
  policy does not refuse. Mermaid still tries inline styles while it measures a diagram; the policy blocks
  them and the browser logs each (about 400 lines for the sandbox's three diagrams), without effect on what is
  drawn. The host needs no `style-src 'unsafe-inline'` any more.

## [0.1.1] - 2026-09-23

Tagged `v0.2.1` of the repository, alongside `eh_os_contract` 0.2.1.

### Changed

- The repository is `EmpoweredHouse/eh-os-contract`, renamed from `eh-os-prototype`.
  `source_url` follows, and so does the git address this package fetches the engine
  from outside its own repository — which under `v0.2.0` reached the engine only
  through GitHub's redirect from the old name.

## [0.1.0] - 2026-09-23

Everything to date, recorded after the fact, and the first tagged version:
`v0.2.0` of the repository, alongside `eh_os_contract` 0.2.0. Not on Hex, because
`eh_os_contract` is not either and a published package may depend only on published
ones; see `README.md` for the second reason. It installs from git.

### Added

- `eh_os_contract_api/2` also serves the generated AsyncAPI documents: an index at
  `/asyncapi` and one document per contract, each with its digest in the body and
  in the `ETag`. Authenticated like everything else — a document naming every event
  and label in the client's own words is a map of their business.
- `eh_os_contract_api/2`, a read-only JSON mount for the conformance report, sharing the
  dashboard's access decision through the same `EhOsContract.Web.Resolver`. It mounts in its
  own scope because a JSON route needs the opposite pipeline to a page: no session,
  no CSRF, and `accepts` saying json rather than html.
- `eh_os_contract_dashboard/2`, mountable in a host's own router, with three LiveView screens:
  contract conformance, accounts, and the process graph.
- `EhOsContract.Web.Resolver`, the seam by which a host decides who may see the dashboard,
  with a default reading `conn.assigns[:eh_os_contract_actor]`.
- `EhOsContract.Web.Plug.Authenticate`, optional, filling that assign from a bearer token or
  the session.
- A provisional local login, `EhOsContract.Web.LocalLogin`, for a host that has no identity
  provider wired up yet.

### Removed

- The provisional login (`EhOsContract.Web.LocalLogin`, the `/login` and
  `/logout` routes), the accounts screen (`EhOsContract.Web.Live.Accounts`), the optional
  `EhOsContract.Web.Plug.Authenticate` and the default resolver `EhOsContract.Web.Resolvers.Default`.
  All of them stood on `PNS.Auth`, which left the engine with them. `:resolver` is
  now required by both `eh_os_contract_dashboard/2` and `eh_os_contract_api/2`: the host decides who may
  see the dashboard, with no fallback that silently lets everyone in.

### Fixed

- Installing this package from git failed with "Dependencies have
  diverged", because it named the engine by `path: "../eh_os_contract"`, which a
  `sparse:` checkout does not contain. The path is used only when the engine sits
  beside this package; otherwise the engine comes from the same repository over
  git, in the shape a consumer declares it.

- Only the verdict carries the verdict's colour. The whole sentence used
  to, including the clause explaining that an external outage means "this is not a
  breach on the client's side" — printed in red, which says the opposite of what it
  means. `EhOsContract.Report.Sentence.verdict/1` and `qualifications/1` split the two.

- The contract screen was quietly answering six fewer questions than
  `mix eh_os_contract.report`. It carried its own copy of the report's sentences — a
  deliberate duplication, made when both copies said the same four things — and by
  the time anybody ran the two side by side it had no addressee, no measured
  `deadline`, nothing for a run suspended by an external outage, nothing for a run
  judged under a rule that had since changed, nothing about which met runs reached
  the fallback, and no sign of queued work at all. A run suspended by somebody
  else's outage read on screen exactly like an ordinary one. Every sentence now
  comes from `EhOsContract.Report.Sentence`; the screen decides what is a heading, a list or
  red, and decides nothing about what the answer says.

- `EhOsContract.Web.Plug.Authenticate` crashed on any request without a bearer
  header in a pipeline that had not fetched a session — that is, on exactly the
  unauthenticated request an API mount most needs to refuse cleanly.
