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

Stages E1–E6 of the move to a v2 contract DSL (`PLAN.md`, `docs/adr/contract-v2.md`). **No verdict of a v1
contract moves.** `mix eh_os_contract.report` and `mix eh_os_contract.graph --overlay --mermaid` gave
byte-identical output on the development database before and after each of E1–E5.

**The version is 0.3.0-dev from E6**, where v2 contracts start to run. A host that ports a contract to v2 sees
it leave what the v1 readers — the report, the graph, `check` — cover, until E7 reads the new log; the
sandbox's `Rehmed.Contracts.VisitSettlement` is the first, and its five lines left `check`'s output with it.
What changes otherwise is what a host has to do.

### Changed — a host has to act

- **A new migration is required.** Add one calling `EhOsContract.Migrations.up(version: 3)` and
  `down(version: 3)`, like the upgrade to version 2. V03 alters `eh_os_contract_events` in place:
  - a `position` column becomes its primary key, and existing rows are numbered in `occurred_at` order;
  - streams, tags, `schema_version`, `command_id`, `metadata` and `recorded_at` are added;
  - `actor` becomes NOT NULL, and rows without one get the system actor;
  - the `eh_os_contract_commands` table is created.
- **And a second one, from E7**: `EhOsContract.Migrations.up(version: 4)` and `down(version: 4)`. V04 creates
  the tables of the consumers that run outside the dispatch transaction — `eh_os_contract_subscriptions`,
  `eh_os_contract_process_managers` and `eh_os_contract_event_runs` — and changes no existing table.
- **The log is append-only.** Triggers refuse UPDATE, DELETE and TRUNCATE on `eh_os_contract_events`. A test
  that moved `occurred_at` afterwards has to emit in the past instead, with `EhOsContract.Clock.at/2`. A test
  database that leaked rows is recovered with `ecto.drop`.
