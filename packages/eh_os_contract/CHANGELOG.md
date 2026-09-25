# Changelog

## The rule this file exists for

**A change that can move a verdict raises the MINOR version and gets a line here.**

A verdict is anything the conformance report prints as a number or a state: an
overlay edge's state, a `trace` verdict, a path counted as untraversed, a run
counted as exceeding a deadline, a declaration counted as changed. Wording,
docstrings, tests and fixtures do not.

The rule exists because a report is arithmetic, and two clients running two engine
versions get two answers to the same question. `EhOsContract.version/0` puts the version in
the report; this file says what each one changed. A version in a report that
nothing explains is decoration.

Nothing mechanical enforces this — no test can. The `review-pr` skill carries it,
and the list of files that trigger the question lives there and only there: two
copies of it had already disagreed by the time this paragraph was rewritten, which
is the drift this package exists to detect, in the file describing the rule
against it.

The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this
package follows [semantic versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

Stages E1–E4 of the move to a v2 contract DSL (`PLAN.md`, `docs/adr/contract-v2.md`). **No verdict moves.**
`mix eh_os_contract.report` and `mix eh_os_contract.graph --overlay --mermaid` gave byte-identical output on
the development database before and after each stage, so the version stays 0.2.1 until a change does move
one. What changes is what a host has to do.

### Changed — a host has to act

- **A new migration is required.** Add one calling `EhOsContract.Migrations.up(version: 3)` and
  `down(version: 3)`, like the upgrade to version 2. V03 alters `eh_os_contract_events` in place:
  - a `position` column becomes its primary key, and existing rows are numbered in `occurred_at` order;
  - streams, tags, `schema_version`, `command_id`, `metadata` and `recorded_at` are added;
  - `actor` becomes NOT NULL, and rows without one get the system actor;
  - the `eh_os_contract_commands` table is created.
- **The log is append-only.** Triggers refuse UPDATE, DELETE and TRUNCATE on `eh_os_contract_events`. A test
  that moved `occurred_at` afterwards has to emit in the past instead, with `EhOsContract.Clock.at/2`. A test
  database that leaked rows is recovered with `ecto.drop`.
- **Emissions run under READ COMMITTED.** `EhOsContract.Store.Postgres` refuses to append at a stricter
  isolation level. Every append takes one transaction-scoped advisory lock, so a transaction that locks a row
  and then emits can deadlock with an emission whose handler locks the same row. Take
  `EhOsContract.Store.Postgres.lock/1` first (`EhOsContract.Store`'s moduledoc).
- **A new dependency: `spark ~> 2.7.3`.**

### Added

- `EhOsContract.Model`: a contract as plain data, and the accessors every reader now uses. A module that is
  not a contract is refused by name.
- `EhOsContract.Store`, with `Store.Postgres` and `Store.Suite`, a set of tests any implementation can run.
  The v1 emitter appends through it.
- `EhOsContract.Clock`: the time events are stamped with, which a test can set for the calling process.
- `EhOsContract.Domain`: the v2 domain DSL, on Spark. It covers contexts with a glossary, actors, subjects,
  values, externals and relations, with rules D1–D5 and F3/F5 as compile errors. Its model is
  `__eh_os_contract_model__/0`, and it generates a `Values` module of types. Nothing in v1 reads it yet.
- `EhOsContract.Next.Contract`: the v2 contract DSL, on Spark, beside v1's `EhOsContract.Contract` until the
  cut. It declares aggregates and dynamic consistency boundaries with their identity, state, invariants,
  commands, events and stage groups; policies, effects, process managers, read models and queries; `consumes`
  and `publish`; one `process` with stages, includes, cadence, deadline and promises; and scenarios. Its model
  is `__eh_os_contract_model__/0`, with a version that ignores declaration order. Nothing runs it yet, and the
  v1 accessors of `EhOsContract.Model` refuse it by name. It refuses to compile what v2 §6's layer L2 refuses:
  names (N1–N2), fields (F1–F6), units and their commands (A1–A5, C1), what reacts and what is read
  (P1–P5), the process (R1–R6), what it consumes from a sibling contract (K1), and the query scope and
  publications of D10–D11.
- `actor` in the domain DSL takes `scope:`, the fields a grant narrows query answers by (D10).
- Options beside a `do` block in the domain DSL: `context`, `term` and `value` accept
  `context :settlement, "Rozliczenia", subdomain: :supporting do … end` as well as the options written inside
  the block. An error still points at the declaration's file and line, and `mix format` keeps the form as
  written.

### Changed

- `mix eh_os_contract.check` prints its findings in a fixed order: errors, warnings, notices, each by text.
  The lines are the same.

## 0.2.1 — 2026-09-23

### Changed

- The repository is `EmpoweredHouse/eh-os-contract`, renamed from `eh-os-prototype`.
  `source_url` and the package links point there. No code changed; no verdict moves.

## 0.2.0 — 2026-09-23

The first tagged version: `v0.2.0`. Not on Hex yet, so it installs from git — see
`README.md`. Everything below that `0.1.0` did not have, including what changed on
23 September before the tag.

### Added

- `EhOsContract` as a supervision-tree child. It runs `EhOsContract.Registry.load!/1`
  and `EhOsContract.Deployment.record!/1` in that order and returns `:ignore`, so a
  host no longer has to remember to call both by hand after starting its repo.

- `EhOsContract.Run`: how long a run took, against the `deadline` its process declared.
  The declaration has existed since the first commit and nothing read it — the
  only mentions were a filter that dropped it when unconfirmed and a renderer that
  printed it back. A run starts at its earliest event and ends at the earliest
  event declared `terminal: true`; four outcomes, not two, because a run still open
  past its duration has a known lower bound and no known duration, and folding it
  in with runs that finished late would report a bound as a measurement.
- `command`, a seventh declaration: a way into a process from outside, and which
  kinds of principal may take it. `EhOsContract.Command.permits?/3` derives the capability,
  which answers level 2 only — whether *this* caller may act for *this* subject
  stays a `rule` with a decision function. There is no `emits:` key, deliberately
  and against `D-15` as written: both readings of "what this command emits" are
  already held elsewhere and neither can be checked for completeness by a gate.
  `principals:` is a closed set and, unlike the payload types, a proposal rather
  than something read out of any corpus.
- `accountable:` on `process`: the role a finding is addressed to. Distinct from
  `owner:` on an event, which holds a module and answers a different question.
  `mix eh_os_contract.check` warns when a process names none.
- `EhOsContract.Report.Sentence`: the sentences a conformance report is made of, without its
  layout. `EhOsContract.Report` composes them with indentation; anything else rendering the
  same report composes them some other way. Neither owns the words.
- `EhOsContract.AsyncAPI`: an AsyncAPI 3.0 document generated from a contract, carrying a
  digest computed over the document itself. `channels` and `components.messages`
  only — no `operations`, because handler edges would make the digest move when
  somebody renamed a handler, and the digest is the point. What the standard cannot
  express travels as `x-eh-os-contract-*`: the `trace`, the retention policy, the stages, the
  commands. `external` is deliberately absent rather than mapped to `servers`.
- `EhOsContract.Conformance.as_data/2` and `EhOsContract.Conformance.Wire`: the report projected onto
  values that survive JSON. It lives in the engine rather than in a transport
  because the shape a consumer compares, version to version, is part of what this
  package promises. An undecided tuple or struct raises rather than being guessed
  at — a wire format acquires unreadable fields one guess at a time.
- The package can be published: `package/0`, a description, a licence file of its
  own, a README and generated docs. Stage 3 called this "the package as a package"
  and closed in August; `mix hex.build` refused the project outright until now.
- `.formatter.exs` with an exported `locals_without_parens`, so a consuming
  project's `mix format` leaves contracts looking like contracts instead of
  rewriting every declaration as a function call.
- `mix eh_os_contract.check` reports, as a notice, a process that declares a `deadline` and no
  `terminal: true` event — a promise about duration that nothing can observe being
  kept or broken.
- Every declaration now carries its own digest, recorded per deployment
  (each contract gains a generated `declaration_digests/0`, stored by `EhOsContract.Migrations` v02).
  `EhOsContract.Deployment.diff/2`
  reports which declaration moved, where before it could only compare event names
  and handler edges — so a changed `within`, `retain`, `identity`, `instance` or
  payload type registered as four empty lists.
- `EhOsContract.Deployment.declaration_boundaries/1`: when each declaration last changed.
- `EhOsContract.version/0`, and the report says which engine computed it.

### Fixed

- The conformance report no longer says "BREACHED in 1 of 5 runs. (including 1 via
  the fallback ending, which conforms to the rule)". The clause qualified the runs
  that were *met* while reading as though it qualified the breaches, which is the
  worst kind of ambiguity to have in an artifact meant to be evidence. It is now
  attached to the count it describes, and omitted entirely when nothing was met.
  Not a verdict change — the numbers were always right — but the sentence was not.

### Changed

- **Renamed from `pns` to `eh_os_contract`**, with the namespace (`PNS` →
  `EhOsContract`), the mix tasks (`mix pns.*` → `mix eh_os_contract.*`), the
  telemetry prefix, the engine's tables (`pns_*` → `eh_os_contract_*`, created that
  way by `V01`/`V02` with no upgrade path), the AsyncAPI extensions
  (`x-eh-os-contract-*`) and the report schema (`eh_os_contract.conformance.v1`).
