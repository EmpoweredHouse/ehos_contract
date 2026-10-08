# Changelog

The rule this package follows is the one written in `packages/eh_os_contract/CHANGELOG.md`:
a change that can move something the dashboard reports raises the minor version and
gets a line here.

The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

- **`<mount>/conformance?process=<id>` serves a process module's report** (plan DD, P2w, eh-os-contract#259, agreed
  with EHOS in EmpoweredHouse/eh-os#297). The report keeps the schema `eh_os_contract.conformance.v3` and has
  `"process"` where a contract's has `"contract"`. An unknown process is 400, and so is naming a contract and a
  process at once. A request with neither, or with `contract=`, answers as before.

- **The dashboard and the API work mounted in a scope with a path of its own, or with an alias.** Mounted in
  `scope "/admin"`, `/admin/dashboard` redirected to `/dashboard/contract`, a 404, and the screens linked outside
  the prefix; in `scope "/admin", MyAppWeb`, every route named `MyAppWeb.EhOsContract.Web.…` and failed. The
  redirect, the links and the `base_path` the resolver is given now carry every scope's prefix, and no trailing
  slash. **What a resolver receives changes** for a host mounted under a prefix: `base_path` was `"/dashboard"`
  and is `"/admin/dashboard"`, and the API's `"/admin/api"`; a resolver matching the old value refuses until it is
  updated. Mounted in `scope "/"`, nothing changes. A router may now mount the dashboard more than once.

- **The graph page selects a contract, by its id, whether or not it has a process** (plan DD, P1b,
  eh-os-contract#186). A contract without a process could not be opened there. The selector lists each contract's
  id, with its process's label where it has one; the declared shape of a process shows only when there is one; the
  contract's graph, its units and its lifecycles show always. The LiveView event is `select_contract` with
  `"contract" => <id>`, where it was `select_process` with `"<module>:<process>"`.

- **The APIs name a contract by its `id:`, and the conformance report is `conformance.v3`** (plan DD, P1a,
  eh-os-contract#183). `GET <mount>/conformance?contract=rehmed.settlement`, `<mount>/model/<id>`,
  `<mount>/openapi/<id>` and `<mount>/asyncapi/<id>` take the contract's id; a module's name is an unknown contract,
  and a parameter given as a list or a map is a bad request. The indexes list `"contract"` as the id and add
  `"module"`; the model index is `eh_os_contract.model-index.v2`. OpenAPI and AsyncAPI documents carry the id as
  `info.x-eh-os-contract-id`. The conformance screen heads each contract with its id and shows its steps apart from
  its processes. A host's callers pass ids; readers of the conformance JSON move to v3 (the engine's CHANGELOG has
  the shape).

- **The design system's tokens and fonts come from the `ehos_design` package** (`ehos_design-v0.1.0`,
  eh-os D-72) instead of a copy kept in `assets/css/vendor/empoweredhouse/`, which is gone. It is a
  `:dev` dependency of the asset build only; the built stylesheet and fonts are unchanged, byte for byte,
  and a host fetches nothing new.

- **E11: the engine's first DSL is gone, and so is what the dashboard drew of it.** The `/graph` screen has no
  "every contract" panel, which drew the first DSL's handler graph, and every list — the contract status, the
  graphs, the API indexes — is of the engine's `Registry.contracts/0`, which from 0.3.0 of `eh_os_contract`
  is the only kind of contract there is.

- **The API mount serves OpenAPI 3.1.2 documents** at `/openapi` and `/openapi/:contract`, with one
  command-and-query document per v2 contract and its digest as the `ETag`. The host's existing resolver
  protects both routes. Repeated query keys are the documented list encoding; structured parameters use
  deep-object keys, and erased personal fields in rows are nullable.

- **The AsyncAPI endpoint now serves v2 contracts and their declared `publish` boundaries.** Its index lists
  only v2 contracts; each document exposes public messages as AsyncAPI `send` operations and does not leak
  internal domain events. A message component is keyed by the exact versioned publication name.

- **The API mount serves v2 model documents** at `/model` and `/model/:contract`. Each document is
  `eh_os_contract.model.v1`, includes the derived capability surface, and carries its digest as an `ETag`;
  the host's existing resolver protects both routes. Personal values in exported examples and defaults are
  `null`, including fields nested in domain values.

- **The graph screen works under a strict Content-Security-Policy** (plan EG3), `default-src 'self'` as EHOS
  serves it: the diagrams were black boxes there. The hook draws with `mermaid.render` and hands the SVG's
  stylesheet and `style` attributes to the CSSOM — a constructed stylesheet and `element.style` — which such a
  policy does not refuse. Mermaid still tries inline styles while it measures a diagram; the policy blocks
  them and the browser logs each (about 400 lines for the sandbox's three diagrams), without effect on what is
  drawn. The host needs no `style-src 'unsafe-inline'` any more.
- **The graph screen draws each domain's context map and system** above the per-process panels (engine
  EG2), a v2 process's full graph — steps, actors, read side, external systems — with the log in the second
  panel, and each unit of that process's contract below it (engine EG1).