- **Emissions run under READ COMMITTED.** `EhOsContract.Store.Postgres` refuses to append at a stricter
  isolation level. Every append takes one transaction-scoped advisory lock, so a transaction that locks a row
  and then emits can deadlock with an emission whose handler locks the same row. Take
  `EhOsContract.Store.Postgres.lock/1` first (`EhOsContract.Store`'s moduledoc).
- **A new dependency: `spark ~> 2.7.3`.**
- **E7a: the `EhOsContract` child is a supervisor.** Besides scanning the registry and recording the
  deployment, it registers every subscription, rebuilds the stale read models that define `reset/0`, and
  starts one runner per subscription; dispatch wakes them through Oban's notifier after each commit it owns.
  **A host's tests set `config :eh_os_contract, subscriptions: :manual`**, which skips registration and
  runners, and drain with `EhOsContract.Testing.drain/1`. `EhOsContract.boot/0` is gone.

### Added

- **E7a: effects run.** An effect delivered `:at_least_once` is an `EhOsContract.EffectJob` in Oban's
  `:events` queue, inserted in the dispatch transaction and holding only the effect's key and the event's id;
  the job reads the event from the log. An effect delivered `:in_transaction` acts before the dispatch commits,
  and its `{:error, reason}` rolls the append back. Until E6 both were skipped without a word. Oban has to run
  on the repo dispatch appends through, and dispatch refuses to insert a job otherwise.
- **E7a: ordered subscriptions.** A read model or a policy delivered `:at_least_once` is fed from the log after
  the transaction, in order, by `EhOsContract.Subscription`, one row each in `eh_os_contract_subscriptions`. An
  event it cannot apply is retried three times and then stops it at that position, `failing`, until a person
  skips it; a read model whose declaration changed is `stale` until it is rebuilt. A read model's
  implementation may define `reset/0` to empty its rows, and only then can it be rebuilt; an inline one is left
  to the runner while it is. `EhOsContract.Testing.drain/1` runs all of it inside a test's transaction.
- **E7b: process managers run.** A process manager is fed from the log in order, like an ordered policy: a
  run starts on its `starts_on` event, reacts, sets and cancels timers, and ends on `ends_on`; its runs are rows
  of `eh_os_contract_process_managers`. A timer is an `EhOsContract.TimerJob` that appends
  `eh_os_contract.timer_elapsed` to the run's stream when it is due, and the process manager reacts to that
  event in order, so a timer fired twice dispatches once. Its commands are issued as `pm:<name>`. A process
  manager whose declaration changed is replayed at boot with its reactions suppressed, and so is **a new one
  deployed onto a log with history**: it learns the runs already there and steers none of them, and their
  timers that came due before the deploy are dropped. **A process manager
  delivered `:in_transaction` no longer compiles** (P4). `EhOsContract.Testing.drain/1` fires the timers due by
  `EhOsContract.Clock.now/0`.
- **E7c: every run an event belongs to is a row of `eh_os_contract_event_runs`** (D7), written in the same
  append as the event: its home run, and the run of each v2 contract whose process `include`s it, correlated
  by that process's fields. An `EhOsContract.Store` entry may carry `runs:` for the included ones. A v1 event
  gets its home run too; the v1 readers do not read the table.
- **E7c: `EhOsContract.Trace` and `EhOsContract.Run` read v2 contracts.** `Trace.evaluate/3` takes the name of
  a v2 `promise`, and `Run.evaluate/3` measures a v2 process's `deadline`, both over the runs in
  `eh_os_contract_event_runs`, so an event another contract decided counts in the run that includes it. The
  arithmetic is v1's, and the same scenarios give the same verdicts on a v1 shape and on its v2 port.
- **E7c: `EhOsContract.Paths`**, the steps a v2 contract declares — a command's emits, a policy's or process
  manager's issues, a timer's, an effect — and, for each, the runs that took it, what waits (subscription lag,
  scheduled timers, effect jobs) and what fails (commands through `failed_in`, a subscription stopped at an
  event, discarded effect jobs).
- **E7a: `mix eh_os_contract.subscriptions`** lists where each subscription stands; `--skip KEY` moves a
  failing one past the event it fails on, `--reset KEY` empties a read model and replays the log into it.
- **E7c: a new policy leaves history alone, as a new process manager does.** A policy delivered
  `:at_least_once` starts at the head of the log when it is first registered, instead of at position 0: a
  deploy onto a year of history issues nothing for that year. `--reset KEY` of a policy moves it back to the
  beginning, and it reacts to the whole log, with the keys derived from each event, so what it issued before
  is not issued twice; until E7c it was refused. **In a host's tests the first `EhOsContract.Testing.drain/1`
  is the deploy**, so a test of a policy's reaction drains once before it dispatches what the policy reacts to.

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
  names (N1–N2, which also keeps `state` and `row` for the aliases an implementation gets), fields (F1–F6), units and their commands (A1–A5, C1), what reacts and what is read
  (P1–P5), the process (R1–R6), what it consumes from a sibling contract (K1), the query scope and
  publications of D10–D11, and scenarios (S1–S8): one trigger each, data that fits the declared fields, and
  **every invariant named by a scenario in which a command is rejected on it**. A scenario writes a
  timestamp as an ISO 8601 string, `"2026-09-01T09:00:00Z"`, and a date as `"2026-09-01"`, so the model
  stays plain data; the unit's identity is the scenario's own and need not be given.
- A v2 contract generates a struct for each command (`C.Commands.RecordPayment`), event (`C.Events.*`), event
  received from another application (`C.Received.*`), state (`C.Aggregates.*.State`, `C.Dcbs.*.State`,
  `C.ProcessManagers.*.State`), read model row (`C.ReadModels.*.Row`) and query's parameters (`C.Queries.*`),
  each with `@type t` and defined at the line of its declaration. Commands and events enforce their required
  fields and carry `__meta__`, an `EhOsContract.Meta`. `EhOsContract.Model.module_for/3` names them; an event
  consumed from a sibling contract is the sibling's own struct.
- A v2 contract generates a behaviour for each unit, policy, effect, process manager and read model, and a
  query's callback beside its parameters: one callback per command, `(command, state)`, and `evolve/2` for a
  declared state; one per handled or projected event; one per process manager reaction or timer that issues.
  A decision returns `{:ok, events}` or `{:error, %EhOsContract.Rejection{}}`, which names the invariant only.
- `use C, aggregate: :name` (or `dcb:`, `policy:`, `effect:`, `process_manager:`, `read_model:`, `query:`) binds
  a module to one declaration of the v2 contract `C` (`EhOsContract.Implementation`): its behaviour, aliases for
  the structs it touches, and `emit/1`, `reject/1` and `issue/1`. It refuses to compile what v2 §6's layer L4
  refuses, at the implementation's own file and line: a declaration that does not exist, with a did-you-mean
  (I1); a missing callback, with the clause to add (I2); `evolve/2` missing an event (I3); `emit/1` of an event
  the command does not emit, or of anything but struct literals (I4); `reject/1` of an invariant the command
  does not reject on (I5); `issue/1` of a command the reaction does not issue (I6); a macro in a kind that has
  no use for it (I7). `__eh_os_implementation__/0` says what each callback emits.
- `use EhOsContract.ScenarioCase, contract: C` generates one test per scenario of `C` and runs it against the
  implementation of its target, found in `C`'s application (or named with `implementations:`). What is
  expected, or issued, has to appear among what the code produced, in order and with the fields named — the
  subsequence `EhOsContract.ContractExample` asserts; a rejection has to be on the named invariant; and whatever
  a decision returns has to be within its declaration. Scenario data is cast to the fields' types.
- A process manager's state starts with its `correlate` fields, as a unit's with its identity, and a scenario may
  fire one of its timers with `on :timer`. Two scenarios may not share a description.
- `EhOsContract.Model.capabilities/1`: a v2 contract's capabilities under the names EHOS grants (D14),
  `<domain>.<command>` and `<domain>.<query>`, each with its roles `<domain>.<actor>` and a query's scope. The
  model's `grants` says the same per actor, with the events each records.
- `compile.eh_os_contract`, a Mix compiler for v2 §6's layer L3: add it after Elixir's,
  `compilers: Mix.compilers() ++ [:eh_os_contract]`. On every compile it checks the project's v2 contracts
  against what they name without a compile dependency, and fails the compile with an error at the declaration:
  `domain:` and `context:` (X1); every actor in `by:`, `recorded_by:`, `accountable` and a scenario, of the
  contract's context (X2); field types and subjects (X3); externals (X4); that every actor asking a scoped query
  carries the scope (D10); that a `publish` is named under the domain's `name:` (D11); that a sibling contract
  consumed is a v2 contract of the same domain declaring the events named (X5); and that the fields a
  subscriber correlates or matches on are in the sibling's event as it is compiled now, with the same type,
  neither optional nor personal (X6) — so removing or retyping such a field fails the compile of every
  subscriber that uses it, with an error at the subscriber naming the publisher's event and its line. Across the
  application: a process name is declared once (X7), a command's or query's capability `<domain>.<name>` too
  (D14), and a declaration has at most one implementation (X8). Scenario data that L2 leaves alone has to fit
  (X9): values of domain types — an enum's member, a value's type, a value's fields — and the data of an event
  consumed from a sibling, against the sibling's fields.
- `__eh_os_implementation__/0` also says where the implementation's `use` is, `file:` and `line:`.
- `EhOsContract.Next.Contract.vocabulary/0`: every entity of the contract DSL, by path, with the keys it
  takes, derived from the extension.
- `actor` in the domain DSL takes `scope:`, the fields a grant narrows query answers by (D10).
- Options beside a `do` block in the domain DSL: `context`, `term` and `value` accept
  `context :settlement, "Rozliczenia", subdomain: :supporting do … end` as well as the options written inside
  the block. An error still points at the declaration's file and line, and `mix format` keeps the form as
  written.
- `EhOsContract.Actor` and `EhOsContract.Authorizer` (D14): who acts, and the question v2 dispatch will ask
  about a credential's actor. `Actor.credential/3` carries a credential's `sub`, `cap` and `scp` as issued;
  `Actor.system/1` is a `:system` actor of the domain. `Authorizer.check/2` is the decision —
  `:missing_capability`, `:unscoped_grant`, `:outside_scope` — and `config :eh_os_contract, authorizer: M`
  replaces the default, which is `check/2` alone. An implementation may narrow a grant, never widen it: the
  engine repeats `check/2` after an `:ok` and raises `Authorizer.WidenedError` when it refuses.
- `EhOsContract.Codec`: v2 field values against their declared types, and their form in the log — JSON's,
  with a decimal as a string of digits and dates and timestamps in ISO 8601. Decoding never creates an atom, and
  a problem names the field, never its value. `EhOsContract.Key`: the one escaping for stream ids, tags and
  joined keys.
- `decimal` is a declared dependency; it came through Ecto before.
- `EhOsContract.dispatch/3`: a command to a v2 contract (`EhOsContract.Dispatcher`). It authorizes the actor —
  a credential's through the `Authorizer`, a `:system` actor against `by:` — then checks the fields, reads the
  unit's stream through `evolve/2`, lets the implementation decide, holds the decision to the declaration
  (an undeclared event or invariant raises and appends nothing), and appends under the stream's version,
  retrying a conflict up to three times when it owns the transaction and returning `{:error, :conflict}`
  inside the caller's. It returns an `EhOsContract.Receipt`. Each outcome is a row of
  `eh_os_contract_commands` (`EhOsContract.CommandRecord`): accepted, rejected with its invariant, or failed
  with where and the exception's module; a refusal writes nothing. An accepted idempotency key returns the
  first receipt, `duplicate: true`.
- Read models and policies delivered `:in_transaction` run inside the dispatch transaction: read models project
  the appended events, then policies react, and what a policy issues is dispatched in the same transaction as
  the policy's own actor, with the event as its cause and a key derived from it. An exception in any of them
  rolls the whole dispatch back; a policy caught in a cycle raises. A declaration delivered in the transaction
  with no implementation stops dispatch rather than being skipped.
- `EhOsContract.record/3` (D6): an event declaring `recorded_by:` enters without a decision, recorded by a
  `:system` actor it names, under the unit's stream version, with the consumers in the transaction and an
  `accepted` row of type `"record:<event>"`. A credential is refused with `:not_grantable` until a capability
  to record exists.
- `EhOsContract.query/3` (D10): a query is authorized like a command, and a scoped query with the value of its
  scope parameter, so a value outside the credential's grant, or a scoped capability granted with no values, is
  refused before the implementation runs. Every row answered is checked against the grant again, and one outside
  it raises `EhOsContract.Authorizer.OutsideScopeError`. A `:system` actor the query names is not narrowed.
  Nothing is written.
- `EhOsContract.Plug` serves the commands and queries of the contracts it is given over HTTP, under their
  capabilities: `POST …/commands/<capability>` and `GET …/queries/<capability>`. It authenticates nobody: the
  actor is `conn.assigns.eh_os_contract_actor`, a credential's, built by the plug in front of it, and without
  one the answer is 401. Outcomes map to statuses — 200, 422 for a rejection or unfitting fields, 403 for a
  refusal, 409 for a conflict or a reused key, 404 — and no body carries a value the caller did not send.
  `plug` is an optional dependency, and the module compiles only when it is there.
- A scenario may ask a query and state its answer, after ESDM's read model scenario: `query :q, %{…}` and
  `answers [%{…}]` (`answers %{…}` or `answers nil` for a query returning one). Givens are events the read model
  projects, and each row names its fields (S2, S3, S6; X9 for values of domain types). `ScenarioCase` projects
  the givens through the read model's implementation and asks the query in a transaction it rolls back, and
  requires exactly as many rows as named, each matching a different answered row on the fields it names, in any
  order. A test module with such a scenario checks out an Ecto sandbox connection of the configured repo.
- `docs/authorization.md`: how authorization works — the names the contract derives, the flow from EHOS's
  credential to a check in dispatch, which calls are asked of the `Authorizer` and which are held to the
  contract, scope, what is written for each outcome, the HTTP surface, and how strong it is.
- `EhOsContract.Codec.decode/4` takes `strings: true`, to read an integer or a boolean written as text.
- `EhOsContract.Meta` carries an event's `id` and `position` when it is read back from the log.
- `EhOsContract.Store.lock/1` on the configured implementation.

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