- `docs/contract.md`, the DSL reference, ships inside the package;
  `mix eh_os_contract.docs` is tooling for developing the package and is no longer
  compiled into consumers.

- **Every contract's `version/0` moved once, deliberately.** A seventh declaration
  group changes the hash even for a contract that declares no commands, so the log
  reclassifies once rather than twice; `accountable:` landed in the same commit for
  that reason. The same one-off price was paid on 6 August when the hash became
  canonical.
- **Verdict-moving.** A `trace` assertion's counts now cover only runs that began
  after that assertion last changed. Runs from before it are counted separately
  and named in the report with the date of the change. Previously an edit to
  `within` retroactively rejudged the whole log at the moment of deployment, with
  nothing in the report to say the rule had moved.
- **Verdict-moving.** An assertion whose every run predates its last change now
  reads as "no run was judged under the rule as it now stands" rather than as
  "there was no run on which this could be judged". The second is an absence; the
  first is not.
- `EhOsContract.Deployment.record!/1` replaces `declaration_digests` on conflict instead of
  leaving the row alone, so a deployment recorded before v02 is backfilled rather
  than staying blind for the version actually running.

### Removed

- `PNS.Auth` in full — the token verifiers (`LocalToken`, `OidcVerifier`), the
  user-management seam (`IdentityAdmin`, `LocalIdentityAdmin`) and `entitled?/2` —
  along with the `:auth_verifier` and `:identity_admin` configuration keys every
  consumer had to set, and the `oidcc` dependency. They belonged to an earlier
  scope in which this engine would also own the dashboard's login and accounts.
  The engine now takes an actor as an opaque subject in `ctx.actor` and knows
  nothing else about identity. `system_actor/0` moved to `EhOsContract.Event.system_actor/0`.
- `PNS.Command.permits?/3` and `principal_type/1`. The `command` declaration and
  its `principals:` key stay, as a description; the engine no longer derives an
  access decision from them. No verdict moves: nothing in the report read either.

## 0.1.0 — never published

Everything up to 2026-09-22, recorded here after the fact because the rule above
did not exist while it was happening. **These entries are retroactive and carry no
version of their own** — inventing numbers for releases nobody published would be
a second source of truth about a sequence that never happened.

At least five changes at this version moved a verdict:

- A process with no runs reports `basis: :no_runs` rather than reporting every
  declared path as untraversed. Zero runs is not evidence that a path is dead.
- Work sitting in the queue counts as in flight, not as a path nobody took.
- A step that is attempted and fails was split out of "never attempted". Both were
  previously one line, and they go to different people.
- `:suspended` became a fourth `trace` verdict: a run whose window contained an
  external dependency's outage is not a breach on the client's side.
- `unverified` reaches a `trace` by name, so the sharpest assertion the engine can
  make — the one most likely to be a guess — can be declared without being counted
  as measured.