- **The dashboard looks like the EHOS console**: the EmpoweredHouse design system's tokens, Albert Sans and
  JetBrains Mono served beside the stylesheet, dark by default and light when the system prefers it. The
  host adds nothing — the fonts come through the `Plug.Static` line it already has. A breached verdict
  stays in the error colour; a met or in-progress one is no longer green or amber, because the design
  system has no colour for either and the sentence already says which. Diagrams follow the theme. The
  `--eh-os-contract-*` properties now point at the tokens; as before, no host stylesheet reaches the
  dashboard's pages to override them.

- **The graph screen opens on a v2 process**, and shows its declared shape — stages, endings, promises — in the
  first panel, as for a v1 process, with its steps and the log in the second.
- **The screens read v2 contracts** (engine E7c). The contract status screen renders a v2 contract's report —
  its steps, with what waits under a heading of its own, its promises, its wiring version and its scenarios —
  in `EhOsContract.Report.Sentence`'s words, as it renders a v1 one; the drift line is the shared sentence too.
  The graph screen draws a v2 process as its steps, declared and with the log laid over it. The conformance
  API serves a v2 contract as `eh_os_contract.conformance.v2`; with more than one contract registered a request
  names one, as before.
- `EhOsContract.Web.Live.Graph` reads contracts through `EhOsContract.Model`, so this package needs an engine
  that has it: the engine's own "Unreleased" or later. Inside this repository, and over git from it, both
  packages come from one commit. Nothing the dashboard shows changes.

## 0.1.1 — 2026-09-23

Tagged `v0.2.1` of the repository, alongside `eh_os_contract` 0.2.1.

- The repository is `EmpoweredHouse/eh-os-contract`, renamed from `eh-os-prototype`.
  `source_url` follows, and so does the git address this package fetches the engine
  from outside its own repository — which under `v0.2.0` reached the engine only
  through GitHub's redirect from the old name.

## 0.1.0 — 2026-09-23

Everything to date, recorded after the fact, and the first tagged version:
`v0.2.0` of the repository, alongside `eh_os_contract` 0.2.0. Not on Hex, because
`eh_os_contract` is not either and a published package may depend only on published
ones; see `README.md` for the second reason. It installs from git.

- **Fixed:** installing this package from git failed with "Dependencies have
  diverged", because it named the engine by `path: "../eh_os_contract"`, which a
  `sparse:` checkout does not contain. The path is used only when the engine sits
  beside this package; otherwise the engine comes from the same repository over
  git, in the shape a consumer declares it.
- **Removed:** the provisional login (`EhOsContract.Web.LocalLogin`, the `/login` and
  `/logout` routes), the accounts screen (`EhOsContract.Web.Live.Accounts`), the optional
  `EhOsContract.Web.Plug.Authenticate` and the default resolver `EhOsContract.Web.Resolvers.Default`.
  All of them stood on `PNS.Auth`, which left the engine with them. `:resolver` is
  now required by both `eh_os_contract_dashboard/2` and `eh_os_contract_api/2`: the host decides who may
  see the dashboard, with no fallback that silently lets everyone in.

- **Fixed:** only the verdict carries the verdict's colour. The whole sentence used
  to, including the clause explaining that an external outage means "this is not a
  breach on the client's side" — printed in red, which says the opposite of what it
  means. `EhOsContract.Report.Sentence.verdict/1` and `qualifications/1` split the two.
- **Fixed:** the contract screen was quietly answering six fewer questions than
  `mix eh_os_contract.report`. It carried its own copy of the report's sentences — a
  deliberate duplication, made when both copies said the same four things — and by
  the time anybody ran the two side by side it had no addressee, no measured
  `deadline`, nothing for a run suspended by an external outage, nothing for a run
  judged under a rule that had since changed, nothing about which met runs reached
  the fallback, and no sign of queued work at all. A run suspended by somebody
  else's outage read on screen exactly like an ordinary one. Every sentence now
  comes from `EhOsContract.Report.Sentence`; the screen decides what is a heading, a list or
  red, and decides nothing about what the answer says.
- `eh_os_contract_api/2` also serves the generated AsyncAPI documents: an index at
  `/asyncapi` and one document per contract, each with its digest in the body and
  in the `ETag`. Authenticated like everything else — a document naming every event
  and label in the client's own words is a map of their business.
- `eh_os_contract_api/2`, a read-only JSON mount for the conformance report, sharing the
  dashboard's access decision through the same `EhOsContract.Web.Resolver`. It mounts in its
  own scope because a JSON route needs the opposite pipeline to a page: no session,
  no CSRF, and `accepts` saying json rather than html.
- **Fixed:** `EhOsContract.Web.Plug.Authenticate` crashed on any request without a bearer
  header in a pipeline that had not fetched a session — that is, on exactly the
  unauthenticated request an API mount most needs to refuse cleanly.
- `eh_os_contract_dashboard/2`, mountable in a host's own router, with three LiveView screens:
  contract conformance, accounts, and the process graph.
- `EhOsContract.Web.Resolver`, the seam by which a host decides who may see the dashboard,
  with a default reading `conn.assigns[:eh_os_contract_actor]`.
- `EhOsContract.Web.Plug.Authenticate`, optional, filling that assign from a bearer token or
  the session.
- A provisional local login, `EhOsContract.Web.LocalLogin`, for a host that has no identity
  provider wired up yet.
