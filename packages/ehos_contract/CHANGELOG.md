# Changelog

The rule this file exists for:

**A change that can move a verdict raises the MINOR version and gets a line here.**

A verdict is anything the conformance report prints as a number or a state: an
overlay edge's state, a promise's verdict, a path counted as untraversed, a run
counted as exceeding a deadline, a declaration counted as changed. Wording,
docstrings, tests and fixtures do not.

The rule exists because a report is arithmetic, and two clients running two engine
versions get two answers to the same question. `EhosContract.version/0` puts the version in
the report; this file says what each one changed. A version in a report that
nothing explains is decoration.

Nothing mechanical enforces this — no test can. The `review-pr` skill carries it,
and the list of files that trigger the question lives there and only there: two
copies of it had already disagreed by the time this paragraph was rewritten, which
is the drift this package exists to detect, in the file describing the rule
against it.

The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this
package follows [semantic versioning](https://semver.org/spec/v2.0.0.html).

A line for a change that can move a verdict starts with `**Moves a verdict:**`, under the
subsection it belongs to. CI's Changelog check holds that a pull request changing the package's
code has a line or says why not; whether the change can move a verdict, it cannot tell.

The rule beside it holds for every package of this repository:

**Every change a user of this package can see gets a line under `## [Unreleased]`, in its own pull
request.** A user is a host application's developer: what they see is the package's public API, its
Mix tasks, what it writes, what it verifies, what the dashboard reports and its `docs/`, the DSL
reference; its tests, README and CI are not. A pull request with no such line says why on a line of
its description, `No changelog: <why>`, and CI's Changelog check (`.github/workflows/changelog.yml`)
fails it otherwise. A line for a breaking change, one a host has to act on when it upgrades, starts
with `**Breaking:**`, under the subsection it belongs to.

The repository's tag, `vX.Y.Z`, is this package's version, and one tag releases each package of the
repository whose version has left `-dev`, at its own version; the others stay unreleased at that tag,
though `release.json` lists their versions. Between releases the version in `mix.exs` ends in `-dev`; at a
release, a package with lines under `## [Unreleased]` moves to its next version. Every release moves
the engine, whose version the tag is: a release of other packages alone moves it by a patch from its
last release, and that version's section says so under `### Changed` ("Released with
ehos_contract_auth 0.1.1; nothing in the engine changed."). The maintainers make a release by
their release procedure, and pushing the tag publishes it (`.github/workflows/release.yml`).

## [Unreleased]

### Added

- At start, the engine logs one warning when a contract declares an effect delivered
  `:at_least_once` or a process manager with a timer and the host's Oban runs no queue `:events`,
  where their jobs wait. Until now those jobs stayed in Oban's table and nothing said so. The warning
  names the line to add, `queues: [events: 10]`. It does not stop the start. The engine does not
  check under Oban's `testing: :manual` or `:inline`, or when Oban starts after the engine (#671).

### Changed

- **Breaking:** The package is called `ehos_contract`, as the rest of the EHOS family is, no longer
  `eh_os_contract`: the application `:ehos_contract`, the modules `EhosContract.*`, the tasks
  `mix ehos_contract.*` and the compiler `:ehos_contract`, `config :ehos_contract`, the key variable
  `EHOS_CONTRACT_KEK`, the schema lock `ehos_contract.lock`, the format identifiers
  (`ehos_contract.graph.v1`, `ehos_contract.model.v1`, …) and the OpenAPI and AsyncAPI extensions
  `x-ehos-contract-*`. The storage follows in version 7: it renames every table, index, trigger and
  function from `eh_os_contract_*` to `ehos_contract_*`, rewrites the engine's two event types in the
  log (`ehos_contract.subject_erased`, `ehos_contract.timer_elapsed`) and Oban's jobs of its workers,
  so a timer or an effect scheduled before the upgrade still runs. To upgrade: rename the dependency,
  the compiler and the tasks in `mix.exs`; replace `EhOsContract` with `EhosContract` and
  `:eh_os_contract` with `:ehos_contract` in code, tests, configuration and existing migration files;
  `git mv eh_os_contract.lock ehos_contract.lock`; set `EHOS_CONTRACT_KEK` where the key variable is
  set; and add a migration calling `EhosContract.Migrations.up(version: 7)`. Oban's jobs are
  rewritten in the `oban_jobs` the `search_path` finds; with Oban in another prefix, rename their
  `worker` from `EhOsContract.` to `EhosContract.` there. The engine's moduledoc names version 7, and
  `docs/getting-started.md` the new dependency. The repository is `EmpoweredHouse/ehos_contract`, so a
  dependency from git names `github: "EmpoweredHouse/ehos_contract"`; GitHub forwards the old address.

## [0.15.2] - 2026-11-22

### Changed

- Released with eh_os_contract_web 0.11.0 and eh_os_contract_graph 0.10.0, which require a Phoenix
  LiveView that fixes EEF-CVE-2026-126334 (#660); nothing in the engine changed.

## [0.15.1] - 2026-11-20

### Changed

- **A commit wakes the subscription runners once, not twice** (#648). Where Oban runs on the
  engine's repo, with its Postgres notifier and the log's schema as its prefix, the log's trigger
  wakes the runners at commit, and the engine no longer sends a notification of its own after a
  transaction it owns. The engine checks this at boot. Elsewhere, it notifies as before. Before,
  each commit of the engine that appended an event an ordered consumer reads woke every runner
  twice, and each runner stepped again to find nothing. On such a node, while Postgres's
  notification queue is half full, the trigger sends nothing, and those commits wait for the
  poll.

## [0.15.0] - 2026-11-20

### Added

- **Subscriptions send `:telemetry` events** (#635): `[:eh_os_contract, :subscription, :lag]`
  for each subscription at each poll, and `[:eh_os_contract, :subscription, :step]` after each
  step, with its result and the number of events it applied. `docs/subscriptions.md` lists their
  measurements and metadata.
- **`EhOsContract` takes `subscription_poll:` in the host's list of children** (#635): how many
  milliseconds the runners' poll waits between two looks at the log, 30,000 by default. The child
  refuses any other option, and a value that is not a number of milliseconds from 1 to
  4,294,967,295. Before, it ignored its options.

### Changed

- **Breaking:** **an append wakes the subscription runners when its transaction commits, also in a
  transaction that the host's code owns** (#635). Before, such an append waited for the poll.
  The storage goes to version 6, which adds a trigger on `eh_os_contract_events` that sends a
  notification at commit: add a migration that calls `EhOsContract.Migrations.up(version: 6)`.
  The engine refuses to start on version 5. An engine before 0.15.0 refuses to start on version 6:
  stop the nodes of the old release before you migrate, and to go back to 0.14, run
  `EhOsContract.Migrations.down(version: 6)` with 0.15.0 first. The notification goes through
  Oban's Postgres notifier, on the channel of Oban's prefix that is the schema of the log. The
  poll now waits 30 seconds, not 1. So if Oban has another prefix or another notifier, an append
  in a transaction of the host's own code waits up to 30 seconds: set `subscription_poll:` lower.
  At commit, `NOTIFY` takes one lock for the whole Postgres instance, so the commits that notify,
  of every application on the instance and of Oban, wait for each other. A schema name of 44
  bytes or more, or a notification queue half full, sends no notification, and the poll finds
  the append.
- **While nothing is appended, a subscription starts no transaction and writes no log line**
  (#635). One process on each node reads the head of the log and the subscription rows at each
  poll, without a lock, and wakes only a runner that is behind. Before, each runner took its row
  `FOR UPDATE SKIP LOCKED` each second, and a host's `:debug` log showed 4 queries for each runner
  each second. A step that applies events now writes one `:debug` line with the key, the number
  of events and the new position, and the queries of a step that finds nothing pass `log: false`.
  A runner that finds its subscription held by another runner tries again after 1 second; its
  step event's `result` is then `:held`. A relay's `:failed` step counts the events it published
  before the failure.

## [0.14.4] - 2026-11-17

### Changed

- Released with eh_os_contract_auth 0.15.0, whose development sign-in page takes the application's
  look (#640) and removes the token from its address (#642); nothing in the engine changed.

## [0.14.3] - 2026-11-16

### Changed

- Released with eh_os_contract_auth 0.14.0, which reads `ehos.yaml/v8` and writes
  `ehos.manifest/v9` (#634); nothing in the engine changed.

## [0.14.2] - 2026-11-12

### Changed

- Released with eh_os_contract_auth 0.13.1, which fixes the development mode's sign-in link and
  refuses `pin_keys: true` in a release (#620, #623, #628); nothing in the engine changed.

## [0.14.1] - 2026-11-12

### Changed

- Released with eh_os_contract_auth 0.13.0, which adds a development sign-in mode (#619); nothing in
  the engine changed.

## [0.14.0] - 2026-11-05

### Added

- **A master key that you destroyed can be named in the configuration** (#578).
  `config :eh_os_contract, EhOsContract.Vault, destroyed: ["2026-03"]` lets the engine start when a
  restored backup holds data keys that a destroyed master key wraps. When it reads, the engine does
  not unwrap those data keys, and reads their subjects as erased. At boot, it tries one data key of
  each destroyed master key, and does not start if the vault unwraps it. The rewrap leaves them,
  and `erase/3` deletes them and records the erasure. At boot, a warning counts them. Call
  `EhOsContract.erase/3` for each of those subjects, as `docs/master-keys.md` says: until then, the
  read models keep what they projected of them. A command with new personal data for such a
  subject gets `{:error, :subject_erased}`. While `destroyed:` names a key, a read that meets a
  subject without a readable data key runs one more query, and a dispatch that meets one runs two.
  Before, the engine did not start, and the Mix tasks that start it did not run.
- **`EhOsContract.call/3` takes a form's params with `form: true`** (#589). It reads them as
  `EhOsContract.Form` does: every value as text, a blank field as absent, and the rows that
  `inputs_for` sends. A page sends a person's command through `call/3`, as `/api` does: the
  `Authorizer` is asked before the fields are read, a field the host supplies is refused in the
  params, and the `Supplier` is asked for it. With `form: true`, `call/3` also takes `data:`, as
  `Form.changeset/4` does, with the same checks: its identity replaces a value the params carry for
  it, and its other fields are the values the params leave out. A field the host supplies is
  refused in `data:`. `Form.refused/3` takes each answer of `call/3`, and
  does not put an error twice that the changeset already holds. `docs/forms.md` and its diagram
  show this path. `dispatch/3` with `Form.to_struct/1` still works.
- **`mix eh_os_contract.check` warns about a scoped actor with an unscoped query** (#559). The new
  warning `scoped-actor-with-unscoped-query` names a query that has an actor with a scope in `by:`
  and no `scope:`. Such a query answers the rows of each value: a lead with a grant for warehouse 7
  reads the rows of warehouse 12. Before, only an unscoped command got a warning. A contract with
  such a query now gets one warning for each `:human` actor with a scope in its `by:`. A new warning
  only: no verdict moves, but a host that runs `check --warnings-as-errors` fails until it scopes the
  query or names a different actor.

### Changed

- **The glossary defines "graph document" and "overlay"** (#517). The pages of
  `eh_os_contract_web` and `eh_os_contract_graph` use both words.
- **The docs of the behaviours and the Mix tasks are rewritten by the shared writing rules** (#517).
  They generate `docs/behaviours.md` and `docs/cli.md`, and hexdocs shows the same text. Each page now
  starts with its scope and ends with "Next steps". `EhOsContract.Bus` has a diagram of what occurs
  between the relay, the bus and the inbox. The docs now say that `mix eh_os_contract.report`,
  `mix eh_os_contract.subscriptions`, `mix eh_os_contract.rewrap` and `mix eh_os_contract.graph
  --overlay` start the whole application. The docs of a rotation of a master key now tell the
  operator to check the key of each data key before the old key goes (#541). Corrected facts: the
  supplier is asked by `dispatch/3` and `record/3` with `supply: true`, and its refusal is 503 over
  HTTP; a raise in `publish/2` makes the relay `failing` after three attempts, not at once; the
  report's contract section answers questions 1, 2 and 4, and a process module's section question 3;
  a name of a command, a query or a recorded event is unique in its domain, not in the application.
- **Breaking:** **The rewrap takes the id of the new master key, and refuses a vault that wraps
  with another key** (#541). Run `mix eh_os_contract.rewrap --expect 2026-09`, or call
  `EhOsContract.Personal.rewrap!(MyApp.Repo, "2026-09")`. If the first key of the list is not that
  key, the rewrap stops before it changes a data key. The batch size moves to the third argument:
  `rewrap!(MyApp.Repo, 50)` now raises `FunctionClauseError`. Before, a rewrap with the list of
  before the rotation wrapped each data key with the old key again, and ended without an error. The
  next deploy then removed the old key, and the personal data did not unwrap.
- **The page on authorization is split by what a reader asks** (#517). `docs/authorization.md` is a
  Concept page, "How is a call authorized?", with two diagrams: the order of a call from sign-in to
  the answer, and which calls the Authorizer checks. Three how-tos take the rest: `scope.md` narrows a
  call to the values of a grant, `authorizer.md` adds a rule of your own, and `calls.md` serves the
  contract over HTTP, through `call/3` or from code. The status table is gone. The pages now say that
  a recorded event has no scope, that `eh_os_contract_auth` signs a person in itself, that a
  credential can expire in up to 15 minutes, and that a removed key stays trusted while fetches fail.
  The table of what each answer writes now has the refusals after the Authorizer and a repeated
  idempotency key. Links change: the sections on scope, the Authorizer, the plug, `call/3` and
  idempotency keys are now on the three new pages.
- **The page on processes is split by what a reader asks** (#517). `docs/process.md` is a Concept
  page, "What is a process module?", with one diagram: which verdicts a promise can have, and what
  moves it. Recording an outage of an external system is a how-to, `outages.md`. What the
  conformance report prints is a Reference page, `conformance.md`: each section, each sentence of a
  process module, and the JSON document. The pages now say that a report with a period judges a
  promise only on the events inside the period, while the deadline and the order of stages read each
  run whole. They also give the names of the verdicts, `:satisfied` and `:violated`, beside the
  report's "Met" and "BREACHED". Links change: the sections of `process.md` on recording an outage
  and on how the report reads a process are now `outages.md` and `conformance.md`.

### Fixed

- **The check of the master keys at boot checks again when a rewrap moved the data keys in
  between** (#579). If a data key does not unwrap, the engine counts the data keys of its master key
  in a second statement. A rewrap on another node can move the last of them to another master key
  before that count. Before, the engine then refused to start with "0 data keys are wrapped by
  master key …". It now takes the samples again and checks the key that holds the data keys now.
  If the data keys move in each of 3 checks, it refuses to start and says that a rewrap is likely
  running.
- **Moves a verdict:** **dispatch asks the supplier inside its transaction, and again on a retry**
  (#563). A command or a recorded event with a field `supplied_by: :host` gets the value from
  `EhOsContract.Supplier` inside the transaction that appends its events. If the stream changed and
  dispatch tries again, it asks again. So `supply/2` can lock the rows that it reads, and a
  concurrent save of them can no longer change the fact before the append. Before, dispatch asked
  one time, before its transaction, and used that answer for every retry. Such a command that reads
  entities (`reads:`) now reads them in the same transaction, after the answer, and again on a retry.
  For a command that creates a unit with a generated identity, `Supplier.Request.given` now holds
  that identity. The `Supplier` docs say what the transaction asks of `supply/2`: the connection it
  holds, the order of locks, and what is kept after a refusal. The verdict moves because an
  exception of the supplier, or of the entities read for such a command, now records the command
  as failed when the transaction is the engine's own, and the conformance report counts it as an
  attempt that failed; before, the engine recorded nothing.
- **Breaking:** **the engine does not start when a stored data key does not unwrap** (#573). At boot,
  the engine unwraps one data key of each master key that `eh_os_contract_subject_keys` names. If one
  does not unwrap, it raises with the id of that master key and the count of its data keys. Before,
  the vault checked only its configured keys. A host that removed a master key that still wraps data
  keys, or changed the bytes of a key and kept its id, started, and the first read of each such
  subject raised. Such a host now stops at boot, unless the data key that the engine tries still
  unwraps, as one from after a change of bytes does: put the key back, and run
  `mix eh_os_contract.rewrap --expect <id of the current key>` before you remove it. If the data
  keys of a restored backup name a destroyed master key, the engine does not start either.
- **`scoped-actor-with-unscoped-command` no longer warns about a `:system` actor** (#559). Dispatch
  does not narrow an actor of kind `:system`, so the command's `scope` narrows nothing for it.
- **Breaking:** **`EhOsContract.Plug` refuses a command or a recorded event that is not JSON** (#558).
  A `POST` must have the header `content-type: application/json`, with or without parameters such as
  `charset`. Otherwise the answer is 415, `{"error": "unsupported_media_type"}`, and nothing is
  dispatched. Before, the plug read any body. A page of another origin could then post a form, or a
  `fetch()` with no content type, with the cookie of a person signed in, and issue a command as that
  person. A browser asks the host before a page of another origin can send `application/json`. Clients
  that send no content type, or another one, must send `application/json`, also for an empty body.
  The OpenAPI document lists the 415 for each command, so the digest of each contract with a command
  changes.
- **Breaking:** **Moves a verdict:** **a skip during a rebuild continues the rebuild** (#550).
  Before, `mix eh_os_contract.subscriptions --skip` always put the subscription back to `running`. A
  read model delivered `:in_transaction` then never got the events after the skipped one, and a
  process manager reacted to the history after it: it issued commands and set timers for past
  events. Now a skip puts the subscription back in the status it failed in, so the rebuild or the
  replay continues after the event. Dispatch also leaves a `failing` read model delivered
  `:in_transaction` alone, as a `rebuilding` one; the runner takes those events after the skip, and
  a query with `min_position:` waits for it. An erasure still calls its `forget/2` at once (#557),
  but inside a savepoint: if `forget/2` raises on the partial rows, the engine undoes what it wrote,
  logs a warning, and the erasure continues. Before, that raise failed the erasure, and every later
  one. A `forget/2` that raises or rolls back inside a `Repo.transaction` of its own still fails the
  erasure. The task's list says "while it replays the log" for a subscription that failed during a
  rebuild or a process manager's replay, and `--skip` of an unknown key says that the key is not a
  subscription, not that it is not failing. The storage goes to version 5, which keeps that status:
  add a migration that calls `EhOsContract.Migrations.up(version: 5)`. The engine refuses to start
  on version 4. The migration marks a read model delivered `:in_transaction` that is `failing` at
  the upgrade `stale`: the next boot empties it through `reset/0` and rebuilds it from the start,
  and until the rebuild ends its queries read part of the rows. Another kind that is `failing` at
  the upgrade goes back to `running` on a skip, as before: reset a process manager that failed
  during its replay instead of skipping it.
- **`mix eh_os_contract.check` no longer warns that a `:separate_ways` relation is crossed by no
  reference** (`orphan-context-mapping`, #537). The relation says that the two contexts do not depend on
  each other, and the compiler refuses a reference across it. The only way to silence the warning was to
  remove the relation, and that removed the refusal too. A domain with such a relation has one warning
  fewer for each; no verdict moves.

## [0.13.1] - 2026-11-01

### Added

- **A glossary of the contract language** (#511): `docs/glossary.md` gives each word one meaning, from
  actor to verdict, with the four questions of conformance. The library's word for something that
  occurred is "event", not "fact"; a read model is a consumer of events, not a reaction.

### Changed

- **`docs/contract.md` is a how-to, and the compile refusals have a page of their own** (#517). The guide
  tells how to write a domain, a contract and a process module, in short sentences, with two diagrams:
  what is checked at which time, and which module names which. Every refusal code, with the layer that
  refuses it, is now in `docs/refusals.md`. The layers have names, numbered in the order they run:
  the schema, one module, the implementation, between modules and the check. So the design record's
  L3, the rules between modules, is layer 4, and its L4, the implementation, is layer 3. Links change: `contract.md#refusals-<family>` is
  `refusals.md#refusals-<family>`, and `contract.md#process-modules` is `contract.md#write-a-process-module`.
  The `eh-os-contract` plugin's skills point at the new page, at 0.14.1.
- **One overview page, and a getting-started page with each step's result** (#517).
  `docs/introduction.md` tells what the engine does and does not do, with two diagrams: how a domain, a
  contract and a process module fit together, and how the contract reaches the conformance report.
  `docs/getting-started.md` now holds the installation, with its prerequisites, the result of each step
  and a diagram of dispatch. The README is short and links to both. Links change: the README's sections
  are gone, `README.md#installation` among them, so link `getting-started.md`; the steps of
  `getting-started.md` have anchors of their own, such as `getting-started.md#dispatch-a-command`. Rotating
  a master key, and what an erasure does not reach in backups, moved to the concept pages
  (`master-keys.md`, `personal-data.md`).
- **The domain pages are split by what a reader asks** (#517). `docs/domain.md` tells how a domain
  divides a business into contexts, with the relation patterns in one table and a diagram of which context
  depends on which. Personal data and erasure have a page of their own, `personal-data.md`, with a
  diagram of an erasure; rotating a master key, writing a vault for a key management service and restoring
  a backup older than an erasure are a how-to, `master-keys.md`. `domain-data.md` keeps the actors, the
  values, the entities and the external systems. `forms.md` is a how-to, with a diagram from a keystroke
  to a refusal. The glossary defines "data key", "master key" and "form". Links change:
  `domain-data.md#subjects-and-personal-data` is `personal-data.md`, and the headings of the four pages
  are questions or tasks, so their anchors change.
- **The concept pages are in `docs/`, beside the other pages** (#517). `docs/concepts/units.md` is now
  `docs/units.md`, and so for each concept page. ExDoc already published them in one directory, so their
  addresses on hexdocs do not change. A link to one of them on GitHub changes its path. The diagrams of
  the domain, personal data and forms pages now show in the HTML documentation, which looked for them
  outside its own directory.
- **The units and scenarios pages are split by what a reader asks** (#517). `docs/units.md` tells what
  an aggregate, a dynamic consistency boundary and a domain service are, with two diagrams: the
  lifecycle of an aggregate, and which events each kind of unit reads. Writing the module of a unit is a
  how-to, `deciding.md`, and changing an event that already has rows is a how-to, `event-versions.md`.
  `docs/scenarios.md` tells what a scenario is and how the engine runs it, with one diagram of what the
  engine does for each kind of trigger. The glossary defines "property test", "schema version",
  "target", "trigger" and "upcast". Links change: the sections of `units.md` on the code that decides
  and on an event that already has rows are now `deciding.md` and `event-versions.md`. The
  `change-contract` skill of the `eh-os-contract` plugin names `event-versions.md`, in plugin 0.14.3.
- **The pages on reactions, reading and other contracts are split by what a reader asks** (#517).
  `docs/reactions.md`, `docs/reading.md` and `docs/between-contracts.md` are Concept pages, each with
  one diagram: where each consumer runs and what a failure leaves, how an event becomes a row and an
  answer, and what occurs from a publication to the policy's command. Writing the modules of a read
  model and a query, and asking the query, is a how-to, `read-models.md`. Moving a subscription past an
  event, rebuilding a read model and replaying the log is a how-to, `subscriptions.md`. The pages now
  say that a `failing` subscription does not try again by itself, and that a reset is not a retry:
  what a reset of a policy, a relay and a process manager costs, and that it fails for a read model
  without `reset/0`. Links change: the sections of `reading.md` on the modules and on
  asking a query are now in `read-models.md`.

### Fixed

- **`docs/contract.md` said that a unit whose events are all recorded needs `evolve/2` when it keeps
  more state than its identity** (#517). Dispatch never folds such a unit, and the check asks for no
  module. It needs a module only for an upcast step by a function. That module then has `evolve/2`
  if the unit keeps state.
- **`mix eh_os_contract.schema`'s documentation said that a personal field may never change its type**
  (#517). A change that old rows still read, an `:integer` made a `:decimal`, is recorded in place, as
  for any field. Its list of tagged fields now names a domain value resting on an `:id`, a `:date` or
  a `:timestamp` too. `docs/cli.md` follows.
- **The installation never said that Oban must run the queue `:events`** (#517). Without it, the jobs of
  the effects delivered `:at_least_once` and of the timers of process managers wait in the table: no
  effect runs, and no timer fires. `docs/getting-started.md`
  now configures the queue.
- **The opening of `docs/contract.md`** said a contract is written once per process with its promises. It
  now says what the rest of the page says: a contract belongs to one context, and a process module holds
  a run and its promises. The page no longer counts a read model among what reacts to events (#511).
- **`docs/domain.md` and `docs/between-contracts.md` said an application has one domain.** It may hold
  more, as the tasks' `--domain` and the sandbox show; each domain keeps its own contracts, and only the
  domain named after the application publishes.
- **The pages, the DSL reference and the moduledocs called an event a "fact"** (#512). They now say "event",
  as the glossary does: `idempotent_on:` names the fields that make one event, and the inbox takes one event
  once. The message of a policy or a read model that takes another context's event without declaring its
  delivery (X10) says that its failure rolls the other context's event back.
- **The glossary and `docs/authorization.md` named only the capabilities of a person** (#515). They now also
  name `<published name>.subscribe`. The engine derives one for each subscribed event that a policy takes.
  The application holds it, not a person.

## [0.13.0] - 2026-10-29

### Added

- **`EhOsContract.Testing.assert_read_model_tables/1`: a read model's table checked against its
  contract** (#493). In a host's test, it reads every read model with `table:` from the test
  database and fails, naming each problem, on a missing table or column, a column of another type
  than its field is stored as, a required field's column that takes `NULL` (a personal field's may,
  since an erasure blanks it), a primary key that is not the `key:`, and a column of the
  projection's own that is `NOT NULL` with no default. A field added to a contract and not to its
  migration then fails in the tests, not at the first write.
- **`mix eh_os_contract.gen.migration`: a read model's migration written from its contract** (#493).
  `mix eh_os_contract.gen.migration Lending.Contracts.Membership member_directory`, or `--all` for
  every read model with a table no migration creates yet, writes `<timestamp>_create_<table>.exs`
  into the repo's migrations: a column per field of the type it is stored as (text, `bigint`,
  `numeric`, `boolean`, `date`, `timestamp` with microseconds, `jsonb` for a value made of fields
  and a list of them, an array for another list), the `key:` as the primary key, `null: false` on
  a required field that is not personal, and an index on each subject's identifier and query scope.
  The migration is the application's to edit; it never overwrites one.
- **`EhOsContract.Form`, a form's changeset from a command's declaration** (#474), and from an
  event an actor records or a query's params, for `record/3` and `query/3`.
  `Form.changeset(contract, module, params, data: ...)` reads what an HTML form, or any input that
  arrives as text, sends:
  - every value as text, a blank field as absent, a select's text as an enum's member;
  - each field held to the rules dispatch applies: required, of its declared type, and within
    its domain value's invariants, asked of the domain.

  Each problem is an error at its field, with the engine's reason in its keyword list
  (`validation: :required | :type | :invariant`, and `invariant:`), so the application writes
  its own words. The identity of the unit an edit form changes comes from `data:`, never the
  params; a supplied field and a generated identity are left to dispatch. `Form.to_struct/1`
  turns a valid changeset into the struct `EhOsContract.dispatch/3`, `record/3` or `query/3` takes.
  A unit's invariants
  and a command's constraints are not asked: they come back as dispatch's refusal, which
  `Form.refused/3` puts back on the changeset, each field's problem at its field and a rejection
  at the field `at:` names for its rule, or on the whole form (`:base`), where a problem at a field
  the form never sent goes too. A domain value with fields, or a list of them, is a row each, which
  `inputs_for` renders with its own errors, and a field the params leave out keeps the value
  `data:` gives it. `Form.changeset/2,3` builds it by a capability's name too, `{:command, name}`,
  as `call/3` takes it; `call/3` keeps JSON's types, and `docs/authorization.md` says a form's text
  goes through `Form` (#132). A new concept page,
  `docs/concepts/forms.md`, states the rule from both sides (the contract holds the rules, the
  changeset checks only the input's shape, a form never copies an invariant) with a LiveView page.
- **A domain lists an enum value's members** (#472): `Lending.Domain.members(:bike_kind)` is
  `[city: "City bike", road: "Road bike"]`, in the order declared, each with its label or `nil`, so a
  select's options or a check read them from the domain instead of a copy. A value named after an
  enum value has its members; any other name raises `ArgumentError`.
- **A read model names the table its rows are kept in, and their key** (#472):
  `read_model :member_directory, "…", table: "lending_member_directory", key: :membership_id`.
  The key, one row field or a list of them, is the table's primary key, required with `table:` and
  refused without it. A new refusal (`P6`) holds both: a table that is not a plain SQL name, is longer
  than the 63 bytes Postgres keeps, is the engine's or Oban's, or is shared by two read models of any
  contracts, and a key field that is not a row field, is named twice, or is optional, personal, a list,
  or a domain value made of fields or that is a list.

### Changed

- **Breaking:** **a domain value made of fields is a struct of its own** (#486),
  `Lending.Domain.Values.Address`, generated in the module that already holds its invariants' callbacks,
  if it has any, and named by `EhOsContract.Model.module_for(domain, :value, name)`. Its required fields
  are enforced, so `%Address{}` without one does not compile, and the value's type in
  `Lending.Domain.Values` is the struct's. The engine hands the struct wherever the value appears: an
  event or a command read from the log or decoded from a caller, a unit's state, a scenario's data,
  a generated value, `EhOsContract.Form`'s rows, a read model's `Row` and a domain's invariant
  examples. A map in its place is not the value: a command or a recorded event that carries one is
  refused with `{field, :type}`, and an event a decision returns with one raises; so do an
  `EhOsContract.Entities` row, an `EhOsContract.Supplier` answer, a domain service's argument or
  result, `Form`'s `data:` and a write through a `Row`. Build the value as its struct
  (`%Lending.Domain.Values.Address{street: …}`). A scenario's data stays a map, which the engine
  casts, and so does a state field's `default:`, which a contract cannot write as the struct: it is
  a map until the first event's `evolve/2` sets the field.
- **Breaking:** a domain value's struct, and a contract's command, event and state structs, are inspected without
  their personal fields, so a value printed in a log, a crash report or a failed test's message
  leaves the person's data out, as a read model's `Row` does. An assertion that fails only on a
  personal field shows both sides alike; compare `Map.from_struct/1` to see the field. A host that
  defines its own `Inspect` for one of these modules, one with personal fields, now redefines the
  engine's (a warning, an error under `--warnings-as-errors`): remove it, or keep its own and accept
  that it, not the engine, decides what is printed.
- **Breaking:** **a read model's `Row` is an Ecto schema** (#472), of its `table:` with its `key:`
  as the primary key, or an `embedded_schema` when it names no table. A projection writes through it
  (`insert_all(Row, rows, ...)`) and a query reads `from r in Row` and answers the structs Ecto loads,
  with no `select:` map and no conversion: each field has the contract's type, an enum an `Ecto.Enum`
  stored as its member's name, a `:timestamp` `:utc_datetime_usec` that writes a time of any
  precision, so a scenario's `given`, which happens to the second, is projected as a dispatched event
  is, a domain value the type the domain gives it, read from the domain once it is compiled, so the
  contract still does not depend on its domain at compile time. A value made of fields is a `jsonb`
  column, a list of them too, written in the log's form and read back as the map an event carries, so
  a projection writes `event.address` as it is; a personal field of it that was erased is written and
  read back `nil`. A personal field is redacted when a row is inspected. An enum's member the contract
  no longer declares cannot be loaded, so a query over a row that holds one raises until the read
  model is rebuilt. `EhOsContract.Form`'s changeset types a `:timestamp` field with the same type,
  which casts as `:utc_datetime_usec` does.
  A `Row` of a table carries Ecto's `__meta__`: code that lists a row's fields reads
  `Row.__schema__(:fields)`, not the struct's keys. `docs/concepts/reading.md` writes and reads its
  example through `Row`.

## [0.12.0] - 2026-10-27

### Changed

- `mix eh_os_contract.graph`'s documentation (`docs/cli.md`) names `mix eh_os_contract.bundle`, in
  `eh_os_contract_auth`, which writes its documents with the manifest as the bundle EHOS takes (#456).
- `docs/authorization.md` names `ehos.manifest/v8`, which `eh_os_contract_auth` writes for an `ehos.yaml/v7`
  that asks for the CPU and memory its workload needs (#453).

### Security

- **Breaking:** the engine requires `decimal` `~> 3.2`, no longer `~> 2.0 or ~> 3.0`. Before 3.0
  `Decimal.new/1` took any exponent (CVE-2026-32686), which a caller's text for a `:decimal` field
  reaches; 3.1.1 and earlier allocate without bound in `Decimal.round/3` (EEF-CVE-2026-97853), which
  the engine never calls but a host may. A host whose lock holds an older `decimal` runs
  `mix deps.update decimal` (#416).

## [0.11.0] - 2026-10-26

### Added

- **A command's scenario can be `rejected` on an invariant of a domain value its data breaks** (#458): `command
  :open_month, %{period_id: "2026-13"}` followed by `rejected :named_by_month`, where the value types a field of
  the command or, since #435, its unit's identity. Dispatch refuses such a command before anything decides it,
  and a contract can now say so; S4 accepts the name when the command's fields hold a value that declares it,
  checked against the domain. `EhOsContract.ScenarioCase` holds the fields a scenario gives to their values'
  invariants before the lifecycle and the decision, as dispatch does (see the Breaking line under Changed). Such
  a scenario covers no invariant of the unit (S8), appears in no generated "refused in", and is not counted by
  the conformance report's scenario coverage, since dispatch records no decision for it: no verdict moves. A graph document names the value and its
  invariant in a unit scenario's new, optional `rejected_on_value`, beside `rejected`. Where two values a
  command's or a recording's fields hold declare an invariant of one name, the graph and the owner's pages name
  the value whose invariant the scenario's data breaks, not the first declared; to tell, `mix
  eh_os_contract.graph`, `mix eh_os_contract.pages` and the dashboard's graph ask the domain's value checks of
  that data, as dispatch would, and name the first declared where the checks cannot be asked.
- **A scenario can record an event** (#430): `record :collected, %{…}` with the `actor` who records it shows
  what an actor of the event's `recorded_by:` may write into the log, `expect`ing the event or `rejected` on the
  invariant of a domain value its data breaks. `EhOsContract.ScenarioCase` holds it to what `EhOsContract.record/3`
  checks before it reads the log, and runs no implementation. The compiler requires the `actor`, among the
  event's `recorded_by:` (S7), expects only the event recorded (S5), and a `rejected` naming an invariant of a
  value the event's fields hold (S4). A graph document carries such scenarios in a new `record` group of its
  `scenarios`, with its own `scenario_record` shape in `graph.v1`, and the exported model a scenario's trigger of
  kind `record` beside `command`, `on` and `query`.
- **`mix eh_os_contract.check` warns of an event an actor records that no scenario records**
  (`recording-without-scenario`, #430). A new warning only: no verdict moves, but a host running
  `check --warnings-as-errors` with a `recorded_by:` event turns red until it adds a scenario that records it.
- **A value may be declared a code, `code: true`** (#431): text whose invariants pin its form, such as a tax
  number, `value :nip, :string, code: true do invariant :valid_check_digit, … end`.
  `free-text-not-personal` no longer reports a field of such a value, or of a value or a list naming it, as
  free text, so the notice keeps to text a person typed. A code that is not text, or that neither declares an
  invariant nor names a value that does, does not compile (`D3`). Declaring it moves no domain's version.
- **A unit's identity field may be typed by a domain value resting on `:id`** (#435): `identity [:company_id,
  period_id: :period]`. Dispatch holds the key to the value's invariants as it holds any field, so a command or
  a recorded event keyed by a month "2026-13" is refused with `{:period_id, {:invariant, name}}` where it was
  appended before. Until now an identity was `:id` or `{:id, name}` only, and a value's invariant never held a
  unit's key. A unit that changes its identity's type from `:id` to such a value keeps its streams, tags and
  `eh_os_contract.lock`; only new commands are checked. A value that does not rest on `:id` is refused (`F1`),
  and so is a value in a generated identity. `EhOsContract.PropertyCase` and `EhOsContract.Generators.history/3`
  draw such a key from the value's `satisfied_by:` examples, as they draw any field of it.
- **A boundary may `match:` a local event's field typed by a domain value resting on `:id`** (#435), as the
  append already tags the event with it and as a sibling's event already allowed (`X6`). A contract that
  matched one used to be refused at compile time (`A4`); now it compiles, and only a value resting on another
  type is refused, against the domain.

### Changed

- **Breaking:** **A command's scenario is held to its values' invariants as dispatch holds the command** (#458).
  A scenario whose data breaks an invariant of a domain value one of the command's fields holds, its identity
  included, and that expects events, failed only in dispatch and passed as a test; it now fails, naming the
  invariant. Give it data the value accepts, or say it is `rejected` on that invariant.
- `docs/contract.md`'s row for `I4` says what `emit/1` and `issue/1` accept: a struct literal, a list of them, or a
  `for` producing them; it read as if a list or a `for` were refused (#434). `docs/concepts/units.md` shows a
  decision emitting one event per item with a `for`.
- **A field typed with a value of the domain says the value's name as the value's own word** (#432): in
  `mix eh_os_contract.check`, `term-of-another-context` no longer warns, and `word-without-term` no longer lists
  the word, when the word is the name of the value the field is typed with. A context whose field `:office_nip`
  has the type `value :nip` need not copy the term "NIP" another context defines; the rest of the name is still
  read.

## [0.10.0] - 2026-10-24

### Added

- **`EhOsContract.Report.Sentence` is public** (#421): the sentences of a conformance report without its layout,
  for a host that shows conformance its own way, as the dashboard does in HTML. Its moduledoc says which part of
  `EhOsContract.Conformance.report/2` each sentence reads.

### Changed

- **Spark may be any 2.x from 2.7.3** (#421), where it had to be a 2.7 patch from 2.7.3: a host that uses a newer
  Spark, as Ash's releases bring, resolves with the engine.
- **`EhOsContract.Dispatcher` is no longer documented** (#421): what a host calls is `EhOsContract.dispatch/3`,
  `record/3`, `query/3` and `call/3`. What dispatch checks, in which order, and how it handles a conflict and a
  failure is now on `EhOsContract.dispatch/3`, and the types are `t:EhOsContract.refusal/0`, `t:EhOsContract.problem/0`
  and `t:EhOsContract.call/0`. `EhOsContract.Dispatcher.refusal()` still names the same type.
- `docs/authorization.md` names `ehos.manifest/v7`, which `eh_os_contract_auth` writes for an `ehos.yaml/v6`
  that asks to send mail through EHOS (#429).
- **Hexdocs lists the modules in groups** (#421): writing a contract, dispatch and queries, the log, delivery,
  personal data, conformance, the model and its documents, testing and configuration.

## [0.9.1] - 2026-10-23

### Changed

- `docs/authorization.md` names the manifest versions `eh_os_contract_auth` writes as they are: `ehos.manifest/v2`
  to `v6`, `v6` for an `ehos.yaml/v5`, which may name the hosts outside the installation the application
  reaches; it said `v2` to `v4`.

## [0.9.0] - 2026-10-22

### Added

- **`mix eh_os_contract.graph --output-dir DIR` writes every document of the application in one run** (#404):
  each domain's, contract's and process module's `graph.v1` document, as `domain.<module>.json`,
  `contract.<id>.json` and `process.<id>.json`, each the bytes `--output` writes for it, so a pipeline sending
  them with a deployment boots the project once. It refuses a directory that holds anything, and goes alone.

## [0.8.1] - 2026-10-22

### Changed

- Released with eh_os_contract_graph 0.5.0; nothing in the engine changed.

## [0.8.0] - 2026-10-21

### Added

- **`EhOsContract.Dependency` is part of the public API** (the publication programme, PB2, #369). A host
  using `boundary` could not call it, since the engine's boundary did not export it, and no page said how
  to record an outage. It is exported now, and [processes](docs/process.md) says how to record one.
- **An actor says which roles a person in it may grant**, as agreed with EHOS.
  `actor :office_employee, :human, "Office employee", may_grant: [:client]` lets a person holding the
  office employee's role grant the client's role through the application, once EHOS grants under the rule.
  `D4` refuses the rule on a system actor, naming the actor itself, a system, an undeclared actor or one twice,
  and rules that lead back to an actor. [Actors](docs/domain-data.md#who-may-let-whom-in) says
  more.

### Changed

- **The documentation's examples are in English, on invented material** (the publication programme, PB3,
  #375). The module docs, the DSL reference, `docs/authorization.md`, `docs/cli.md` and the older entries of this
  changelog take their examples from a library lending copies, a shop fulfilling orders and a subscription billing
  instead of a clinic with Polish labels, and a value's `unit:` example is `:cents`. Nothing a host calls changed.
- **Moves a verdict:** **an outage is stamped with the engine's clock** (#369).
  `EhOsContract.Dependency.observe/3` and `unavailable!/4` take the moment from `EhOsContract.Clock.now/0`
  instead of the wall clock. Outside `EhOsContract.Clock.at/2` nothing changes; inside it, as in a host's
  tests, an outage now lands where the clock says, and can suspend the run whose window it falls in.

## [0.7.0] - 2026-10-17

### Added

- **Moves a verdict:** **A promise names the systems it waits on through an earlier step** (plan DD, stage OW1,
  #355): `waits_on [:metering]` in a process module's `promise`. An outage of one of them inside the window,
  observed by any contract the process includes, suspends the promise as an outage of what its `eventually` or
  `or_else` depends on does: an invoice neither issued nor disputed while the metering system was down is
  suspended, not broken. Each name is an external of the domain, and not one `eventually` or `or_else` already
  depends on, and one a contract the process includes uses (X4); a scenario's `outage` may name it. The
  process's page, `mix eh_os_contract.view` and its `graph.v1` document show it, the last as a `waits_on`
  relation from the promise to the external, which every process document now carries, empty without one, so
  each process document's digest moves once. A promise without it keeps its digest, so no process's version
  moves. An outage anywhere inside the window counts, even after the step that calls the system is done.

### Changed

- **Breaking:** **A duration longer than 100 years does not compile** (plan DD, stage DU1, #193): a process
  manager's timer's `wait`, a process module's `within` and its `deadline`. A year is counted as 366 days and a
  month as a twelfth of that, so `wait: {100, :year}` and `wait: {1200, :month}` compile and `wait: {1201, :month}`
  does not. The limit is a chosen one, far inside what a date can hold: `wait: {10_000_000, :year}` used to compile
  and fail on every retry when its timer was set. A contract with a longer duration stops compiling; none is
  expected to have one.

## [0.6.1] - 2026-10-17

### Changed

- Released with eh_os_contract_auth 0.4.0; nothing in the engine changed.

## [0.6.0] - 2026-10-17

### Added

- **A change to an event's fields made without a new version is noticed** (plan DD, stage V3, #340): `mix
  eh_os_contract.schema` records the fields of every event, by its type in the log and its `schema_version`, in
  `eh_os_contract.lock` beside the project's `mix.lock`, as a row holds them: a domain value as its shape, with
  whether a field may be absent, is personal and whose identifier seals it. `--check` writes nothing and fails on a
  missing file or entry, on a recorded version whose fields changed so that an old row would not read, naming each
  field, on a recorded version newer than the declaration, and on an event no contract declares any more, renamed or
  removed. `--forget TYPE` drops an event's versions from the declared one up, or all of an event no longer
  declared, and records what is declared, for versions no log holds rows of. To use it, run
  `mix eh_os_contract.schema` once, commit the file and run `--check` beside `mix eh_os_contract.check`.

- **The lock records in place a change old rows still read, and holds a new version's steps to what changed**
  (plan DD, stage V4, #346). Recorded in place: a field added as optional, a field removed (kept, marked `removed:
  true`, so a field declared again under its name is held to what old rows hold), required made optional, an enum
  given members, `:integer` made `:decimal`, `:id` made `:string`, inside lists and domain values too. A raised
  version's steps must cover what changed from every earlier recorded version: `rename:` a renamed field, `default:`
  a new required one, a function anything else. Refused even with a step: a field that becomes personal or stops
  being, or is sealed by another identifier; a personal field whose type changes, or a value holding personal data
  whose shape does; a required personal field, at any depth, that old rows may lack; an identifier that seals a
  field given another `subject:`; and a field the log tags rows with that the version before did not tag.

- **An old row read through a function, where a rename and a default cannot say the change** (plan DD, stage V2,
  #338): `upcast from: 1, function: :amount_from_minor` names a function of the unit's implementation, which takes a
  row's payload at that version as the log stores it and gives the next version's. The implementation does not
  compile without it (`I2`). Reading refuses the row, naming the step and never a value, when the function moved
  or made a sealed personal value, changed a field the log tags rows with, raised, threw, exited, or gave no map. What
  it gives is read as the log stores a value, so a decimal, a date or an atom key reads as an old row's own. A step by
  a function takes neither `rename:` nor `default:`, and is not named like a command of the unit or like `emit`,
  `reject` and `issue` (`U2`). `mix eh_os_contract.check` reports a unit with such a step and no implementation
  (`declaration-without-implementation`), as it does a unit with commands.

- **An event's old rows are read in its current shape** (plan DD, stage V1, #333): an `upcast` per version below
  `schema_version`, `upcast from: 1, rename: [reason: :demand_reason], default: [priority: "normal"]`. A row is read
  through the steps from its own version up, by every consumer and by a relay before it publishes. The log is never
  rewritten, and a renamed personal field opens under the name it was sealed with. A `default:` is written as the
  log stores a value. The compiler refuses a version without its step (`U1`), a step to a field the event will not
  have (`U2`), a step that renames onto or defaults what the log keeps by a field's name — the unit's identity, and
  every required, non-personal `:id`, date or timestamp it tags rows with — or gives personal data a default (`U3`),
  and a default that is not a value of its field (`U4`).

### Changed

- **Breaking:** an event above `schema_version: 1` needs an `upcast from:` each version below it, or the contract
  no longer compiles (`U1`). One whose fields kept their shape takes an empty step: `upcast from: 1`.

## [0.5.0] - 2026-10-16

### Added

- **The model's pages for the business owner** (plan DD, stage L4, #326): `mix eh_os_contract.pages --output
  docs/owner --audience owner` writes the same tree of pages with each declaration by its label, and without
  module names, versions, stored types, delivery, idempotency, correlation keys, field names and types and the
  graph documents. A field without a label is left out, and a promise is read by its rule. The pages have a
  marker of their own (`EhOsContract.Pages.marker/2`), so they go to a directory of their own. `Pages.render/3`
  takes `audience: :owner`.

- **`check` notes a stage or a value the owner would read by its name in the code** (plan DD, stage L4, #326):
  `owner-view-without-label`, a notice for each stage of a process module, each value of the domain and each
  member of a value's enum written as a bare atom with no label: what a business owner reads that may be
  written without one. The owner's pages and the graph's switch "Owner" both read the model this way.

- **A process's overlay says which stages runs entered out of order** (plan DD, stage O2, #319): under
  `observed.relations`, `out_of_order` lists each pair, from the later stage's node to the earlier one's, with
  how many runs, as the conformance report counts them (`EhOsContract.StageOrder`). `graph_overlay.v1` grows by
  an optional key; a reader that does not know it ignores it.

- **The report says when a deploy changed only the words** (plan DD, stage V5, #322): `Deployment.diff/2`
  carries `agreement_changed` and `words`, the declarations whose words moved, and the fourth question reads
  "Only the words changed since the previous deployment, not the agreement: 1 (event:visit_completed)." where the
  version stayed. `EhOsContract.Report.Sentence.change/2` writes it, for the text report and the dashboard.

### Changed

- **Breaking:** **Moves a verdict:** **a contract's version is what it allows, not its words** (plan DD, stage V5,
  #322). `version` and `digests` hash fields, commands, who may issue them, what they emit and refuse, rules,
  lifecycles, reactions and their delivery, and in a process module its stages, promises and deadline; labels,
  `source:`, scenarios' descriptions, `where:` prose and a domain's glossary are left out. They have a digest of
  their own, `text_digest` and `text_digests` in the model, under the same keys. The same holds for a domain and a
  process module. Relabelling an event is no new version any more: no event is stamped differently, no read model
  goes stale, and the deployment diff no longer names the declaration as changed. What a host meets once, at the
  first boot of this release:
  - every contract's, domain's and process module's version moves, with every declaration's digest, so the
    events already in the log count as "from earlier contract versions" and the diff names every declaration;
  - every read model and process manager is marked stale: a process manager is rebuilt at boot, a read model
    through its `reset/0`, and one without it stays stale;
  - the storage goes to version 4, which records the words' digest beside each deployment, so a change of the
    words alone is a deployment of its own. Add a migration calling `EhOsContract.Migrations.up(version: 4)`;
    the engine refuses to start on version 3.
- **Breaking:** **the context map holds the contracts to it** (plan DD, stage M1, #316). A reference from one
  context into another that runs against the relation between them does not compile any more:
  - from the upstream context of a directed relation into its downstream one, or across `separate_ways` (`X11`);
  - a read model, an effect or a process manager taking a sibling's event, or a boundary consulting one, across
    an `anticorruption_layer`, where only a policy takes it (`X12`);
  - consuming an event a sibling does not `publish` across an `open_host_service` or a `published_language`
    (`X13`).

  A consume or a field naming an entity or a unit against the relation was the `check` warning
  `relation-against-references`, which is gone; the rest `check` did not warn of. A host fixes the relation or
  the reference.
- **Breaking:** **a field typed with a domain value another context declares (`value …, context:`), directly or
  through another value's fields, is a reference between the two contexts**, so `X11`,
  `cross-bounded-context-reference-without-mapping` and `orphan-context-mapping` see it. A field of such a value
  used against the relation stops compiling.

## [0.4.0] - 2026-10-16

### Added

- **`graph.v1` changes only by addition** (plan DD, stage G1, #297): a key, a node kind or a relation type once in
  a document or an overlay keeps its name, type and meaning, so a reader on an older version — the EHOS Console
  reading applications on several — keeps working; a reader ignores what it does not know. A test holds both
  shipped schemas to a baseline, which only a breaking change moves (`EhOsContract.Graph.Document`).
- **A consumed event says which contract declares it** (plan DD, stage G1, #297): its node in a contract's
  `graph.v1` document carries `declared_in`, the sibling contract's id, beside `declared_as`, so a reader need not
  read it out of an id.
- **A contract's drift on the domain's overlay** (plan DD, stage G1, #297): each contract's node in a domain's
  overlay carries `untraversed`, its declared steps and lifecycle transitions never taken, and `undeclared`, the
  distinct moves its lifecycles do not allow that happened, as many as the lines the conformance report lists
  for them. The domain's overlay now reads every contract's steps and lifecycles, each once.
- **A unit's node in a contract's `graph.v1` document says it records only** (plan DD, stage C1, #304): a unit with
  events none of whose commands can be refused carries `"records_only": true`, the same fact its page from
  `mix eh_os_contract.pages` states; the key is absent otherwise, and the schema in `priv/schema/graph.v1.json`
  has it as optional. Moves no verdict.
- **A line logged while the engine works carries that work's correlation.** While it runs a command,
  records an event, or reacts to an event, a timer or a message, the Logger's metadata holds the
  work's correlation identifier as `correlation_id`, in lower case, and what was there before is
  back afterwards; one that is not a UUID's text sets nothing. A host names `:correlation_id` in its formatter's
  metadata to write it (#298).

- **The skills for writing contracts reach an application as a Claude Code plugin.** This repository is a
  marketplace, `eh-os-contract`, whose plugin of the same name, in `plugins/eh-os-contract/`, carries
  `module-boundary-check`, `contract-distillation`, `add-event`, `change-contract`, `write-decider` and
  `write-reaction`, each saying where its paths are in an application (under `deps/eh_os_contract/`).
  `docs/getting-started.md` says how an application enables it; it is released by its own tag,
  `eh-os-contract-plugin-vX.Y.Z`.
- **The core is where things are decided** (plan DD, stage L2, #272). `mix eh_os_contract.check` has two new
  rules for contracts of a context in a subdomain of `type: :core`: `core-command-never-refuses` (a notice for a
  command with empty `rejects:`, unless only a policy or a process manager issues it) and
  `core-unit-records-only` (a warning for a unit with events none of whose commands can be refused). A unit's
  page from `mix eh_os_contract.pages` says "Records only" when that holds. Moves no verdict; a host running the
  check with `--warnings-as-errors` may see the new warning on an unchanged contract.
- **A field can say which unit it identifies** (plan DD, stage L3, #286). In a contract, `{:id, name}` names
  a unit of one of the domain's contracts as it names an entity (a domain's own values and entities still
  name only entities): `field :visit_id, {:id, :visit}`, and a unit keyed by
  another's number types its identity, `identity visit_id: {:id, :visit}` or `identity [:period_id,
  company_id: {:id, :client}]`. The compiler between modules refuses a name that matches no entity and no
  unit, or more than one of them, and a `reads:` through a field that identifies a unit. The model keeps
  such a field as `type: :id, refers_to: name`, as for an entity. `mix eh_os_contract.check` counts a
  reference to another context's unit as one into that context, so the context-map rules read it; the
  pages link the field to the unit, and a unit's page lists the fields that refer to it. In a contract's
  `graph.v1` document a field's `refers_to` names the entity or the contract's own unit, and is left out for
  a sibling's unit. Moves no verdict; a contract that types a field this way gets a new version.
- **A domain's `graph.v1` document draws what one contract's cannot** (plan DD, stage L3, #286): a new
  relation type, `refers_to`, from a contract to a sibling whose units' numbers it keeps, one per pair, with
  the units' names in `units`. The schema in `priv/schema/graph.v1.json` lists it among a domain's relations,
  every one of which a document carries, empty or not. Moves no verdict.
- **A process module has a `graph.v1` document** (plan DD, stage P2e, #220): `EhOsContract.Graph.Document.process/1`
  gives one of kind `"process"` — the process with its correlation and deadline, its stages, the events they
  include with each one's stage, contract and whether it ends a run, those contracts and their contexts, the
  external systems those events rest on with their `depends_on` relations, as in the contract's document, its
  promises with the events that open, fulfil or settle each otherwise (`opens`, `fulfils`, `or_else`), and the
  actor `accountable_for` it when the domain declares that actor. An event keeps the id it has in its contract's
  document, so the two join. Its shape is the new `process_document` of `priv/schema/graph.v1.json`. Moves no verdict.
- **What the log says over a process module** (plan DD, stage P2e, #220): `EhOsContract.Graph.Overlay.process/2`
  puts its runs on the process, how often each event it includes happened on the event (0 for one that did not),
  and on each promise its verdicts — kept, by which route, broken, pending, suspended, and the runs judged — as
  `EhOsContract.Conformance.process/2` reports them; a promise not yet confirmed has none, as in the report. Its
  shape is the new `process_overlay` of `priv/schema/graph_overlay.v1.json`. Moves no verdict.
- **`mix eh_os_contract.graph --process <id>`** gives a process module's document, and with `--overlay` what the
  log says over it (plan DD, stage P2e, #220). It refuses an id no process module has, a contract's included, and
  `--process` beside `--contract` or `--domain`.
- **A domain's `graph.v1` document has its process modules** (plan DD, stage P2e, #220): a `process` node for each
  process module given, an `includes` relation from it to each given contract whose events it includes, and the
  actor `accountable_for` it when the domain declares that actor, as in the process's own document; the domain's
  overlay puts each one's runs on its node. The task gives them; see "Changed" for what a reader of the schema has
  to do. Moves no verdict.
- **Three functions behind the overlays are public** (plan DD, stage P2e, #220):
  `EhOsContract.Conformance.promise_verdicts/2` judges a process's confirmed promises as the report does,
  `EhOsContract.Paths.occurrences_by_type/2` counts events of the given types in one query, and
  `EhOsContract.Paths.runs_by_process/2` counts the runs of several process modules in one query.
- **Breaking:** **a process module has a page, a branch of the domain's tree and a place in the glossary** (plan
  DD, stage P2e, #220). A host that holds its pages to the model with `mix eh_os_contract.pages --check` runs
  `mix eh_os_contract.pages --output <dir>` once and commits the result: the check fails until then, since each
  process module has a new page and document, and the domain's page and the page of each contract whose events a
  process module includes change. `mix eh_os_contract.pages` writes `processes/<its id after the domain's name>.md` for each process
  module of the domain: what tells its runs apart, the actor accountable for it, its stages in order with each
  included event linked to its contract's page, the events that end a run, its promises and deadline (an
  unconfirmed one said to be left out of the report), the external systems its events rest on and its scenarios.
  The domain's page lists the process modules, and a contract's page those that include its events. Beside the
  pages, `graph/process/<id>.json` holds its `graph.v1` document; the task replaces and deletes one there as it
  does a contract's. `mix eh_os_contract.view` prints the process modules under the domain, each with its stages
  and the events each includes, and with `--details` what ends a run, its deadline and its promises; a path to one
  context leaves them out. `mix eh_os_contract.glossary` lists, under a term, a process module that includes the
  context's events and whose id, a stage, a promise or a `correlate` field is named with it. No existing page or
  path moves. Moves no verdict.

### Changed

- **Moves a verdict:** a command a process manager issues from an `on` naming one of its timers is a declared path
  from that timer (plan DD, stage C1, #304), as one the timer itself issues is. Before, the report counted neither
  its runs nor its absence, so a path the code takes could not be reported untraversed.
- **Breaking:** **A key names each field once** (plan DD, stage C1, #304). A process manager whose `correlate`
  names a field twice, `correlate: [:visit_id, :visit_id]`, no longer compiles (P4), nor a dynamic consistency
  boundary's `consults` whose `match:` does (A4); each message names the field, as a process module's (R2)
  already did. Name the field once. Moves no verdict.
- **Breaking:** **A policy or an effect reacts to at least one event** (plan DD, stage C1, #304). One declared
  with `handles: []` compiled and never ran, and dispatch still let such a policy issue what its `issues:`
  named; neither compiles now (P1). Name the events it reacts to, or remove it. Moves no verdict.
- **The report says what one run of a process module is** (plan DD, stage P2e, #220): "Runs in this period: 2, one
  per account_id." The sentences of a process module's runs and deployment are in `EhOsContract.Report.Sentence`,
  which the dashboard prints too. A process module's report carries what tells its runs apart, `correlate`, and
  the conformance wire carries it as `"correlate"`, a list of field names, a key a reader may ignore under the
  same schema. Moves no verdict.
- **Breaking:** a domain's `graph.v1` document carries a new node kind, `process`, and a new relation type,
  `includes` (plan DD, stage P2e, #220), which `priv/schema/graph.v1.json` lists among those every domain document
  carries, empty or not; its `oneOf` has a third document, a process module's, and the overlay schema a third
  overlay. A reader that holds a domain document to the schema shipped in 0.3.0 refuses the new keys, and the new
  schema refuses a document without them: take the schema with the engine. `Document.domain/2` and
  `Overlay.domain/3` take the domain's process modules in the same list as its contracts
  (`Registry.contracts() ++ Registry.processes()`); given contracts alone, the document has no process nodes.
  A contract's document is unchanged.

- **The docs and the plugin's skills teach a process as a module** (plan DD, stage P2i, #294). The examples of
  the README, `docs/introduction.md`, `docs/contract.md` and `docs/concepts/` write a run with
  `use EhOsContract.Process` (`stage … include:`, `ends_on`) and contracts without a `process`, stage groups or
  `terminal:`; `docs/concepts/process.md` says how a contract's own `process`, which is being removed, maps onto a
  module. The plugin `eh-os-contract` 0.2.0: `add-event`, `module-boundary-check`, `change-contract`,
  `write-reaction` and `contract-distillation` say the same. Nothing in the engine changed.
- **Breaking:** `{:id, name}` for a name that both an entity of the domain and a unit of one of its
  contracts have no longer compiles (plan DD, stage L3, #286); before, it meant the entity. Adding such a
  unit to any contract of the domain refuses every reference to the entity. Rename the unit or the entity.
- **Breaking:** a domain's `graph.v1` document carries the new relation type `refers_to` (plan DD, stage L3,
  #286), which `priv/schema/graph.v1.json` lists among the relations every document carries. A reader that
  holds a domain document to the schema shipped in 0.3.0 refuses the new key, and the new schema refuses a
  0.3.0 document without it: take the schema with the engine. A contract's document is unchanged.
- **Moves a verdict:** two rules of `mix eh_os_contract.check` read process modules (plan DD, stage P2h, #221).
  `backward-edge` warns of a policy or a process manager reacting to an event one stage of a process module
  includes and issuing a command whose events sit in an earlier stage of that module; it read a contract's stage
  groups, which are gone. `orphan-actor` counts an actor named as a process module's `accountable` as used; it
  counted only a contract's process, so such an actor was reported unused. `deadline-without-terminal-event` is
  removed: a process module's `deadline` does not compile without `ends_on` (R6).
- **The plugin `eh-os-contract` 0.3.0** (plan DD, stage P2h, #221): `change-contract` says that a process module's
  stages decide what `backward-edge` warns of, since a contract has none.

### Removed

- **Breaking:** a contract's `graph.v1` document no longer carries the kinds of a process (plan DD, stage P2e,
  #220): its `process`, `stage` and `promise` nodes and its `accountable_for`, `opens`, `fulfils` and `or_else`
  relations, empty since a contract declares no process, are gone from it and from the schema's
  `contract_document`. The optional keys nothing has written since then go from the schema too: an event's
  `stage`, `included` and `terminal` in a contract's document, and a contract node's `process` and `correlate`.
  A process's stages, promises and accountable actor are in its process module's document. A reader that holds a
  contract document to the schema of 0.3.0 refuses it for the missing kinds: take the schema with the engine.
  Moves no verdict.
- **Breaking:** a contract can no longer declare a process (plan DD, stage P2h, #221). The `process` block — with
  `correlate`, `accountable`, `stage`, `include`, `deadline` and `promise` —, a unit's `stage` groups and an
  event's `terminal:` no longer compile. Write the run as a process module, `use EhOsContract.Process`, with
  `stage … include: [{Contract, [:event]}]` and `ends_on` (`docs/concepts/process.md`): the block's label,
  `accountable`, `correlate`, promises and `deadline` move to the module, the events of each stage group and each
  `include` go into a stage's `include:` under the contract that declares them, and the `terminal:` events into
  `ends_on`. The refusals of the old form go with it: the rule that a contract declares a process now refuses only
  a contract that declares nothing (R1), the rule on a process's includes is gone (R4), and the rules on names,
  durations, correlation fields, actors and siblings lose what they refused of a contract's process (N1, R6, F4,
  F8, F9, X2, X6, X7); what they refuse of a process module is unchanged. No contract's version or digest moves:
  the digest keeps an empty process group and every event's `stage: nil, terminal: false`.
- **Breaking:** the model of a contract has no `process` key, and its events no `stage` and `terminal` (plan DD,
  stage P2h, #221), in `EhOsContract.Model.to_data/1` and the `/model` documents. `EhOsContract.Model.process/1`
  is `nil` and `EhOsContract.Model.process_events/1` is `[]` for a contract; for a process module they answer as
  before, and an entry of `process_events/1` no longer has `included`, which was always `true` for one. The
  conformance report keeps its `processes` key, `[]` for a contract: a reader of it needs no change. A contract's
  `graph.v1` document lost its process kinds afterwards (#220, above).
- **Breaking:** the storage is at version 3 (plan DD, stage P2h, #221): `eh_os_contract_events` and
  `eh_os_contract_commands` lose `process` and `instance_id`, which filed a row under the process its contract
  declared. An event's runs are the rows of `eh_os_contract_event_runs`, filed under the process modules that
  include it, and a command keeps no run. **A host has to act:** add a migration calling
  `EhOsContract.Migrations.up(version: 3)` (and `down(version: 3)`, which gives the columns back empty). The
  engine now also **refuses to start on storage newer than its own version**, since a node of an older release
  would write the removed columns on every append. **A rolling deploy that migrates first breaks:** a node of
  0.3.0 does not refuse newer storage, and once the migration runs every command it handles fails on a missing
  column. Stop the nodes of the old release before migrating. Dropping the columns takes a short exclusive lock
  on both tables, so migrate when nothing holds a long transaction on them.

  ```elixir
  defmodule MyApp.Repo.Migrations.UpgradeEhOsContractToV3 do
    use Ecto.Migration

    def up, do: EhOsContract.Migrations.up(version: 3)
    def down, do: EhOsContract.Migrations.down(version: 3)
  end
  ```

## [0.3.0] - 2026-10-11

The move to the second contract DSL (`docs/adr/contract-v2.md`), from E1 to the cut, E11.
**The first DSL is gone**: a contract written with `event`, `payload:`, `trace` and `EhOsContract.Handler`
no longer compiles, and nothing of it is migrated — there was no consumer to migrate. What 0.3.0 is, and
how to write a domain and a contract for it, is in `README.md` and `docs/contract.md`; every key of both
DSLs is in `docs/dsl/`. Until E11, E1–E5 moved no verdict of a first-DSL contract — `mix
eh_os_contract.report` and `graph --overlay --mermaid` gave byte-identical output before and after each —
and from E6 the second DSL ran beside it. The entries below each name their stage.

### Added

- **A contract and a domain as `graph.v1` documents** (plan E13, #217). `EhOsContract.Graph.Document.contract/1`
  gives a contract's document and `domain/2` a domain's: a graph of facts, every declaration a relation can end at
  as a node grouped by kind and every link between them as a relation grouped by type, and a contract's scenarios
  grouped by the kind of their target, each with the relations it exercises (`covers`). Each node carries what a
  panel shows of it: a field's type, whether it is required, its default, whose personal data it is and what keeps
  its value about a person (`kept`), the subject, value or entity it names, the system that issues it; a
  command's capability, scope, what its decision reads (`reads`) and the one person who may issue it
  (`actor_is`); delivery and idempotency, windows, terminal and final events, a unit's state, a query's
  parameters, an actor's role, an external's operations, a context's terms with each term's word in code
  (`code`, in the domain's `code_language`). A unit's scenario says the person issuing its command (`as`), the
  rows the command reads (`given_entities`) and when each given happened (`at`). Every id is stable and opaque,
  scoped to the contract's `id:` or the domain's module. A document holds no pictures and nothing from the log;
  its examples and defaults are redacted as `EhOsContract.Model.to_data/1` redacts them; it says `"schema":
  "eh_os_contract.graph.v1"` and carries a `"digest"`, and `Document.encode/2` writes it with every object's keys
  in order, so the same declarations give the same bytes and the digest is a sound `ETag`. Its JSON Schema ships
  in `priv/schema/graph.v1.json` (`Document.schema_path/0`). Moves no verdict.
- **What the log says over a graph document, as a document of its own** (plan E13, #217).
  `EhOsContract.Graph.Overlay.contract/2` and `domain/3` give `eh_os_contract.graph_overlay.v1` (its schema in
  `priv/schema/graph_overlay.v1.json`): the period, the version and the digest of the document it joins, and maps
  from that document's ids to the numbers the conformance report computes — an event's occurrences, a process's
  runs, how often a step was taken, whether the report lists it as waiting or failing (`waits`, `fails`) and
  whether it counts it as never taken or not yet, a transition's count, the events between two contracts, and a
  move a lifecycle does not allow. A process manager that issues one command on one event both as the event
  starts a run and during it gets no numbers on those two relations, since the log does not record the phase.
  `EhOsContract.Conformance.steps/2` gives every step with the report's reading of it. Moves no verdict.
- **`mix eh_os_contract.graph` gives the graph documents** (plan E13, #217): `--contract <id>` a contract's,
  `--domain <name>` a domain's (left out where the application has one), with `--overlay [--since]` what the
  log says over it, as JSON, `--output` to a file. `eh_os_contract_web` serves the same documents over HTTP. The
  pictures it drew are under "Removed" below. Moves no verdict.
- **The glossary is joined to the code** (plan DD, stage L1, #269). `use EhOsContract.Domain` takes
  `code_language:`, English by default, and a term's word in code is its translation into it.
  `mix eh_os_contract.glossary` lists, under each term, the declarations named with that word, and
  `mix eh_os_contract.check` has two new rules: `word-without-term` (a notice per context, ranking the words of
  its units', read models' and fields' names that no term covers) and `term-of-another-context` (a warning for
  a name that says another context's term and none of its own). `code_language:` is in the domain's model
  only when it is not `:en`, and in no digest, so it moves no version. Moves no verdict.
- **A unit's code is tested on legal histories of its contract** (plan DD, stage PC2, #266).
  `use EhOsContract.PropertyCase, contract: C, max_runs: 50` writes, for every aggregate with an implementation,
  a property that `evolve/2` folds every legal history (events with `__meta__`, personal fields sometimes
  erased), one per command that its decision returns only what dispatch would append, or a rejection it
  declares, in a status its `from:` admits, and, when the implementation defines `holds?(invariant, state)`, one
  that every invariant holds after each decided command. `fold/4`, `decide/5`, `walk/4`, `decisions/3` and
  `walks/2` are public. It compiles only where StreamData is. Moves no verdict.
- **A contract produces valid examples of its data** (plan DD, stage PC1, #264). `EhOsContract.Generators` gives
  StreamData generators of a contract's commands (`command/3`) and events (`event/3`), of a domain entity's row
  (`entity_row/3`), and of a unit's history in an order its lifecycle allows (`history/3`), every value within what
  the engine stores and a domain value with invariants drawn from its `satisfied_by:` examples; `fields:`
  fixes or narrows a field. The module compiles only where StreamData is, `{:stream_data, "~> 1.1"}`, an optional
  dependency of the package. Moves no verdict.
- **The report counts the runs whose stages happened out of order — can move a verdict** (plan DD, stage O1,
  #260, agreed with EHOS). Each process section of
  `EhOsContract.Conformance.report/2` has `out_of_order: %{runs: n, pairs: [%{earlier:, later:, runs:,
  earlier_label:, later_label:}]}` (`EhOsContract.StageOrder`): the runs that entered a later stage before an
  earlier one they also entered, by position in the log, a stage entered by its first event, a run in the
  period by its first event and judged on all of them. On the wire it is a new key of v3, and the text report
  prints "Stages out of order in n runs" with a line per pair, only when there is one. It never names a run. The
  dashboard does not show it yet.
- **A process module's report is on the conformance wire** (plan DD, stage P2w, #259, agreed with
  EHOS). `EhOsContract.Conformance.as_data/2` no longer refuses a process module: its report
  keeps the schema `eh_os_contract.conformance.v3` and has `"process"`, its id, where a contract's has
  `"contract"`; a report has exactly one of the two. `EhOsContract.Conformance.Wire` states the rule every reader may
  rely on: an unknown key is ignored, and a key an older reader must not ignore comes with a new schema name. Moves
  no verdict.
- **A process's promise can be shown and tested with a scenario** (plan DD, stage S2, #251). A process module
  takes `scenario "…", verdict: :satisfied, via: :eventually do … end`, with `given :event, %{…}, at:
  "2026-09-07T09:00:00Z"`, `outage :external, at: "…"` and the trigger `promise :name, at: "…"`, the moment the
  promise is judged. `use EhOsContract.ScenarioCase, process: MyApp.Processes.Visit` writes a test per scenario
  (`EhOsContract.ScenarioCase.judge/2`): it builds each given as the event its contract declares, files it into
  its run and judges the promise through `EhOsContract.Trace.judge/3`, without a database. New compile refusals:
  the scenario's shape (S11), and S1, S2, S3, X4 and X9 extended to a process module's scenario. Any scenario,
  a contract's too, may date a given with `at:`; one without it keeps its moment, a minute after the given
  before it, and an `at:` earlier than the given before it is refused (S3). A process module with scenarios gets
  a `scenarios` key in its model and a new version; one without them, and every contract, keeps its version.
  Moves no verdict.

- **A command can name the person who must issue it** (plan DD, stage A1, #247). Inside a command, `actor_is
  :specialist_id, or_rejects: :invariant` says a credential's subject must be the one that field of the unit's
  state holds (a new compile refusal, A9, for the unit's identity, which the caller fills, a field outside the
  state, not an `:id` or personal, an invariant outside `rejects:`, a command that `creates:` or has no `by:`;
  and X2, for a `by:` without a person). Dispatch checks it after folding the state and
  before the decision, and refuses anyone else on the invariant with a `rejected` row, which the report counts as
  any rejection; a `:system` actor and a reaction pass. A scenario names the person with `as "…"` beside its
  `actor`, and must when the actor is a person (S7, X2). Nothing changes for a contract that does not declare it.

- **A command can read an entity the application keeps before it is decided** (plan DD, stage T2a, #240). A
  command declares `reads: [service: :service_id]`, naming a required field of its own typed `{:id, entity}`
  and issued only by an actor, never a policy or a process manager (a new compile refusal, A8); its decision
  takes a third argument, the rows read by name. The host gives them through a new behaviour,
  `EhOsContract.Entities` (`config :eh_os_contract, entities: MyApp.Entities`, `fetch(actor, domain, entity,
  id)`), asked once per command before its transaction, as the actor who issued it; a row not found refuses the
  command with `{:invalid, [{field, :unknown}]}`, a 422, and a row that does not fit its entity, or is another
  one than asked for, raises `EhOsContract.Entities.UnfitRowError`. What was read is kept in a new column,
  `inputs`, of `eh_os_contract_commands`. A scenario gives a row with `given_entity` (S12, and X9 for its
  fields). A value invariant may no longer be named `:unknown` (D9). **A host has to act:** add a migration
  calling `EhOsContract.Migrations.up(version: 2)` (and `down(version: 2)`), since the storage is now at
  version 2 and **the engine no longer starts on storage missing or older** than the version it needs; and
  configure `entities:` once a contract declares `reads:`, or the node does not start.

- **The report, the deployment record and the check show a process module** (plan DD, stage P2d, #213).
  `EhOsContract.Registry` finds process modules beside contracts (`processes/0`, `process/1` by id).
  `EhOsContract.Conformance.report/2` of a process module gives the process section a contract's process gets
  — its runs, its duration against `deadline`, its promises' verdicts and its confirmed declarations — with its
  deployment, and `mix eh_os_contract.report` prints process modules after the contracts.
  `EhOsContract.Deployment.record!/1` writes a row per process module, under `"process:<id>"`, with its
  version and the digests of its promises, so a promise's verdict is read against the version it was made
  under. `mix eh_os_contract.check` counts an event a process module includes as read
  (`event-without-consumer`) and applies `process-without-accountable`, `unverified-declaration` and
  `promise-without-within` to process modules. `EhOsContract.Model.process/1`, `process_events/1` and
  `declaring/2` answer for a process module. The dashboard does not list process modules yet, and until
  P2w (above) `Conformance.as_data/2` refused one. No verdict of a contract
  moves. One correction for contracts too: the deployment the report shows for a version is the row recorded
  last, so after the wiring changes under the same version the report shows the new wiring and its date, where
  it showed the first row's, and no "since the previous version" line for a wiring-only change.
- **A process module is checked against its domain and its contracts, and gets runs** (plan DD, stage P2c,
  #210). The rules between modules refuse a process module whose `domain:` is not a compiled domain (X1), whose
  `id:` is outside the domain's `name:` (D11), whose `accountable` is no actor of the domain (X2), whose
  `include:` names no compiled contract of the domain or an event that contract does not declare itself (X5),
  whose `correlate` field an included event lacks, makes optional or personal, or types as no identifier or
  another one (X6), and whose `id:` another process of the system has (X7). Dispatch files each event a
  process module includes into a row of `eh_os_contract_event_runs` under the module's `id:`, keyed by its
  `correlate`, beside the event's home run; a contract's own runs are unchanged. No reader shows those runs
  yet, so no verdict moves.
- **A process can be written as a module of its own** (plan DD, stage P2b, #205): `use EhOsContract.Process`,
  with `id:`, `label:` and `domain:`, `correlate`, stages that `include:` the events of named contracts,
  `ends_on`, promises and a `deadline`. It compiles to a model of kind `:process` that
  `EhOsContract.Model.fetch/1` returns, and refuses what one module can see is wrong under the contract's codes
  (D11, N1, R2, F9, R3, R5, R6), a `deadline` without `ends_on` among them. Nothing at run time reads it yet,
  so no verdict moves and nothing has to be done. The DSL reference is `docs/dsl/process-dsl.md`, and the
  formatter's exported `locals_without_parens` covers it.
- **The configuration is declared in one schema and checked when the engine starts**
  (#203). `EhOsContract.Config` lists every key of `config :eh_os_contract`, its type,
  default and meaning; an unknown key, a value of the wrong shape or a missing
  `applications:` or `repo:` stops the engine with a message naming the key, never the
  value. `docs/configuration.md` is generated from it. Moves no verdict.
- **A contract may describe no process** (plan DD, stage P1c, #190). R1 refuses a second `process`, and in a
  contract without one, a unit's `stage` group and a `terminal:` event, which only a run has. Such a contract
  dispatches with no run indexed, runs its scenarios, and gets a report with its steps, lifecycles and
  scenarios and no process section. A contract that declares nothing at all is still refused. No verdict of a
  contract that compiled before moves, and nothing has to be done. Removing a process from an existing contract
  is another matter: it changes the contract's version and ends its runs (P1d).
- **The conformance report finds one contract's commands through an index** (#185):
  `eh_os_contract_commands (contract, outcome, recorded_at)`, added to V01 in place, as V01 is until 0.3.0 is
  released. Before it, every query of `Coverage` and `Paths` on that table read all of it; reads bounded by
  `recorded_at` and of failed commands gain the most. No verdict moves, and nothing has to be done: a database
  created from an earlier V01 is recorded at version 1, so `up/0` leaves it without the index and only slower. The
  reset of the engine's schema that naming contracts by their `id:` asks for (plan DD, stage ID4, #178) creates it;
  without a reset, `CREATE INDEX CONCURRENTLY IF NOT EXISTS
  eh_os_contract_commands_contract_outcome_recorded_at_index ON eh_os_contract_commands (contract, outcome,
  recorded_at)`, outside a transaction, builds it without stopping dispatch.
- **A warning at start-up when the event log files events under a contract name no contract has as its id**
  (#179). The engine names them and goes on. It catches a log written before rows named a contract by its id (plan
  DD, ID4, #178) and not reset: its event types are still declared, so the warning of #175 says nothing, while the
  conformance report and the commands' counts skip those events. The names are read one index step each. Ids are
  matched whole; the library's own name (`eh_os_contract`, which an erasure is filed under) is known.
- **A warning at start-up when the event log holds types no contract declares** (#175). The engine names them and
  goes on. It catches a log written before event types became `"<contract id>.<event>"` (plan DD, ID3) and not reset,
  which a boundary, a subscription, a read model and the report would otherwise skip without a word; it also names the
  history of a contract removed on purpose. The log's distinct types are read one index step each, so a long log
  costs no more than a short one with as many types.
- **A contract can name itself: `use EhOsContract.Contract, …, id: "lending.circulation"`** (plan DD, stage ID1). The
  domain's `name:`, then dotted snake_case segments, none of them a version, at most 100 bytes (**D11**, at compile
  time); under the domain's own namespace (D11, L3) and unique in the application (**X7**). Optional for now, in the
  model as `:id` only where given, and outside the contract's version and its declarations' digests, so no deployment
  counts it as a change and no verdict moves. The exported model (`EhOsContract.Model.to_data/1`) carries it as
  `"id"`, so that document's own `"digest"` does change when an `id:` is added. Later stages make it
  required and the prefix of the contract's event types.
- **`mix eh_os_contract.check` warns of a lifecycle transition no scenario takes**
  (`transition-without-scenario`, plan DD stage S4). A transition is taken by a scenario of a command whose `given` leaves the
  unit in the transition's `from` status and which expects its event, the graph read as dispatch reads it; a
  transition from several statuses needs a scenario from each, and one on an event no command of the unit
  emits (recorded only), or from a status no such command's `from:` admits, is left out. A new warning only: no verdict moves, but a host running
  `check --warnings-as-errors` with such a transition turns red until it adds the scenario.
- **T1: a field the host gives, not the caller.** `field :late_fee, :money, supplied_by: :host`, on a
  command's field or a recorded event's (**F10** refuses it anywhere else, and on a command's `scope` field).
  Through `EhOsContract.call/3` — and `EhOsContract.Plug` — a request that sends it at all, even as `null`, is
  refused by name, `{:invalid, [late_fee: :supplied]}` (422 `{"invalid": {"late_fee": "supplied"}}`). Once
  the caller is authorized and what it sent — its fields, its idempotency key — is found sound, the new behaviour
  `EhOsContract.Supplier` gives the value, one call per command with the fields the request gave, its answer held
  to exactly the fields asked for, their types and invariants. Its `{:error, reason}` refuses the request with
  `{:not_supplied, reason}` (503 `{"error": "not_supplied"}`, in the OpenAPI document of such a command only), and
  nothing is written; a retry of a request already accepted under its key gets its receipt without asking.
  `dispatch/3` and `record/3` from the application's own code are not asked. The OpenAPI document leaves the field
  out of the request body. **A host that declares such a field configures `config :eh_os_contract, supplier:
  MySupplier`, a module exporting `supply/2`: the engine does not start without one** (the Mix tasks that only read
  contracts do not ask). A contract without the option keeps its version.

- **W3: a promise can be judged without a log.** `EhOsContract.Trace.trace/2` reads what a promise is judged on
  from the contract — the stored types of its events, its window, and the item's identity for a promise made per
  item inside a run — and `EhOsContract.Trace.judge/3` gives the verdicts for events handed to it, at the moment it
  is given (`now:`, required) and with the outages it is given (`outages:`). It reads neither the log nor the
  clock. `Trace.evaluate/3` is now the two over the log's rows. The split itself moves no verdict, and a log
  written under one identity reports byte for byte as before; the one verdict W3 does move, on a log whose rows
  predate a unit's identity growing, is under "Fixed" below.

- **LC4b (#99): an aggregate's lifecycle as a diagram.** `EhOsContract.Graph.lifecycle_to_mermaid/3` and
  `mix eh_os_contract.graph --contract M --lifecycle NAME` draw where an aggregate starts, its statuses and ends,
  and the transitions named by their events; with `overlay: true` / `--overlay` each arrow carries the report's
  count, `not yet` or `never`, and a move the lifecycle does not allow is a dotted arrow.
  `EhOsContract.Conformance.lifecycles/2` gives the report's `lifecycles` alone. The dashboard draws it beside
  its unit, and the contract screen has the lifecycle's section in the report's sentences. A double quote in
  any diagram's label is now Mermaid's `#quot;`, drawn as the quote the client wrote, not an apostrophe.
- **LC4a (#99): `T4` lets a command be issued where its decision only refuses.** A status in `from:` that
  none of the command's events can leave is no longer refused when `rejects:` names a rule besides
  `or_rejects:`: `from:` says where the decision runs, not where it accepts, and a decision may refuse there on
  a rule finer than the status (an item put up for sale but never handed out). Without such a rule it is still refused, and
  so is an emitted event that no status in `from:` lets out.
- **LC3 (#99): the report asks the first two questions of a lifecycle.** For each aggregate that
  declares one, `EhOsContract.Conformance` reports under `lifecycles` how often each declared transition was
  taken in the period, which were never taken (none when no aggregate had an event) and which are only not
  taken yet (`pending`: an aggregate that has not ended still stands where it can take them), and which events the
  lifecycle does not allow where the aggregate stood happened anyway — history from before the declaration,
  a recorded event that did not fit, an event after the end. The status is walked over the whole stream of
  each aggregate with an event in the period, streamed a stream at a time; only the period's events are
  counted. The text report has a `LIFECYCLE` section; on the wire
  the key is added to `eh_os_contract.conformance.v2`, and the start of an aggregate is `null`.
- **LC2 (#99): the engine keeps an aggregate's status.** For an aggregate with a `lifecycle`, dispatch
  and `ScenarioCase` compute the status from the names of the stream's events and put it into the state as
  `status` (before each event `evolve/2` folds, and after the last). **A command outside its `from:` is
  refused on its `or_rejects:` before the decision** — a `rejected` row, as a decision's own refusal — and
  an event the decision emits that the graph does not allow raises, with nothing appended. A recorded event
  is never refused for not fitting. `T1` refuses a state or identity field named `:status` beside a
  lifecycle. A contract without a lifecycle dispatches as before.
- **LC1 (#99): an aggregate's lifecycle, declared.** An aggregate may declare `lifecycle do status …;
  initial :status, on: :event; transition from, :event, to end`, and a command `from:` statuses with
  `or_rejects:` an invariant. `T1`–`T4` refuse a lifecycle that does not hold together: an unknown status or
  event, a status no `initial` reaches, a terminal status left or a non-terminal one with no way out, a
  `from:` an event of the command can leave from none of its statuses, a command that `creates:` the aggregate and emits no initial
  event. `from:` and `or_rejects:` are words of an aggregate's command only. A unit's model has `lifecycle`
  and a command's `from` and `or_rejects` only where declared, so no version moves until one is; the exported
  model carries them.
- **EP5b: what an actor answers for, and the words a relation pairs.** An actor may name its
  `responsibility`s (named prose, shown on the domain's page). **A relation's `terms` are pairs**, `terms:
  [{"Member", "Member"}]` — the word of the first end (upstream, or the first of `between:`) and of the
  second; a flat list of strings no longer compiles. D5 refuses a word of a context end that its glossary does
  not define, and the glossary shows, under a term, what the other end calls it. Pairs are allowed in a
  symmetric relation too, where ESDM has none. Moves the version of a domain whose relation has `terms`; an
  actor without responsibilities hashes as before. **In the exported model** (`eh_os_contract.model.v1`) a
  relation's `terms` is now a list of two-element lists of strings, no longer a list of strings.
- **EP5a: what an external system does.** An `external` may declare `operation`s, ESDM's `capabilities`
  (named otherwise, since a capability here is what EHOS grants an actor): `operation :submit_report,
  "…", source: "X-01"`. Once it does, every effect's `calls:` to it names one, `calls: {:p1,
  :submit_report}` (`X4`); `check` warns of an operation no effect calls (`operation-never-called`). The
  effect's model keeps `calls` as the systems and adds `operations` only where named, and an external
  without operations hashes as before, so no version moves until one is declared. The effect's `@doc`,
  its page and the domain's page show them.
- **EP4: a process manager's state in a scenario.** A process manager's scenario may say `state %{…}`, the
  fields its run holds after the trigger; `ScenarioCase` folds the delivered event after the reaction, as the
  engine does (a timer folds none), compares the fields named, and fails a step the engine would not take — a
  given before the run starts, a trigger after it ends. **Any** process manager's scenario whose events
  name two values of a correlation field now fails: the engine keeps two runs, and the runner had folded them
  into one state. S3 and S6 refuse a state naming no field of the run or
  the correlation, said twice, or said of anything but a process manager. Kept in the model only where said,
  and redacted in the export by the run's fields, so no other version moves.
- **EP3: a generated behaviour documents what the contract says.** Each callback's `@doc` gives its
  declaration's label and source, the events it may emit or the commands it may issue, the rules that hold
  there — each with the scenario that refuses on it or illustrates it, or marked prose alone — and the
  scenarios it runs; a consumed event says where it comes from. Each behaviour's `@moduledoc` adds the
  declaration's label, source and rules (`EhOsContract.Contract.Doc`). `b <Behaviour>.<callback>` in IEx
  prints it. No model, digest or version changes.
- **EP2: a reaction's rules, and the scenario that illustrates them.** `constraint` in a `policy`, an
  `effect` and a `process_manager`, and `invariant` in a `process_manager`, as a command and a query name
  theirs. A scenario names the rules of its target it shows in `illustrates:`; one its target does not have
  fails the compile (S10), and so does any on a command's scenario, which shows its rules with `rejected`. A
  process manager's constraints and invariants share one namespace (N1). `mix eh_os_contract.check` warns
  `prose-without-scenario` of a constraint of a policy, a process manager or a query, or an invariant of a
  process manager, that no scenario illustrates; an effect's constraint is prose alone, since no scenario
  runs an effect. `mix eh_os_contract.pages` lists the rules and what each scenario illustrates. A
  declaration or scenario without them keeps its digest.
- **EP1: `source:` on every declaration** a workshop names — a policy, an effect, a process manager and its
  timers, a read model, a query and the process in a contract; an actor, a subject, a value, an external and a
  relation in a domain — where it comes from in the material. `mix eh_os_contract.pages` shows it. A
  declaration without it keeps its digest; setting or changing one moves the declaration's digest and the
  version, as a label does.
- **E12d: `EhOsContract.call/3`, the one way in for data from outside.** A command, a recording or a query
  by its capability's name (`{:command, "lending.pay_late_fee"}`), with the data as a caller sent it and a
  credential's actor: it asks the `EhOsContract.Authorizer` before it says what is wrong with what was sent,
  then goes through `dispatch/3`, `record/3` or `query/3`. `EhOsContract.Plug` is now one door onto it, with
  the same statuses and bodies as before; `EhOsContract.Dispatcher.route/3` names the contract and the
  declaration a capability names, for a door that needs the declaration (a form's fields).
  `Dispatcher.permit_undecoded/5`, undocumented, is gone. One answer changes: an `x-correlation-id` of sixteen
  bytes that are not a UUID's text, which `Ecto.UUID.cast/1` took as a raw UUID and the log then refused with a
  500, is a 400 `correlation_id_is_not_a_uuid` like any other.
- **E12c: another application's published event arrives in an inbox (D12).** For every `consumes
  "<name>"` a policy handles, the engine starts a durable consumer on the configured `EhOsContract.Bus`,
  `"<contract>:inbox:<name>"`, before any relay, through `EhOsContract.Inbox.Keeper`: a consumer whose transport refuses it, at boot or later, is logged and
  started again five seconds later, and stops neither the boot nor any runner; one that stops after running
  is started again at once. **For a transport adapter:** a consumer's start returns quickly, subscribed or
  failed, since the boot waits for it; its state and exit reasons hold no credentials; and a consumer name
  the transport cannot take is mapped one to one. Each delivery is decoded into the contract's received
  struct and, in one transaction, written to `eh_os_contract_inbox` and handed to the policies, whose
  commands carry the message's correlation and name the inbox row as their cause; it is acknowledged after
  the commit. A row exists per message key, so a redelivery, or the same fact published again under a new
  id, reacts once: the relay gives a message the SHA-256 of its name and its `idempotent_on:` values, each
  framed by its length, as its key, or its id when the publication declares none. A message that does not fit what
  the contract consumes, or whose policy raises, is not acknowledged and comes again. With no `bus:`
  configured the boot logs a warning for each inbox. `Model.capabilities/1` has one more capability per
  consumed name a policy handles, `<name>.subscribe`, without the name's version, of kind `:subscribe` and
  with no roles: the application's, granted by EHOS, never a person's. Who may publish under a name is the
  transport's to enforce: the inbox takes what its consumer is delivered.
- **E12b: a `publish` leaves the application through its relay.** `EhOsContract.Relay` is one ordered
  subscription per `publish`, `"<contract>:relay:<name>"` in `eh_os_contract_subscriptions` and in
  `mix eh_os_contract.subscriptions`, which reads the events it publishes and hands each to the configured
  `EhOsContract.Bus` as a message of the declared `fields` only, with the id `<event id>/<versioned name>`
  and the event's correlation. It advances only once the bus holds the batch; an `{:error, _}` from the bus
  counts no attempt, a raise fails the event as a policy's does. Like a policy it starts at the head of the
  log, so a `publish` deployed onto history publishes none of it; a reset publishes the log again. With no
  `bus:` configured the relay waits at its position, and the boot logs a warning for each one. A host that
  declares a `publish` gets the row and the warning on its next boot. **For a transport adapter:**
  `Bus.publish/2` runs inside the relay's database transaction and has to return within seconds, well under
  the repo's timeout, and answers `{:error, _}` only for what retrying fixes; anything else raises, so the
  relay stops at that event.
- **E12a: `EhOsContract.Bus`, the seam between two applications (D11, D12).** A behaviour with two
  callbacks: `publish/2` hands a batch of `EhOsContract.Bus.Message`s to a transport, and `consumer/2`
  gives the child that runs a durable consumer, whose handler answers `:ack` or `:nack`. It promises
  at-least-once delivery and no order, and requires no deduplication: the inbox (E12c) drops a second
  delivery by the message's key. `EhOsContract.Bus.Local` runs it inside one BEAM, for tests and
  development, and sends the payload through JSON so a term no transport could carry fails in a test.
  `EhOsContract.Bus.Suite` holds the tests every adapter has to pass, for the transport adapters EHOS
  writes. Nothing publishes or consumes through it yet: the relay is E12b. Configured with
  `config :eh_os_contract, bus: {Adapter, opts}`; nothing is configured by default.
- **D11: an application's namespace may hold a dash (#50).** The first segment of a `publish as:` or a
  `consumes "<name>"` may now contain `-`, not at either end, so a domain named as EHOS names an
  application, `name: :"my-shop"`, publishes `"my-shop.entry.recorded.v1"`. Before, no name could satisfy
  both D11 checks for such a domain: the pattern refused the dash, and the namespace refused
  `"my_shop."`. The other segments stay snake_case, and a namespace with an underscore stays valid.
- **E10: `EhOsContract.OpenAPI` projects the v2 model's human command and query capabilities as OpenAPI
  3.1.2.** Paths match `EhOsContract.Plug`, field and read-model schemas share AsyncAPI's JSON Schema
  projection, scoped operations name their dimension, and commands only application code may issue stay
  absent. List query parameters use repeated `form` keys and structured values use `deepObject`, matching
  what the Plug decodes; a crypto-shredded personal field in a query row is nullable while its key remains
  required. Each per-contract document and the v2 index carry an injective document digest, deliberately
  separate from the historical contract-version encoding.

- **E10: `EhOsContract.AsyncAPI` projects v2 `publish` boundaries as AsyncAPI 3.0.** Each publication is one
  addressed channel, one JSON Schema message carrying only its selected non-personal fields, and one `send`
  operation. The exact versioned publication name is its component key, so two local names cannot collapse
  under case conversion and overwrite one another. Internal events are absent. The index now lists v2
  contracts; direct v1 document generation stays available only until the E11 cut.

- **E9c: a field typed by a domain value of `:id` is an identifier.** `value :period, :id` with an invariant
  keeps the value's check at dispatch, and the field is now also a tag, so a consistency boundary can `match:`
  on it, and X6 compares it with a plain `:id` on the other side as the same type. `EhOsContract.Key.tag_field?/2`
  takes the domain's values; without them, at compile time, only the built-in type counts. Events appended
  before carry no tag for such a field.

- **EG2: a domain's context map and its system.** `EhOsContract.Graph.context_map_to_mermaid/1` draws the
  subdomains as groups of their contexts, the domain's externals, and the relations between them — a directed
  one from upstream to downstream, either end of which may be an external, a symmetric one without an
  arrowhead, `separate_ways` dashed. `EhOsContract.Graph.system_to_mermaid/3` draws a domain's v2 contracts in
  their contexts, what one consumes from another as an arrow carrying the events' names, and a publication as a
  node its publisher and a consumer of its name meet on; `overlay: true` puts a process's runs on its contract
  and, on each edge, how many consumed events the log holds and what waits or fails at the consumer. No verdict
  moves. `mix eh_os_contract.graph --map NAME` and `--system NAME [--overlay]` draw them; the domain's page from
  `mix eh_os_contract.pages` carries its map, and the dashboard's graph screen draws each domain's map, and its
  system with the log, above the per-process panels. `EhOsContract.Graph.bounded/2` narrows a query over events to a period,
  for the graphs' own queries (`EhOsContract.Paths` and `EhOsContract.Trace` keep their copies, which bound the
  same way).

- **EG1: a v2 contract's full graph and one unit of it.** `EhOsContract.Graph.contract_to_mermaid/2` draws the
  steps as before, and around them each unit's commands and events as a group, the actors issuing commands,
  recording events and asking queries, the read models with what they project and the queries over them, and
  the domain's externals the contract touches (an effect's `calls`, an event's `depends_on`, a system actor's
  `backed_by`, a field an external issues, directly or as an entity's identifier). No verdict moves: the counts
  on the overlay are the steps' as they were, and nothing new carries a count.
  `EhOsContract.Graph.unit_to_mermaid/2` draws one unit: its state as a card of fields, its commands and events,
  what builds its state (an aggregate's own events, a DCB's consulted ones), its invariants off the commands
  they may refuse, and how many scenarios pin each path. `mix eh_os_contract.graph --contract MODULE [--overlay]
  [--unit NAME]` draws either; `--process NAME --overlay` draws a v2 process's full graph. The unit's page from
  `mix eh_os_contract.pages` carries its diagram as a Mermaid block, and the dashboard's graph screen draws a v2
  process's full graph with the log.

- **EL3: `mix eh_os_contract.pages --output <dir>`** (ESDM's `documentation`): the domain and its v2 contracts
  as Markdown, a page per element — the domain with its tree, each context with its glossary and relations,
  each value and entity, each contract with its process, and each unit, command, event, reaction, read model,
  query and domain service — linked to each other by relative links (`EhOsContract.Pages.render/2`). Each page
  starts with a marker line naming its domain: a marked page of the domain the model no longer has is deleted,
  and a page is never written over a file without the marker or through a link — the task then writes nothing
  and names what is in the way. `--check` writes nothing and names every page that is missing, differs, is left
  over or is in the way.
- **EL2b: a value's invariants, checked.** `value :money, :integer do invariant :not_negative, "…",
  violated_by: [-1], satisfied_by: [0, 15_000] end` (D9). The domain generates `D.Values.Money`, one callback
  per invariant; `use D, value: :money` binds the module defining them (I1, I2). Dispatch holds every value of
  the type to them: a command, a recorded event and a query's parameters are refused,
  `{:invalid, [amount: {:invariant, :not_negative}]}`, 422 `{"invalid": {"amount": "not_negative"}}`; an event a
  decision returns, and a domain service's arguments and result, raise. The log read back is never checked. A
  domain declaring no invariant keeps its version, and so do its contracts' wiring versions.
- **EL2b: `use EhOsContract.ScenarioCase, domain: D`** writes a test per example of each value's invariants.
- **EL2b: `value-without-implementation`**, a warning of `check`: a value declares invariants and nothing checks
  them, in a domain some contract of which has code.
- **EL2b: a contract's wiring version includes the modules checking its domain's values**, so binding a value
  to another module records a new deployment, as rebinding a unit does.
- **EL1: every finding of `mix eh_os_contract.check` names a rule** of `EhOsContract.Check.Catalog`, a name
  that does not change between versions, documented in `docs/rules.md` (generated from the catalog). A
  finding about a v2 contract says the file and line of its declaration. `--format json` prints one array of
  `rule`, `level`, `message`, `file`, `line` and `documentation`; `--warnings-as-errors` fails the task on a
  warning too. Nothing silences a rule. `no-contracts` now counts v2 contracts, so an application with only
  v2 contracts no longer hears that it has none.
- **EL1: ESDM's completeness rules that read a whole domain**, warnings of `check`: `orphan-actor`,
  `orphan-external-system`, `bounded-context-without-content` (a context no contract belongs to),
  `orphan-context-mapping` and `cross-bounded-context-reference-without-mapping` — a reference being a
  `consumes` of another context's contract or a field naming another context's entity.
- **EL1: ESDM's completeness rules that read one contract**, warnings of `check`: `aggregate-without-events`,
  `event-without-consumer` (a promise or `terminal: true` counts as a reader, the conformance report),
  `read-model-without-query`, `process-manager-without-ends-on` (ESDM's `-ends-when`),
  `process-manager-without-event-reactions`, `event-name-with-aggregate-prefix`, and the library's own
  `consults-without-match`.
- **EL1: v1's rules over v2 contracts, and one only an implementation answers**: `backward-edge` (a
  reaction issuing a command into an earlier stage), `competing-in-transaction-consumers`,
  `free-text-not-personal` (a notice) and `emits-never-produced` (an event a command declares and no
  `emit/1` of its implementation names).
- **EL1: `check` repeats the rules between modules (L3) as errors** in a project whose `compilers` has no
  `:eh_os_contract`, under the codes the compiler prints (`X2`, `D14`, …). A project that registers the
  compiler sees no change.
- **EL2: `mix eh_os_contract.glossary`** (ESDM's `glossary`): the domain's ubiquitous language as Markdown,
  a section per context, `--language` for a translation, `--context`, `--domain`, `--output`
  (`EhOsContract.Glossary.render/2`). `EhOsContract.Registry.domains/0` lists the domains of the configured
  applications.
- **EL2: `mix eh_os_contract.view`** (ESDM's `view`): the domain as a tree — contexts, their contracts, each
  contract's units with commands and events, consumers, read models, queries and domain services — with a path
  to keep one branch and `--details` for what each row declares (`EhOsContract.View.render/3`).
- **EL2: `constraint` in a command and a query** (ESDM's constraints). A command's is checked as an invariant
  is: `rejects:` names it, `reject/1` refuses on it, and a `rejected` scenario of the command is required for
  each (A7, S8); a query's is prose. A command or a query declaring none keeps its version.
- **EL2: a directed relation may end at an external system**, `relation :conformist, upstream: :tax_registry,
  downstream: :invoicing`, with the other end a context (D5); a name both a context and an external fails the
  compile (D1). `orphan-external-system` counts a relation's end as a use, and `orphan-context-mapping` counts a
  relation to an external as crossed when a contract of its context calls it, depends on it or acts through an
  actor it backs.
- **EL2: `issued_by:` on a field**, the domain external that gives its value (a number a registry assigns):
  `field :invoice_number, :id, issued_by: :tax_registry`, with an entity reference too. An unknown
  external fails the compile (X4 in a contract, D8 in a domain). `view --details` shows it; `check` counts it as
  a use of the external. A field without it keeps its digest.
- **EL2: `relation-against-references`**, a warning of `check`: a contract of a directed relation's upstream
  context consumes a contract of the downstream one or names an entity it owns, or any such reference crosses
  `separate_ways`.
- **EL2: `label-with-avoided-term`**, a warning of `check`: a label of a contract uses, as a whole word in any
  case (not its inflected forms), a word its context's glossary says to `avoid`, in declarations' labels and
  enum members' labels.
- **EL2: `external-direction-contradicted`**, a warning of `check`: a value is `issued_by:`, or an actor
  `backed_by:`, a system declared `direction: :outbound`.
- **EL2: `reaction-without-scenario`**, a warning of `check` (ESDM's `feature-without-scenarios`): a policy, a
  process manager or a query no scenario runs.
- **EL2: `subdomain-without-bounded-context`**, ESDM's warning for a subdomain no context names; `view`
  shows each context's subdomain and its kind.
- **EL1: `EhOsContract.Domain.vocabulary/0`**, the domain DSL's words by entity path, as
  `EhOsContract.Next.Contract.vocabulary/0` has them for the contract; a test pins both.
- **EM2: `domain_service` in a contract** (ESDM's domain service): pure functions no unit owns, each with
  typed `argument`s, a `returns` type and prose `rule`s. The contract generates `C.DomainServices.<Name>`, a
  behaviour for the implementation (`use C, domain_service: :name`, I2 asks for every function) and the module
  a decision calls: `C.DomainServices.Seating.free_seats(3, 1)` checks the arguments, runs the implementation
  and checks its result, raising on a mismatch without the value in the message
  (`EhOsContract.DomainService`). `mix eh_os_contract.check` counts it among what a contract implements. A
  contract declaring none keeps its version.
- **EM3: the library may give a new aggregate its identity** (ESDM's `identifiedBy: generated`). An aggregate
  declares `identity :booking_id, generated: :uuid`, and a command `creates: true`; that command arrives
  without the identity, dispatch gives it a UUIDv7, and `%EhOsContract.Receipt{identity: %{booking_id: id}}`
  returns it — the first command's for a duplicate. A creating command that brings an identity is refused
  with `{:error, {:invalid, [booking_id: :generated]}}`, a new problem; every other command still needs one.
  A6 keeps it to an aggregate with one identity field and at least one creating command. `Receipt` gains
  `identity` for every command, and `EhOsContract.Plug`'s 200 body carries it as `"identity"` (the user's
  choice after the EM3 review: over HTTP a creating command was otherwise blind to what it made).
  A creating command needs an idempotency key, `{:error, :idempotency_key_required}` (a new refusal, 422 over
  HTTP) without one, since a retry would otherwise make a second aggregate; a reaction's key is derived.
  `EhOsContract.record/3` records an event of such an aggregate only for one a command created,
  `{:error, :not_created}` otherwise, a new refusal.
- **EM3: a process manager's timer may wait by the calendar**, `timer :review, wait: {1, :month}` — also
  `:week` and `:year`. A month after 31 January is the last day of February (`EhOsContract.Duration.calendar_shift/2`,
  `DateTime.shift/2`). `within` and `deadline` still take fixed units only, since the report measures elapsed time
  against them.
- **EM3: a domain service's result may be declared empty**, `returns {:id, :clinic}, optional: true`; without
  `optional:` a `nil` result is still refused. `returns` is its own declaration now, and a function without one
  does not compile (F2).
- **EM2: `entity` in a domain** (ESDM's entity): reference data with an identity that no event of the log
  changes — `entity :period, "Billing period", context: :invoicing, identified_by: :period_id do field … end`. A field
  of a contract or of a domain value names one as `{:id, :period}`; it is an `:id` in the model, in the log and
  in the tags, with `refers_to: :period` beside it. D6 checks the entity and every field naming one, X3 a
  contract's. The library keeps no rows of it. A domain declaring no entity keeps its version.
- **EM1: a command to a dynamic consistency boundary dispatches** (v2 §10.1), through `EhOsContract.dispatch/3`
  as a command to an aggregate does, and `EhOsContract.record/3` records a boundary's event. The decision folds
  what the boundary reads — its own events under its identity, and each event it `consults`, a sibling
  contract's too, on the fields it matches or all of the type by `where:` — and the append goes in only if
  none of it moved since the read; otherwise dispatch reads and decides again, as for a stream.
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
- **E7c: a query reads its own writes.** `EhOsContract.query/3` takes `min_position:` — the `position` of a
  dispatch's receipt — and waits, up to `wait:` milliseconds (5000), until the read model the query reads has
  taken it; otherwise `{:error, :not_caught_up}`. A read model delivered in the transaction already has it.
- **E7c: scenario coverage** (`EhOsContract.Coverage`, v2 §13): a v2 report's `scenarios` says how many of the
  contract's command scenarios the log saw happen — by type only, `given` among the stream's types and `expect`
  a subsequence of what was emitted, or the same rejecting invariant — which never, and which decisions no
  scenario declares. Beside it, `wiring` names the deployed wiring version and since when.
- **E7c: `mix eh_os_contract.check` reads v2 contracts** (`EhOsContract.Check.v2_findings/1`): a process with no
  `accountable`, a declaration or promise not confirmed, a promise with no `within`, a `deadline` no run can be
  seen to end, and whether the contract is implemented — not at all is noted (D3), in part is a warning. What
  the DSL refuses to compile is not repeated. The sandbox gains one warning (a contract with no
  `accountable`), which E6's port had taken out of the output.
- **A v2 process's declared shape** (after E7c): `EhOsContract.Graph.declared_to_mermaid/2` draws a v2 process as
  it draws a v1 one — stages as lanes, the contract's own and included events in them, promises as arrows with
  their window, endings and externals marked. `mix eh_os_contract.graph --process NAME --mermaid` draws it for a
  v2 process too; with `--overlay`, the steps with the log laid over them, as before.
- **E7c: a v2 contract's graph**, `EhOsContract.Graph.steps_to_mermaid/2` and `mix eh_os_contract.graph --process
  NAME --mermaid` for a v2 process: a node of every kind — commands, events, policies, process managers,
  effects, timers — in the Event Storming colours, and each step as its edges; with `--overlay` (`overlay:
  true`) the runs per step, the occurrences per event, and what waits or fails.
- **E7c: `mix eh_os_contract.report` reports v2 contracts too**, one section each beside the v1 ones.
- **E7c: the boot records the deployment of every v2 contract** (`EhOsContract.Registry.v2_contracts/0`, beside
  `contracts/0`, which stays v1's). Its paths are its declared steps, and **its wiring version is computed from
  the contract and the implementation**: the steps, and which module implements each declaration, so the same
  contract bound to other modules is another wiring. This moves verdicts of a v2 report: the deployed version
  has a `since`, and a changed `promise` — digested on its own at the deploy, `promise:<name>` — stops judging
  the runs that began before it.
- **E7c: the conformance report reads v2 contracts, and `conformance.v2` is their shape on the wire.**
  `EhOsContract.Conformance.report/2` of a v2 contract answers the same four questions: its steps
  (`EhOsContract.Paths`, each end `{kind, name, label}`) untraversed, in flight and failing, with `in_flight`
  as `{effects, timers, lag}` and `failing` as `{commands, subscription, effects}`; its confirmed promises under
  `promises`; its confirmed deadline and cadence; and as drift, an event of the deployed version no declared
  command emits. `as_data/2` names it `eh_os_contract.conformance.v2`. **A v1 contract's report is unchanged,
  and stays `conformance.v1`.** `EhOsContract.Report` renders both, and a v2 step says which consumer it runs
  through and which source waits or fails.
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
  `context :circulation, "Circulation", subdomain: :supporting do … end` as well as the options written inside
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
- `EhOsContract.Plug` asks whether the caller may make the call before it says what is wrong with the request
  (stage EA). A body that is not an object, fields that do not decode, or a correlation id that is not a UUID
  are asked of the `EhOsContract.Authorizer` as the call would have been: a caller without the capability gets
  403 where it used to get 400 or 422 with the fields named, and a scoped query without its parameter is 403
  `outside_scope`, as `query/3` answers it. Each request is still exactly one question to the `Authorizer`.
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
- **E8a: personal fields are encrypted in the log** (v2 §14). A field declared `personal:`, at any depth of a
  domain value, is stored as `{"$eh": "enc1", "k": 1, "d": "…"}`: its value JSON-encoded and sealed with
  AES-256-GCM under its subject's data key, bound to the event type, the field, the subject and the key
  version. Each subject's key is made the first time an event carries its data — read, made and wrapped before
  the append lock, so no writer waits on the vault, and stored under it — in `eh_os_contract_subject_keys`,
  wrapped by a master key of `EhOsContract.Vault`. Reading an event
  back — a decision's folded stream, a receipt, a consumer — opens its personal fields; a stream reads every
  key it needs in one query, and an event without personal fields reads none. **No verdict moves**: the
  conformance readers never read a payload's personal fields.
- **E8a: `EhOsContract.Erased`** is what a personal field reads back as once its subject is erased — its key
  gone, and the subject recorded in `eh_os_contract_erasures` — `%EhOsContract.Erased{subject: :member, id:
  "member-anna"}`. A key gone without that record raises instead. The structs a contract generates, and the types of
  domain values, admit `EhOsContract.Erased.t()` on every personal field, and `EhOsContract.Codec.problems/3`
  accepts it there and nowhere else. Sealing it into the log is refused; out of the log — a query's rows over
  HTTP — it is written as `null`.
- **E8a: `EhOsContract.Vault`**, the behaviour of the master keys, with `EhOsContract.Vault.Local` as default: the
  keys come from `config :eh_os_contract, EhOsContract.Vault, keys: [{id, base64}]`, the first wrapping, the
  others only unwrapping. `mix eh_os_contract.rewrap` rewraps every data key a retired master key still
  wraps. Another vault, a KMS, is `config :eh_os_contract, vault: MyVault`.
- `EhOsContract.Codec.encode/4` takes a function that seals personal fields, `decode/4` takes `open:`, and
  `personal?/2` and `subjects/4` say where personal fields are and whose they are.
- **E8a: F7 refuses personal data where the library keeps it outside the log**, since erasure reaches only
  what the log encrypts (v2 §14). A process manager's state field declared `personal:` does not compile (L2);
  a process manager's state field, or a query's `scope` parameter, of a domain value holding a personal field
  at any depth — directly, through an alias, in a list — is an L3 error. A query's parameter takes no
  `personal:` itself.
- **E8b: `EhOsContract.erase(subject_type, subject_id, actor: actor)`** erases a subject, in one transaction
  under the append lock: its data keys are deleted, the erasure recorded in `eh_os_contract_erasures`,
  `eh_os_contract.subject_erased` appended (the subject's type and id, nothing personal), and every read model
  delivered in the transaction that projects that subject type's data forgets it. A read model after the
  transaction takes the same event in order, and a rebuild replays it. It answers `{:ok, :erased}`,
  `{:ok, :no_data}` when no data key was there for that id (recorded all the same; a mistyped id erases nobody),
  or `{:ok, :already_erased}`, and then nothing is appended; never `{:error, _}`, though it raises on a subject no
  domain declares. The engine asks no `Authorizer`: who may erase is the host's to decide.
  **No verdict moves**: the conformance readers never read the event, and a test pins
  `EhOsContract.Conformance.as_data/2` identical before and after.
- **What Oban keeps of a failed effect carries no value.** `EhOsContract.EffectJob` hands Oban
  `EhOsContract.EffectJob.Failure` in place of the effect's exception, exit or throw — the effect, the event's
  position and the kind of what failed, with the stacktrace's arguments dropped — and an `{:error, reason}`
  described by its kind only. Exits are trapped while the effect runs, so a linked process it started crashing
  comes back as an exit rather than killing the job with the crash's reason. Oban writes both into `oban_jobs.errors`, where a decoded event's personal data would outlive an erasure.
  A host that wants the full failure logs it in its own effect. **Failures recorded before this version may
  still hold values**: delete the failed and discarded rows of `EhOsContract.EffectJob` from `oban_jobs`, or let
  Oban's pruner take them, before counting on an erasure.
- **E8b: dispatch refuses personal data of an erased subject**, `{:error, :subject_erased}` (a new refusal),
  checked under the append lock before anything is sealed; it writes no `_commands` row. `EhOsContract.Plug`
  answers it `410` with `{"error": "subject_erased"}`.
- **E8b: a read model's `forget(subject_type, subject_id) :: :ok`**, an optional callback of the generated
  behaviour, called for the subject types whose personal data the read model projects.
  `EhOsContract.Codec.personal_subjects/2` says which.
- **E8a: personal data inside a domain value is held to the same rules as a personal field.** A field declared
  `personal:` whose type holds personal fields of its own is refused — in a domain value (F5) and in a contract
  (F5, L3) — since they would be sealed under the outer subject's key and outlive their own subject's erasure.
  A `publish` carrying a field of such a type is refused (D11, L3), as one carrying a personal field was.
  `EhOsContract.Codec.personal_type?/2` is the one predicate behind them and F7.

### Changed

- **`event-without-consumer` counts an event a unit's lifecycle starts on or moves on as read** (plan DD, P1b,
  #186): the report's lifecycle section reads it, whether or not the contract has a process. The check warns less;
  no verdict of the report moves.

- **Breaking:** **`mix eh_os_contract.pages` writes each contract's graph document beside its pages, and no diagram** (plan
  E13, #217). `graph/<contract id>.json` holds the contract's `graph.v1` document, linked from its page, and the
  task treats those files as its own when it overwrites, checks or deletes. The domain's context map and each
  unit's Mermaid diagram are gone from the pages. **A host that commits the pages and checks them with `--check`**
  runs the task once. Moves no verdict.
- **Breaking:** **The conformance wire is `eh_os_contract.conformance.v3`, and v2 is not served** (plan DD, P1a, #183; the
  user's decision). `report.contract` is the contract's `id:` (`"lending.circulation"`), as every row of the log names
  it since ID4, with `report.module` beside it; `report.deployment.contract` is the id too. The steps sit at the
  report's level, under `activity` and `paths` (`steps`, `untraversed`, `in_flight`, `failing`), and a step gives
  `taken` where it gave `runs` and `of_runs`; `processes[]` keeps `runs`, `declarations`, `duration` and `promises`.
  A reader of v2 moves to v3; EHOS is told in an issue. The dashboard's screen heads each contract with
  its id.
- **Breaking:** **The dashboard's APIs name a contract by its id** (plan DD, P1a, #183; the user's decision).
  `GET <mount>/conformance?contract=lending.circulation`, `<mount>/model/lending.circulation`, `<mount>/openapi/…` and
  `<mount>/asyncapi/…` take the `id:`; a module's name is an unknown contract. Their indexes list `"contract"` as the
  id and add `"module"`; the model index is `eh_os_contract.model-index.v2`. `EhOsContract.Registry.contract/1`
  finds a registered contract by its whole id. The OpenAPI and AsyncAPI documents keep the module as their title
  and carry the id as `info.x-eh-os-contract-id`. `mix eh_os_contract.graph --contract` takes the id too, and the
  text report heads each contract `CONTRACT: <id>`.
- **Breaking:** **A step counts how often it was taken, not the runs it was taken in** (plan DD, P1a, #183; moves verdicts).
  `EhOsContract.Paths.observe/2` gives each step `taken` — the events its command appended, or the commands its
  reaction issued, accepted or rejected — where it gave `runs` and `of_runs`; failed commands are counted the same
  way. Two deposits on one account read "2 taken" on the graph, where they read "1/1 runs", and two failures of one
  account are two. A contract's steps are counted whether or not it has a process, and an event's node on the graph
  shows its occurrences without the runs. A process still counts its runs (`Paths.runs_of/3`).
- **Breaking:** **A contract's steps are its own block of the report, judged when it recorded an event** (plan DD, P1a, #183;
  moves verdicts). `EhOsContract.Conformance.from_model/2` (now public) gives `activity` (the contract's events
  and its commands, whatever their outcome, in the period) and `paths` (`steps`, `untraversed`, `in_flight`,
  `failing`) at the report's level; a process (`Conformance.process/2`, now public) keeps its runs, declarations,
  duration and promises, without lists of steps. "Never carried out" is listed when the contract recorded an event
  in the period, where it was listed when its process had any run: a contract without a process is judged, and so
  is one whose events belong to no run. What waits and what fails is listed whatever the activity. The text report
  and the screen print a STEPS block before PROCESS; with no event it says "this contract recorded no event in this
  period", and a contract with no steps says "The contract declares no steps."
- **Breaking:** **The engine's rows and keys name a contract by its `id:`, not its module** (plan DD, stage ID4, #178). The
  `contract` column of events, commands, deployments and dependency observations holds `"lending.circulation"`
  where it held `"Lending.Contracts.Circulation"`; so do the keys of subscriptions, relays, inboxes and process managers
  (`"<id>:<kind>:<name>"`), a reaction's command key and the chain of reactions stored with an event. Moving a
  contract's module no longer cuts it off from its history. No table changes shape. **A host resets the engine's
  schema before upgrading, as for ID3** — one reset covers both: rows written before name modules and are not read.
  **The host also clears the tables its read models project into**, which are the host's and which the reset leaves: they
  hold projections of the log that is gone, and an ordered read model starts again from the new log's first event. An inbox's durable
  consumer on the bus is named by its key, so the transport keeps the old one and may go on filling it until it is
  deleted: what reaches it — before the upgrade and after it — is never taken under the new key. Stop what publishes
  to the inbox and drain it before upgrading, then delete the old consumer. An effect's job
  carries the name of the application its dispatch looked in (`"application"`), since an id cannot name it. The
  conformance wire, the dashboard's APIs and the exported model still name the module; they change with P1a. An
  `EhOsContract.Authorizer.Request` carries `contract_id` beside `contract`: an authorizer that records a decision
  names the contract by it.
- **Breaking:** **Two contracts of one `id:` across the configured applications, or the siblings they consume, are refused when the engine scans them**
  (plan DD, ID4, #178): `ArgumentError` naming both modules and their applications, at boot or at the first
  dispatch. X7 refuses it within one application at compile time; across applications no compile sees both, and
  since every row and key names the id, the two would share one history.
- **Breaking:** **Every contract names its `id:`, and an event's type is `"<id>.<event>"`** (plan DD, stage ID3, #173). A contract
  without `id:` no longer compiles (D11). The type stored with every event changes from `"<process>.<event>"` —
  `"loan.copy_lent"` — to `"<id>.<event>"` — `"lending.circulation.copy_lent"`. **A host resets the engine's
  schema before upgrading** (`EhOsContract.Migrations.down/up`, or a fresh database), not only the events table:
  subscriptions, the relay, process managers, runs and the commands' idempotency rows all point into the old log.
  Events stored under the old types are not read, and nothing reports them: an aggregate whose stream holds one
  raises, but a boundary, a subscription, a read model and the report skip them silently — a boundary that allows
  one booking per seat would accept a second for a seat booked before the upgrade. No tool converts them (the
  user's decision; rewriting stored types and reading old types as aliases were rejected). Every contract's version moves, so every
  deployment counts as changed, and graphs and reports name events by the new types. Process names stay unique in
  the application: they key their runs.
- **Breaking:** **A policy or a read model taking an event of another context declares its `delivery`** (plan DD, stage X1;
  the refusal is **X10**). Left out, it
  runs `:in_transaction`, inside the transaction that records the other context's event, so a failure of the
  reaction rolls that event back. **X10** now refuses such a reaction without `delivery:` at compile time; one
  that names `delivery: :in_transaction` compiles, and `mix eh_os_contract.check` warns about it
  (`in-transaction-across-contexts`). Only consumers of a sibling contract of the same domain and another
  `context:` are affected; within one context nothing changes, and a reaction that leaves `delivery` out keeps
  `:in_transaction` and its contract's version. An effect (`:at_least_once` unless declared) is not refused, but
  one declared `:in_transaction` on another context's event gets the same warning, which turns
  `check --warnings-as-errors` red. **A host with such a reaction adds `delivery:`** — `:at_least_once` (with
  its `idempotency` for a policy, P3; a read model takes none), or `:in_transaction` and an explanation for the
  warning. Choosing `:at_least_once` moves the reaction after the transaction: an overlay
  step goes from inline to subscribed, and a test that read the reaction's result straight after the dispatch
  drains the subscriptions first.
- **Breaking:** **T1: a domain value's invariant may no longer be named `:supplied`** (D9), the word a request's refusal now
  puts where an invariant's name goes, as it already could not be `:required`, `:type` or `:generated`. Rename one
  that was.

- **Breaking:** **A blank label no longer compiles.** A label is blank when it is empty or holds only Unicode whitespace and
  invisible format characters (zero-width spaces, direction marks, the byte order mark). N1 refuses one on any
  declaration of a contract, fields included; D1 does the same in a domain; F2 and D3 refuse a blank label of an
  enum member. `event :visit_closed, ""` compiled until now and left a page, a graph's node and a report's
  sentence with nothing saying what the business calls it. An optional label left out still passes, and a struct
  written as data, in a scenario's rows or an invariant's examples, is not checked. An enum member named `true`,
  `false` or `nil` is refused with a label too, as it already was without one. No version moves: a contract that
  compiles is unchanged.
- **Breaking:** **W2: a required date or timestamp is tagged with its day when appended, in the domain's zone.** Every required,
  non-personal field of type `:date` or `:timestamp`, or of a domain value resting on one, adds a tag
  `<field>.day:YYYY-MM-DD` beside the `:id` tags: a date its own day, a timestamp the day it falls on in the
  domain's new `time_zone:` option, UTC unless given (`use EhOsContract.Domain, …, time_zone: "Europe/Warsaw"`).
  A boundary that buckets by day (B2) will find every event appended from this version on; events appended before
  carry none, and none is added to them, since the log only grows — so **set `time_zone:` before you upgrade**, or
  the tags already written keep UTC's days. A zone other than UTC is read with the time zone database the host
  configures (`config :elixir, :time_zone_database, Tz.TimeZoneDatabase`, with `{:tz, …}` among its
  dependencies): the package brings none, and **D13** refuses a zone that database does not know — also when the
  configured module is not there. A node that runs with another database than the domain compiled with, or none,
  refuses to start, naming the domain and the zone, instead of raising on every append; it asks the domain of
  every contract it scans, also one in an application `applications:` does not list. Nothing reads the tags yet.
  Only a domain that sets a zone moves its version.
- **Breaking:** **W1: a row of the log carries the schema version it was written with, and newer code's rows wait.**
  Dispatch writes the event's `schema_version:` into `schema_version`, where every row said 1 until now, the
  column's default. A row written with a newer version than the running code declares is never decoded with the
  older fields: it raises `EhOsContract.NewerSchemaError`, which names the row, never a value. During a rolling
  deploy, or after a rollback, that means on the older node:
  - a command whose stream holds such a row is refused, recorded `failed` with that error;
  - a subscription, a process manager and a relay wait at the row: the events before it in the batch are
    applied, the row itself moves nothing, no attempt is counted, the runner logs a warning and tries again every
    5 s, and it goes on by itself once the node runs the newer code; a subscription does not turn `failing` over
    it, so do not `--skip` it;
  - an effect's job is snoozed for 30 s, which Oban does not count against `max_attempts`, and its backoff after
    a real failure counts only the attempts that ran;
  - a message an inbox takes whose policy's command meets such a row is answered `:nack` and delivered again.
  Rows written before this version say 1 whatever their event declared; no contract has raised a version yet, so
  none is misread. An older row decodes as before, until upcasters (V1). No contract version moves.
- **Breaking:** **N3: a timer has a label.** `timer :documentation_due, wait: {24, :hour}, …` no longer compiles; write
  `timer :documentation_due, "Documentation due", wait: {24, :hour}, …`. The label names what the timer is for,
  not how long it waits, which `wait:` or `at:` says, and a blank one is refused (N1). A process manager's page
  prints both, the callback's `@doc` and the graph's timer node carry the label, and so do the conformance report's
  and the dashboard's sentences about a timer's step, which named the timer before. **Moves the version** of every
  contract with a timer.
- **Breaking:** **N2: another application's event is `subscribe`d to, not `consumes`d.** `consumes "billing.invoice.issued.v1",
  as: :invoice_issued do … end` no longer compiles; write `subscribe "billing.invoice.issued.v1", as: :invoice_issued do
  … end`, the word its capability `<name>.subscribe` already used. `consumes` takes a sibling contract's module only
  and reads its events from this log; a published name given to it is refused by K1, which says to write
  `subscribe` instead. D11 says `subscribe`, and with no list of events to take, it no longer refuses one. The
  model is unchanged, so **no version moves**.
- **Breaking:** **N1: an entity declares `identity`, and the library injects it.** `entity :service, "Service", context:
  :configuration, identified_by: :service_id` with a `field :service_id, :id` no longer compiles; write
  `identity: :service_id` and drop the field, which the library adds first among the entity's fields as a
  required, non-personal `:id`, as it adds a unit's. An identity some system gives takes `issued_by:` on the
  entity, `identity: :number, issued_by: :tax_registry`, and the model keeps it on the injected field. D6 refuses an
  identity not in snake_case or declared again as a field; D8 holds an entity's `issued_by:` to the domain's
  externals. **Moves the version** of every domain with an entity, whose model now says `identity`.
- **Breaking:** **N1: a scenario names what it is about with `target`, not `scope`.** `scope :remind_on_close` in a
  `scenario` no longer compiles; write `target :remind_on_close`. `scope` stays a command's and a query's,
  where it narrows a grant. S1 says "target". The model's scenario loses its raw `scope` key and keeps the
  resolved `target`, so **the version moves** of every contract with a scenario.
- **Breaking:** **N1: a status that ends an aggregate's life is `final:`, not `terminal:`.** `status :closed, "Closed",
  terminal: true` no longer compiles; write `final: true`. `terminal:` stays an event's, where it ends a run of
  the process, so one word no longer means two things in one contract. T3 and T4 and dispatch's refusal say
  "final". **Moves the version** of every contract with a lifecycle, whose statuses carry the key in the model.
- **Breaking:** **N1 refuses a query named like an event an actor records**, at the query's line. Both are capabilities named
  `<domain>.<name>` (D14), and since EHOS's manifest offers queries and recorded events as capabilities too, it offers both. L3's D14 already refused the pair when
  the Mix compiler runs; N1 refuses it in the contract's own compile, before `Model.capabilities/1` could merge
  the two into one capability.

- **Breaking:** **EP4: `idempotency` names its key and its owner.** `idempotency: :event_id` no longer compiles: it is
  `[key: :event_id, owner: :self]`, the owner one of `:self` (the reaction's code keys what it writes),
  `:downstream` (the system an effect calls is given the key) and `:infrastructure` (the engine keys the
  commands a policy or a process manager issues, so the key is `:event_id`). P3 refuses `:downstream` outside
  an effect and `:infrastructure` on one. The callback's `@doc` and the reaction's page say what the owner
  asks of the code. **Moves the version** of every contract with an `idempotency`, which is a map in the model
  and in its export (`eh_os_contract.model.v1`), no longer an atom.
- **Breaking:** **#98: a key past 2048 bytes is refused, not failed.** F9's six fields were measured, not proved: a key heavy
  in `|` and `%`, which escape to three bytes, or behind a long name, fit a btree entry only when Postgres
  compressed it. Now the key is counted after escaping, with the name in front of it, against
  `EhOsContract.Key.budget/0`, 2048 bytes of the 2704 an entry holds:
  - **dispatch** refuses a command whose aggregate's stream id, or a run's key an event belongs to — home or
    included, the process's name and the instance id — is over it: `{:error, :key_too_long}`, or 422
    `{"error": "key_too_long"}`, with nothing written. Until now Postgres refused the append, and the answer
    was 500;
  - **a process manager** raises `EhOsContract.Key.TooLongError` on an event that would start a run whose
    key — its timer stream, `"$pm:<manager>:<correlation>"` — is over it, before anything is written. Its
    subscription stops at that event as at any failure, until someone skips it (`mix
    eh_os_contract.subscriptions`). Until now it stopped on Postgres's exception, or did not, depending on
    compression. An event no run takes is taken as before, whatever its key's length;
  - **a command a reaction issues** and dispatch refuses with `:key_too_long` raises, as any refusal of such a
    command other than a rejection does: a policy delivered `:in_transaction` rolls back the command that led
    to it, and the caller still gets a 500; one delivered `:at_least_once`, and a process manager, stop at the
    event. Only a command's own keys became a 422.
  - **A key written before this change past the budget** is now refused: an aggregate whose stream id is longer
    takes no further command, and a run is not started for it. A host finds them with
    `octet_length(stream_id) > 2048` on `eh_os_contract_events` and `octet_length(process) +
    octet_length(instance_id) > 2048` on `eh_os_contract_event_runs`.
  - The 422 of every command in the OpenAPI document names the new reason, so its `x-eh-os-contract-digest`
    changes.

- **Breaking:** **#96: a run and a process manager are told only by an `:id`, and a key has at most six fields.** Two
  contract shapes that compiled no longer do:
  - **F8.** A field a process or a process manager `correlate`s on is an `:id`, `{:id, entity}` or a domain
    value resting on `:id`, in every local event that carries it and in a manager's state. Its value is
    part of the run's and the manager's index key, and only an `:id` is bounded (255 bytes). Until now
    `correlate :invoice_number` on a `:string` compiled, and a request with 3 KB of text in it answered 500;
    on a manager delivered `:at_least_once`, its subscription stalled. A contract correlating on another type
    correlates on the identifier it stands for instead. A manager's correlation the state does not declare takes
    its type from the first local event carrying it, handled or not, so that event is held to F8.
  - **X6, the part F8 needs between contracts.** A process that correlates on a field no local event carries — a
    contract with no unit of its own, including a sibling's events — holds the sibling's field to `:id`. Until now
    its type was not compared at all.
  - **F9.** A unit's identity, a process's `correlate` and a process manager's `correlate` have at most six
    fields. Seven `:id` fields at their bound, with `|` and `%` that escape to three bytes, overflow the 2704
    bytes a btree entry holds, and the append failed.

- **Breaking:** **#65: a policy on another application's event is a path of the conformance screen. This moves verdicts.**
  `EhOsContract.Paths` declares a step `received event → policy → command` for every `consumes "<name>"` event a
  policy handles, and counts it taken in the runs whose commands that policy issued with a row of its inbox
  (`eh_os_contract_inbox`) as their cause, bounded by when the inbox took the row.
  - Until now such a reaction was neither traversed nor untraversed: the screen did not see it. A contract
    whose reaction was declared and never ran now reports it as untraversed.
  - The step is one of the contract's edges, so its wiring version changes once, at the first boot on this
    version, with the path among the paths added (`EhOsContract.Deployment`).
  - The contract's graph draws the received event, and its edge to the policy.
  - **What it does not see:** a delivery the policy fails on is rolled back with the inbox's row and delivered
    again by the transport, so it leaves nothing in this database. A received path that always fails reads as
    untraversed, not as failing, and the policy's own failures on the log are not counted against it.
  - The inbox now writes `received_at` by `EhOsContract.Clock`, as dispatch writes an event's `occurred_at`, so
    a report's bounds read both alike.

- **Breaking:** **What a request controls is bounded where what holds it is.** Past a bound a value does not fit its type:
  `{field, :type}`, or 422 over HTTP. Until now each of these failed a write or a host's read model later, a 500
  or a stopped subscription. The bounds:
  - **an `:id` is at most 255 bytes**, so an index entry keys it with room for the rest of a key;
  - **an `:integer` is a signed 64-bit integer**, what a `bigint` column holds. Until now an integer far beyond 64
    bits was let in, since the log's JSON and the BEAM hold it. **This reverses that**, by the user's decision;
  - **a `:decimal` is finite, with an exponent and a coefficient of at most a thousand digits.** `NaN` and
    `Infinity` were let in. A struct past the bounds failed at the append, where `Decimal.to_string(_, :normal)`
    refuses past its digits. Decimal itself parses text only within decimal128;
  - **a `:date` and a `:timestamp` are within the years 1 to 9999**, which Postgres keeps.

  **They hold wherever a value enters the log:**
  - a request, and another application's published event an inbox takes;
  - a command a reaction issues, an event a decider emits, a domain service's arguments and result.

  Reading the log back asks none of them, so what was written before them still reads. Written again — copied by a
  decider, re-issued by a reaction from an old event, published to another application — it is held to them:
  - an aggregate whose identity is past 255 bytes takes no further command;
  - a decider whose arithmetic leaves the bounds (two int64s summed past int64, a decimal's exponent past a
    thousand) fails the command, as an event that does not fit always has.

  A decimal within the bounds reads back whole, though Decimal 3 parses text, and casts an integer, only up to 34
  digits: the codec reads the plain form the log writes, and a JSON number is held to the bounds as its text is. An empty `:id` is refused as it is decoded, as validation refused it: an inbox
  takes a published event by decoding alone.

  A tighter bound — a `varchar(n)`, a `numeric(p, s)`, a sum a read model keeps — is the domain's to declare, as an
  invariant of a value. The OpenAPI and AsyncAPI documents carry the bounds JSON Schema has words for: `:id`
  `minLength`/`maxLength` in characters and `x-eh-os-contract-max-bytes`, since the bound is in bytes; `:integer`
  `minimum`/`maximum` beside `format: int64`, which only annotates. Every document with such a field gets a new
  `x-eh-os-contract-digest`, though its contract did not change.

  Over HTTP, **a query string Plug cannot read** — not UTF-8, nested too deep — is 400 `{"error":
  "invalid_query_string"}`, and one past Plug's length is 414. Either comes after the caller is asked whether it
  may make the call. Until now Plug raised as it read the string: Phoenix answered 400 and a bare Plug 500.

  A scope value past 255 bytes is asked of the `Authorizer` as none, so it is refused `:outside_scope` and never
  recorded in full.

- **Breaking:** **Request bytes the log cannot hold are a refusal, not an exception.** Until now Postgres refused to store each
  of these, and a request answered 500. The rule for an idempotency key also refuses keys that were stored before
  (below):
  - **Text in a `:string` or `:id` field holding a NUL, or invalid UTF-8, does not fit its type.**
    - Reachable over HTTP: `"\u0000"` in JSON, `%00` in a query string. Plug refuses invalid UTF-8 in a query
      string, and Jason in a body.
    - Reachable from a direct caller of `call/3` or `dispatch/3` with any bytes.
    - The answer is `{:error, {:invalid, [{field, :type}]}}`, or 422 `{"invalid": {"<field>": "type"}}`, at any
      depth of a domain value. A query's parameter is held to it too.
    - A published event an inbox takes is held to it as well. One that does not fit is delivered again, also when
      no policy would have stored the field.
    - A scope value that is not text is asked of the `Authorizer` as none (`nil`), so it is refused
      `:outside_scope` and never reaches a decision row.
    - Reading the log back does not ask again: a sealed personal value written before the rule still opens.
  - **A caller's idempotency key must be printable ASCII (`0x21`–`0x7E`) of at most 255 bytes.**
    - Otherwise the answer is `{:error, :idempotency_key_invalid}`, or 400 `{"error": "idempotency_key_invalid"}`.
      This is a new refusal.
    - The rule is stricter than the key's columns need, so a key never depends on what a text column, `jsonb` and
      an index entry happen to hold.
      - What failed the write before was a NUL, invalid UTF-8, or a key past about 2.7 KB.
      - These were accepted before and are refused now: a space, other non-ASCII UTF-8 such as `café-1`, a
        key of 256 bytes to 2.7 KB, and an empty `idempotency-key` header.
    - The OpenAPI document gives the header's pattern.
    - A reaction's key is held to it too, since a reaction's actor is a struct any caller can build. The key the
      library derives keeps its form, `<kind>:<contract>:<name>:<event id>:<n>`; one that would break the rule
      (names past what 255 bytes leave, a quoted module) is `<kind>:sha256:<hex>` of it instead.

- **Breaking:** **E12c, D12: only a policy takes an event another application publishes.** A read model, an effect or a
  process manager that names a `consumes "<name>"` event no longer compiles: the event arrives in an inbox and
  never enters the log they read, so none of them would ever have been given it. React with a policy, and take
  the event its command records.
- **Breaking:** **E12c: V01 creates one more table, `eh_os_contract_inbox`.** V01 is changed in place, as before 0.3.0 is
  first released: a database migrated earlier has no inbox. Recreate it, or create the table V01 now creates.
- **Breaking:** **E12c: an `EhOsContract.Bus.Message` has a fifth field, `key`, and it is required.** A transport adapter
  carries it as it carries the id; a test that builds a message gives it one.

- **Breaking:** **D11: a domain's `name:` is one segment of an application's namespace.** It begins every name the domain's
  contracts publish and every capability, and nothing checked it: `name: :"acme.billing"` published
  `"acme.billing.x.v1"`, which passed both D11 checks and lies in the namespace of an application `acme`. A
  domain whose name is not lowercase letters, digits, `_` and `-`, starting with a letter and not ending with a
  dash, no longer compiles, even one that publishes nothing, and the refusal points at its `use`. Of the names
  that could publish before, only those with a dot are refused.
- **Breaking:** **F1, D3 and D6: a field's name is snake_case, and a value's field is named once.** A contract's fields
  were checked only for uniqueness and a leading `__`, a value's and an entity's only for uniqueness (an
  entity's) or not at all (a value's): `field :"Invoice No"` became a key of the typespec, the JSON Schema and
  the page, `:"a|b"` broke the unit graph's edge it labelled, and a value's field declared twice gave the JSON
  Schema the later definition with the earlier one's `required`. A unit's `identity` is held to the same,
  named once, at the unit: `identity :"a|b"` reached a graph edge and a page table through `consults`. A
  contract or domain declaring such a field no longer compiles.
- **Breaking:** **N1: two names that camelize alike are refused where they become one module or alias.** N1 compared names
  exactly, so `event :visit_closed` beside `event :visit_closed_` compiled, with a warning that
  `<Contract>.Events.VisitClosed` was redefined: one event carried the other's struct. The same held for a
  command, event or consumed event (an implementation aliases each as `<Camelized>`) and for two aggregates,
  dcbs, reactions, read models, queries or domain services of one kind. N2 compares `:state` and `:row`, the
  aliases of a unit's state and a read model's row, camelized too, so `command :state_` is refused. A contract
  that declared such a pair no longer compiles.
- **Breaking:** **D1: a subdomain's, context's, subject's, value's, entity's and external's name is snake_case.** They were
  held only to uniqueness: `value :"a/b"` generated `<Domain>.Values.A.B`, a module nested in another, and
  `context :"front desk"` broke the context map's diagram; `mix eh_os_contract.pages` refused such a name, but
  only when it ran. Two values whose names camelize alike (`:money_amount`, `:money_amount_`, `:money__amount`)
  generated one module of invariants once either had one, and are now refused as two of one name. A value
  named after a type Elixir builds in (`:map`, `:bool`), whose `@type` failed to compile with an error pointing
  at the library, and one named after a built-in field type (`:date`, `:id`), which a field of that type
  silently meant instead, are refused with a code. A domain that declared one no longer compiles. Field names
  are not covered.
- **Breaking:** **D4: an actor's name is snake_case.** A person's is a role, `<domain>.<actor>`, in the manifest EHOS
  reads, and nothing checked its form: `actor :"*", :human` in a domain `acme` was the role `"acme.*"`, and
  `:"billing.clerk"` a role of two segments. A system actor is held to the same form, since `by:` names it as
  it names a person. A domain that declared one no longer compiles.
- **Breaking:** **N1 and D9: a name ending in a newline is refused, and so is a decimal in scenario data.** Their patterns
  ended in `$`, which also matches before a final newline: `command :"pay\n"` compiled, and its capability
  `"<domain>.pay\n"` reached `EhOsContract.Model.capabilities/1`, the OpenAPI document and the EHOS manifest.
  The same held for a value invariant's name and a scenario's decimal written `"12.50\n"`: a contract or a
  domain that declared one no longer compiles. `mix eh_os_contract.pages` refuses a page named after a
  domain's element ending in a newline, as it refuses one with a space.
- **Breaking:** **D11: a published or consumed name ending in a newline is refused.** The pattern ended in `$`, which
  also matches before a final newline, so `"billing.invoice.issued.v1\n"` compiled; on a broker such a name
  breaks the subject line. A contract that declared one no longer compiles.
- **Breaking:** **E11f: a unit reads only what its `evolve/2` folds.** When every clause of `evolve/2` that does not name
  an event is exactly `def evolve(state, _), do: state`, dispatch decodes only the events it names. A
  boundary's query and its conflict condition narrow to those types, so appending an event it passes
  over no longer conflicts with its decisions, and its commands' `given_types` list only folded types —
  unless it folds none of its events, when it reads and conflicts on all of them as before, since a store
  query cannot be empty.
  Scenario coverage compares a scenario's `given` on the folded types too, so no verdict moves for a
  scenario that names an event the unit passes over. A row of a passed-over type that no longer fits its
  declaration no longer stops the stream; a type the contract no longer declares still does.
- **Breaking:** **E11f: an idempotency key belongs to the actor who sent it.** Dispatch looks an accepted key up by the
  actor and the key together, and the unique index is on both (`issued_by`, `idempotency_key`). Before, the
  key was one for the whole application: a second actor sending a key the first had used got the first
  one's receipt — its events, personal fields opened — and its own command was not run. Now it is its own
  command. A host that shared one key between actors on purpose, to run a command once whoever sends it,
  no longer gets that. A retry therefore has to come from the same subject, and whatever shares one
  credential or one `:system` actor shares one key space (`docs/authorization.md`). A credential with an
  empty subject is refused, since it would make every such credential one actor. A development database
  created before this change keeps the old index: recreate it,
  or rebuild the index with `DROP INDEX eh_os_contract_commands_idempotency_index` and the `CREATE UNIQUE
  INDEX` V01 now runs.
- **Breaking:** **E11b: the second DSL takes the first one's names.** `use EhOsContract.Next.Contract` is
  `use EhOsContract.Contract`, and every `EhOsContract.Next.*` module drops `Next`. `Registry.v2_contracts/0`
  is `Registry.contracts/0`, and the scan's key `graph().v2_contracts` is `graph().contracts`;
  `Check.v2_findings/1` is `Check.findings/1`; `Deployment.v2_edge_labels/1` is `Deployment.edge_labels/1`.
  **`Registry.contracts/0` and `Check.findings/1` existed before and meant the first DSL's contracts**: a
  call written before E11 still compiles, and now gets the second DSL's.
- **Breaking:** **E11c: the engine's storage is one migration.** `EhOsContract.Migrations.current_version/0` is 1, and V01
  creates the whole store in its final shape. The upgrades to versions 2–5 are gone, and nothing migrates a
  database from them: **a database that holds data stays on 0.2.x.** A development database is recreated —
  delete the host's migrations that call `up(version: 2..5)` first, since on a fresh database they would
  run versions that no longer exist, then `ecto.drop`, `ecto.create` and `ecto.migrate`; what the old log,
  subject keys and erasures held is gone with it. Left as it is, such a database is refused: `up/1` and
  `down/1` raise on a recorded version above 1, and on a target outside the versions the release has — a
  leftover `up(version: 3)` migration fails with that message. The final shape differs from what V05 left:
  text columns are
  `text`, not `varchar(255)`; `eh_os_contract_event_handlings` and `eh_os_contract_handler_failures` are not
  created; the indexes on `type`, `causation_id`, `instance_id` and `(process, instance_id)` of
  `eh_os_contract_events` are not created, since runs are read through `eh_os_contract_event_runs`.
- **Breaking:** **E11a: R2 refuses a process with `correlate []`, and P4 a process manager with `correlate: []`.** Both
  compiled, and then every event of the contract joined one run — the report counted one run for everything
  — and every run of the manager shared one record, state and set of timers.
- **Breaking:** **E11a: an empty `:id` is refused**, at dispatch (`{field, :type}`) and in scenario data at compile (S3), as
  an entity's id is. The log read back still accepts one, so what is already written keeps reading.
- **Breaking:** **E11a: a promise can be suspended.** `EhOsContract.Dependency.unavailable!/4` takes a contract with an
  event that `depends_on` the external, where it accepted only a first-DSL contract, so an outage recorded
  inside a promise's window now suspends it instead of counting as a violation. `Dependency.observe/3`
  records an outage of an external the contract only `calls:`, where it raised; such an observation
  suspends nothing, since promises read only `depends_on` events.

- **Breaking:** **E10: `EhOsContract.Model.to_data/1` publishes the v2 model under the named schema
  `eh_os_contract.model.v1`.** The JSON-ready document includes the contract, its domain, derived human
  capabilities and a digest of that projection. Its declaration and example structure is complete, but
  personal values in scenarios, rule examples, invariant examples and defaults are `null`: the public model
  is not a second store for fixture data. A scenario's event is redacted by the fields of the contract that
  declares it, so a consumer's scenario on a sibling's event does not publish that sibling's personal
  values. What no declaration covers is `null` rather than verbatim: the data of an event or command
  that cannot be found, a query's answer without its read model, a key no field declares, and a
  structured value's example that is not a map but holds a personal field.

- **Breaking:** **E9c: a command may be scoped, as a query is (D10).** `command :x, "…", by: :actor, scope: :field` names one
  of its fields; `EhOsContract.Model.capabilities/1` gives the command's capability that `scope:` instead of
  `nil`, and dispatch — and `EhOsContract.Plug` — ask the `Authorizer` with the field's value. A credential
  granted a scoped command without values for its dimension is refused `:unscoped_grant`, as for a query, so a
  host granting one has to send the values (`scp`).
- **Breaking:** **E9a: an event a contract records has a capability, and a credential records with it.**
  `EhOsContract.Model.capabilities/1` gives each event declaring `recorded_by:` the capability
  `<domain>.<event>`, kind `:record`, with the roles of its `recorded_by:` actors; `EhOsContract.record/3` asks
  the `Authorizer` for it, as `dispatch/3` does for a command, instead of refusing every credential with
  `{:error, :not_grantable}`, which is gone. `EhOsContract.Plug` serves it as `POST <mount>/records/<capability>`,
  and answers a recording for a unit no command created (`{:error, :not_created}`) with 404 `{"error":
  "not_created"}`.
  A host that checks every capability has an entry point (`EhOsContract.Auth.Testing`, which EHOS asks of an application) maps the
  recordings too; D14 now also refuses a recorded event named like another declaration's capability.
- **Breaking:** **E9a: only what a person may do is a capability.** `EhOsContract.Model.capabilities/1` gives a command, a
  query or a recorded event a capability only when its `by:` or `recorded_by:` names a `:human` actor, and its
  roles are those people only. A command only a reaction issues (no `by:`) and an event only a `:system` actor
  records have none: a credential naming them is refused `:missing_capability`, and `EhOsContract.Plug`
  answers 404. A host's entry-point check drops them; the application's own `:system` actor reaches them as
  before.
- **Breaking:** **EG1: `EhOsContract.Graph.steps_to_mermaid/2` is `contract_to_mermaid/2`**, and draws a v2 contract's full
  graph (below). A caller renames the call; the options (`overlay:`, `since:`, `until:`) and the steps' nodes and
  edges are the ones they were.
- **Breaking:** **EL2b: a domain service's `rule` needs `examples:`**, `rule :never_below_zero, "…", examples: [{[1, 3],
  0}]` — the arguments in the order the function takes them, then the result. A rule without one fails the
  compile (S9), and so does an example of the wrong arity or types (S9, X9 for domain values). Each example is a
  test in `use EhOsContract.ScenarioCase, contract: C`, run through `C.DomainServices.<Name>`.
- **Breaking:** **EL2b: N2 refuses a callback named after a function every module defines** at its arity: an event
  `:module_info` (its handler would define `module_info/1`) fails the compile, as a domain service's function
  of that name already did.
- **Breaking:** **EL2: a subdomain is named, and a context names it.** `subdomain :core, "Lending", type: :core` in the
  domain, then `context :circulation, …, subdomain: :core`; `subdomain:` on a context no longer takes the kind,
  and a name the domain does not declare fails the compile (D7). A domain keeping its old contexts can declare
  `subdomain :core, "…", type: :core` and leave them as they are. Every domain's version moves.
- **Breaking:** **EL2: a translation needs its `definition:`**, as in ESDM: `translation :en, "Completed", definition: "…"`;
  one without fails the compile. A translation may name words to `avoid` in its language, and an `avoid` may
  give its `reason:`. `mix eh_os_contract.glossary --language` prints them.
- **Breaking:** **EL1: `mix eh_os_contract.check` prints two lines a finding**, `LEVEL <rule>: <sentence>` and then where the
  declaration was written (v2 contracts) and the rule's entry in `docs/rules.md`. A script reading the old
  one-line output reads the first line of each pair; one reading it by program should move to `--format json`.
- **Breaking:** **E8b: a read model that projects personal data needs `forget/2`**; without it, the `EhOsContract` child
  refuses to start, since an erased subject's data would stay in its tables.
- **Breaking:** **E8a: a host whose contract declares personal fields needs a master key**, `config :eh_os_contract,
  EhOsContract.Vault, keys: [...]` (`README.md`); without one, the `EhOsContract` child refuses to start. A host
  without personal fields configures nothing.

- **Breaking:** **The log is append-only.** Triggers refuse UPDATE, DELETE and TRUNCATE on `eh_os_contract_events`. A test
  that moved `occurred_at` afterwards has to emit in the past instead, with `EhOsContract.Clock.at/2`. A test
  database that leaked rows is recovered with `ecto.drop`.
- **Breaking:** **Emissions run under READ COMMITTED.** `EhOsContract.Store.Postgres` refuses to append at a stricter
  isolation level. Every append takes one transaction-scoped advisory lock, so a transaction that locks a row
  and then emits can deadlock with an emission whose handler locks the same row. Take
  `EhOsContract.Store.Postgres.lock/1` first (`EhOsContract.Store`'s moduledoc).
- **Breaking:** **A new dependency: `spark ~> 2.7.3`.**
- **Breaking:** **E7a: the `EhOsContract` child is a supervisor.** Besides scanning the registry and recording the
  deployment, it registers every subscription, rebuilds the stale read models that define `reset/0`, and
  starts one runner per subscription; dispatch wakes them through Oban's notifier after each commit it owns.
  **A host's tests set `config :eh_os_contract, subscriptions: :manual`**, which skips registration and
  runners, and drain with `EhOsContract.Testing.drain/1`. `EhOsContract.boot/0` is gone.
- **Breaking:** **EM1: an `EhOsContract.Store` implementation of the host's own needs `read_query/2`**, and its `append/3`
  takes a third condition, `{:dcb, query, after_position}`, refused with `{:error, :condition_failed}`
  (v2 §10.1). `EhOsContract.Store.Suite` checks both. `EhOsContract.Store.Postgres`, the default, has them.
- **Breaking:** **EM1: an appended event is tagged with every required, non-personal `:id` field it carries**, not only its
  unit's identity: `["account_id:a-1", "branch_id:b-7"]` where it was `["account_id:a-1"]`. A consistency
  boundary finds what it consults by these tags, so a `match:` names only such fields (A4 for a local event,
  X6 already for a sibling's). Events appended before this version carry the narrower tags.
- **Breaking:** **EM1: a command's row in `eh_os_contract_commands` lists each type it was given once** (`given_types`), in
  the order first read, where it listed one entry per event: a boundary may read the whole history of a type.
  Scenario coverage compares these as sets, so no count moves.

- `mix eh_os_contract.check` prints its findings in a fixed order: errors, warnings, notices, each by text.
  The lines are the same.

### Removed

- **Breaking:** **The Mermaid pictures** (plan E13, #217). `EhOsContract.Graph` is gone, with `declared_to_mermaid/2`,
  `contract_to_mermaid/2`, `unit_to_mermaid/2`, `lifecycle_to_mermaid/3`, `context_map_to_mermaid/1` and
  `system_to_mermaid/3`, and `mix eh_os_contract.graph` draws nothing: `--contract <id>` gives the contract's
  `graph.v1` document as JSON where it gave a Mermaid diagram, and `--process`, `--mermaid`, `--unit`,
  `--lifecycle`, `--map` and `--system` are refused as unknown options. **A host that drew a picture** with them
  mounts the dashboard (`eh_os_contract_web`), whose Graph screen draws the same six pictures, or renders the
  documents with `eh_os_contract_graph`. Moves no verdict.
- **Breaking:** **A process has no `cadence`** (plan DD, P1d, #195; the user's decision). It said how often a run is due
  (`cadence {1, :month}`), and nothing acted on it: the report printed "Due: every …" among the process's
  confirmed declarations, the pages "Cadence: every …", and the check noted an unconfirmed one
  (`unverified-declaration`). A contract that declares it no longer compiles (`undefined function cadence/1`):
  delete the line. The report's `declarations` hold at most the confirmed `deadline`. A process is digested as it
  was with no cadence declared, so no other contract's version moves; one that declared it moves once, when the
  line goes. The exported model (`EhOsContract.Model.to_data/1`) loses the `"cadence"` key from `"process"`, where
  it was `null` unless declared, so that document's own `"digest"` moves for every contract with a process.

- **Breaking:** **E11a, the first DSL:** `use EhOsContract.Contract` with `event`, `process`, `trace`, `rule`, `example`, `external` and `command`
  keyword declarations, and everything that read them: `EhOsContract.Handler`, `EhOsContract.emit/4` and its
  emitter, `EhOsContract.Job`, handler failures, `EhOsContract.Telemetry`, `EhOsContract.Brief`, the first
  model (`Model.V1`), and the first DSL's findings in `check`, its AsyncAPI projection, report, trace, run,
  graph overlay and deployment rows.
- **Breaking:** **E11a, the first DSL:** `mix eh_os_contract.trace` and `mix eh_os_contract.brief`. A promise's verdicts are in the report; a Brief
  for a process owner comes back on the dashboard. `mix eh_os_contract.graph` without a picture flag refuses,
  exiting non-zero with its usage, instead of drawing the first DSL's graph: a script that ran it bare fails.
- **E11a, the first DSL:** The dashboard's "every contract" panel on `/graph`, which drew the first DSL's handler graph.
- **Breaking:** **E11a, the first DSL:** **Jobs of `EhOsContract.Job` still in a host's Oban queue have no worker.** Drain the queue before the
  upgrade. A job left behind fails and is discarded, and the handler's work it carried never happens, with
  nothing recording that. Its args hold the event's payload and actor, which erasure does not reach, so after
  draining delete the rows (`worker = 'EhOsContract.Job'`) rather than waiting for a pruner.
- **E11a, the first DSL:** The direct `:telemetry` dependency. It stays in the lock through Ecto and Oban.

### Fixed

- **A scenario of a unit without a lifecycle fails when its `evolve/2` returns anything but the unit's state**, as
  dispatch refuses it. Scenarios, property tests and dispatch now fold a unit's stream with one function
  (`EhOsContract.Decision`), where a scenario had folded such a unit without the check. Moves no verdict.
- **`EhOsContract.Model.to_data/1` redacts the rows a scenario gives with `given_entity`.** A field the domain's
  entity declares `personal:` was published as written; it is `null` now, as in a given event, and a row of an
  entity the domain does not declare has its values dropped. The model document of a contract whose scenarios
  give such a row changes its digest. Moves no verdict.

- **Moves a verdict:** **W3: a hit that does not name its item resolves none.** For a promise made per item, an `eventually` or
  `or_else` whose payload lacks one of the identity's fields, or carries it as `nil`, used to be paired by that
  `nil` with a `from` missing the same field, and close an item neither named. It now resolves no item, as the
  promise's rule always said; a `from` like that still opens its item. Only a log whose rows predate a unit's
  identity growing can hold such events: a run there that was satisfied this way is now violated. A log written
  under one identity is judged as before.

- **An append waits only for appends to the same log.** The append lock had one fixed key, and an advisory
  lock belongs to the whole database: where applications share one, each in a schema of its own, as EHOS
  keeps them, every application's appends waited for every other's. V01's lock now has two
  integers, the engine's and one derived from the schema's name, written into `eh_os_contract_append_lock()`
  and the log's trigger at migration, so neither resolves anything through the `search_path` at run time.
  V01 is changed in place, as before 0.3.0 is first released: a database migrated earlier keeps the old key
  until it is created again, which is still correct, only shared.
- **`up/1` and `down/1` run what the host's migration queued before them first.** Ecto runs `execute` and
  `create` only when a migration flushes, and the version and the lock's key were read before that: a
  `CREATE SCHEMA` queued ahead of `up/0` — `Oban.Migration.up(prefix: ...)` without `create_schema: false`
  queues one — left `current_schema()` empty, or with `search_path: "ledger, public"` read `public`'s version
  and key. The schema should still exist before the migrations run: Ecto places its own `schema_migrations`
  through the path before any of them does.
- **The storage works in a schema other than `public`** (issue #51; EHOS gives each application a schema of its own).
  `EhOsContract.Migrations` read and wrote its version on `public.eh_os_contract_events` by name, while the
  tables were created unqualified, in the connection's `search_path`. In a schema of the application's own,
  `up/0` failed on a `public.eh_os_contract_events` that did not exist, or, where `public` already had the
  tables, read their version, created nothing, and left the application to fail on its first write. The
  version is now read in `current_schema()`, where the tables are created, and written with an unqualified
  `COMMENT ON TABLE`; every query at run time was already unqualified. A host sets the schema as its repo's
  `parameters: [search_path: ...]` and gives Oban the same prefix. Nothing at run time creates, alters or
  drops anything: the role the application runs as needs `SELECT`, `INSERT`, `UPDATE` and `DELETE` on the
  tables, `USAGE` on the sequences, and `EXECUTE` on the engine's functions, which PostgreSQL grants to
  `PUBLIC` by default. Ecto's migration prefix (`--prefix`) is not supported, and says so.
- **`down/1` leaves a schema with no version recorded alone.** It ran V01's drops regardless, and with
  another schema later on the `search_path` (`"ledger, public"`) those unqualified drops found that
  schema's tables.
- **Oban's jobs are read where Oban's `prefix:` puts them.** The report's counts of waiting and discarded
  effect jobs and scheduled timers, and a process manager's check for a queued timer after a rebuild, read an
  unqualified `oban_jobs`, which failed when Oban's prefix was not on the search path. A node running no
  Oban still reports, looking on the path as before. No verdict moves where the jobs were on the path.

## [0.2.1] - 2026-09-23

### Changed

- The repository is `EmpoweredHouse/eh-os-contract`, renamed from `eh-os-prototype`.
  `source_url` and the package links point there. No code changed; no verdict moves.

## [0.2.0] - 2026-09-23

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
  and against EHOS's architecture as it was then written: both readings of "what this command emits" are
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
  the `eh_os_contract.docs` task is tooling for developing the package and is no longer
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

## [0.1.0]

Never published.

Everything up to 2026-09-22, recorded here after the fact because the rule above
did not exist while it was happening. **These entries are retroactive and carry no
version of their own** — inventing numbers for releases nobody published would be
a second source of truth about a sequence that never happened.

At least five changes at this version moved a verdict:

### Changed

- **Moves a verdict:** A process with no runs reports `basis: :no_runs` rather than reporting every
  declared path as untraversed. Zero runs is not evidence that a path is dead.
- **Moves a verdict:** Work sitting in the queue counts as in flight, not as a path nobody took.
- **Moves a verdict:** A step that is attempted and fails was split out of "never attempted". Both were
  previously one line, and they go to different people.
- **Moves a verdict:** `:suspended` became a fourth `trace` verdict: a run whose window contained an
  external dependency's outage is not a breach on the client's side.
- **Moves a verdict:** `unverified` reaches a `trace` by name, so the sharpest assertion the engine can
  make — the one most likely to be a guess — can be declared without being counted
  as measured.
