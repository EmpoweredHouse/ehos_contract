# Changelog

## The rule this file exists for

**A change that can move a verdict raises the MINOR version and gets a line here.**

A verdict is anything the conformance report prints as a number or a state: an
overlay edge's state, a promise's verdict, a path counted as untraversed, a run
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

### Added

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
- **A contract can name itself: `use EhOsContract.Contract, …, id: "rehmed.settlement"`** (plan DD, stage ID1). The
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
- **T1: a field the host gives, not the caller.** `field :p1_reported, :boolean, supplied_by: :host`, on a
  command's field or a recorded event's (**F10** refuses it anywhere else, and on a command's `scope` field).
  Through `EhOsContract.call/3` — and `EhOsContract.Plug` — a request that sends it at all, even as `null`, is
  refused by name, `{:invalid, [p1_reported: :supplied]}` (422 `{"invalid": {"p1_reported": "supplied"}}`). Once
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

### Changed

- **`event-without-consumer` counts an event a unit's lifecycle starts on or moves on as read** (plan DD, P1b,
  #186): the report's lifecycle section reads it, whether or not the contract has a process. The check warns less;
  no verdict of the report moves.

### Fixed — can move a verdict

- **W3: a hit that does not name its item resolves none.** For a promise made per item, an `eventually` or
  `or_else` whose payload lacks one of the identity's fields, or carries it as `nil`, used to be paired by that
  `nil` with a `from` missing the same field, and close an item neither named. It now resolves no item, as the
  promise's rule always said; a `from` like that still opens its item. Only a log whose rows predate a unit's
  identity growing can hold such events: a run there that was satisfied this way is now violated. A log written
  under one identity is judged as before.

### Changed — a host has to act

- **The conformance wire is `eh_os_contract.conformance.v3`, and v2 is not served** (plan DD, P1a, #183; the
  user's decision). `report.contract` is the contract's `id:` (`"rehmed.settlement"`), as every row of the log names
  it since ID4, with `report.module` beside it; `report.deployment.contract` is the id too. The steps sit at the
  report's level, under `activity` and `paths` (`steps`, `untraversed`, `in_flight`, `failing`), and a step gives
  `taken` where it gave `runs` and `of_runs`; `processes[]` keeps `runs`, `declarations`, `duration` and `promises`.
  A reader of v2 moves to v3; EHOS is told in an issue in `eh-os`. The dashboard's screen heads each contract with
  its id.
- **The dashboard's APIs name a contract by its id** (plan DD, P1a, #183; the user's decision).
  `GET <mount>/conformance?contract=rehmed.settlement`, `<mount>/model/rehmed.settlement`, `<mount>/openapi/…` and
  `<mount>/asyncapi/…` take the `id:`; a module's name is an unknown contract. Their indexes list `"contract"` as the
  id and add `"module"`; the model index is `eh_os_contract.model-index.v2`. `EhOsContract.Registry.contract/1`
  finds a registered contract by its whole id. The OpenAPI and AsyncAPI documents keep the module as their title
  and carry the id as `info.x-eh-os-contract-id`. `mix eh_os_contract.graph --contract` takes the id too, and the
  text report heads each contract `CONTRACT: <id>`.
- **A step counts how often it was taken, not the runs it was taken in** (plan DD, P1a, #183; moves verdicts).
  `EhOsContract.Paths.observe/2` gives each step `taken` — the events its command appended, or the commands its
  reaction issued, accepted or rejected — where it gave `runs` and `of_runs`; failed commands are counted the same
  way. Two deposits on one account read "2 taken" on the graph, where they read "1/1 runs", and two failures of one
  account are two. A contract's steps are counted whether or not it has a process, and an event's node on the graph
  shows its occurrences without the runs. A process still counts its runs (`Paths.runs_of/3`).
- **A contract's steps are its own block of the report, judged when it recorded an event** (plan DD, P1a, #183;
  moves verdicts). `EhOsContract.Conformance.from_model/2` (now public) gives `activity` (the contract's events
  and its commands, whatever their outcome, in the period) and `paths` (`steps`, `untraversed`, `in_flight`,
  `failing`) at the report's level; a process (`Conformance.process/2`, now public) keeps its runs, declarations,
  duration and promises, without lists of steps. "Never carried out" is listed when the contract recorded an event
  in the period, where it was listed when its process had any run: a contract without a process is judged, and so
  is one whose events belong to no run. What waits and what fails is listed whatever the activity. The text report
  and the screen print a STEPS block before PROCESS; with no event it says "this contract recorded no event in this
  period", and a contract with no steps says "The contract declares no steps."
- **The engine's rows and keys name a contract by its `id:`, not its module** (plan DD, stage ID4, #178). The
  `contract` column of events, commands, deployments and dependency observations holds `"rehmed.scheduling"`
  where it held `"Rehmed.Contracts.Scheduling"`; so do the keys of subscriptions, relays, inboxes and process managers
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
- **Two contracts of one `id:` across the configured applications, or the siblings they consume, are refused when the engine scans them**
  (plan DD, ID4, #178): `ArgumentError` naming both modules and their applications, at boot or at the first
  dispatch. X7 refuses it within one application at compile time; across applications no compile sees both, and
  since every row and key names the id, the two would share one history.
- **Every contract names its `id:`, and an event's type is `"<id>.<event>"`** (plan DD, stage ID3, #173). A contract
  without `id:` no longer compiles (D11). The type stored with every event changes from `"<process>.<event>"` —
  `"computer.issued"` — to `"<id>.<event>"` — `"appunite_equipment.computers.issued"`. **A host resets the engine's
  schema before upgrading** (`EhOsContract.Migrations.down/up`, or a fresh database), not only the events table:
  subscriptions, the relay, process managers, runs and the commands' idempotency rows all point into the old log.
  Events stored under the old types are not read, and nothing reports them: an aggregate whose stream holds one
  raises, but a boundary, a subscription, a read model and the report skip them silently — a boundary that allows
  one booking per seat would accept a second for a seat booked before the upgrade. No tool converts them (the
  user's decision; rewriting stored types and reading old types as aliases were rejected). Every contract's version moves, so every
  deployment counts as changed, and graphs and reports name events by the new types. Process names stay unique in
  the application: they key their runs.
- **A policy or a read model taking an event of another context declares its `delivery`** (plan DD, stage X1;
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
- **T1: a domain value's invariant may no longer be named `:supplied`** (D9), the word a request's refusal now
  puts where an invariant's name goes, as it already could not be `:required`, `:type` or `:generated`. Rename one
  that was.

- **A blank label no longer compiles.** A label is blank when it is empty or holds only Unicode whitespace and
  invisible format characters (zero-width spaces, direction marks, the byte order mark). N1 refuses one on any
  declaration of a contract, fields included; D1 does the same in a domain; F2 and D3 refuse a blank label of an
  enum member. `event :visit_closed, ""` compiled until now and left a page, a graph's node and a report's
  sentence with nothing saying what the business calls it. An optional label left out still passes, and a struct
  written as data, in a scenario's rows or an invariant's examples, is not checked. An enum member named `true`,
  `false` or `nil` is refused with a label too, as it already was without one. No version moves: a contract that
  compiles is unchanged.
- **W2: a required date or timestamp is tagged with its day when appended, in the domain's zone.** Every required,
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
- **W1: a row of the log carries the schema version it was written with, and newer code's rows wait.**
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
- **N3: a timer has a label.** `timer :documentation_due, wait: {24, :hour}, …` no longer compiles; write
  `timer :documentation_due, "Termin dokumentacji", wait: {24, :hour}, …`. The label names what the timer is for,
  not how long it waits, which `wait:` or `at:` says, and a blank one is refused (N1). A process manager's page
  prints both, the callback's `@doc` and the graph's timer node carry the label, and so do the conformance report's
  and the dashboard's sentences about a timer's step, which named the timer before. **Moves the version** of every
  contract with a timer.
- **N2: another application's event is `subscribe`d to, not `consumes`d.** `consumes "rehmed.visit.closed.v1",
  as: :visit_closed do … end` no longer compiles; write `subscribe "rehmed.visit.closed.v1", as: :visit_closed do
  … end`, the word its capability `<name>.subscribe` already used. `consumes` takes a sibling contract's module only
  and reads its events from this log; a published name given to it is refused by K1, which says to write
  `subscribe` instead. D11 says `subscribe`, and with no list of events to take, it no longer refuses one. The
  model is unchanged, so **no version moves**.
- **N1: an entity declares `identity`, and the library injects it.** `entity :service, "Usługa", context:
  :configuration, identified_by: :service_id` with a `field :service_id, :id` no longer compiles; write
  `identity: :service_id` and drop the field, which the library adds first among the entity's fields as a
  required, non-personal `:id`, as it adds a unit's. An identity some system gives takes `issued_by:` on the
  entity, `identity: :number, issued_by: :ksef`, and the model keeps it on the injected field. D6 refuses an
  identity not in snake_case or declared again as a field; D8 holds an entity's `issued_by:` to the domain's
  externals. **Moves the version** of every domain with an entity, whose model now says `identity`.
- **N1: a scenario names what it is about with `target`, not `scope`.** `scope :remind_on_close` in a
  `scenario` no longer compiles; write `target :remind_on_close`. `scope` stays a command's and a query's,
  where it narrows a grant. S1 says "target". The model's scenario loses its raw `scope` key and keeps the
  resolved `target`, so **the version moves** of every contract with a scenario.
- **N1: a status that ends an aggregate's life is `final:`, not `terminal:`.** `status :closed, "Closed",
  terminal: true` no longer compiles; write `final: true`. `terminal:` stays an event's, where it ends a run of
  the process, so one word no longer means two things in one contract. T3 and T4 and dispatch's refusal say
  "final". **Moves the version** of every contract with a lifecycle, whose statuses carry the key in the model.
- **N1 refuses a query named like an event an actor records**, at the query's line. Both are capabilities named
  `<domain>.<name>` (D14), and since `eh-os` D-73 the manifest offers both. L3's D14 already refused the pair when
  the Mix compiler runs; N1 refuses it in the contract's own compile, before `Model.capabilities/1` could merge
  the two into one capability.

### Removed — a host has to act

- **A process has no `cadence`** (plan DD, P1d, #195; the user's decision). It said how often a run is due
  (`cadence {1, :month}`), and nothing acted on it: the report printed "Due: every …" among the process's
  confirmed declarations, the pages "Cadence: every …", and the check noted an unconfirmed one
  (`unverified-declaration`). A contract that declares it no longer compiles (`undefined function cadence/1`):
  delete the line. The report's `declarations` hold at most the confirmed `deadline`. A process is digested as it
  was with no cadence declared, so no other contract's version moves; one that declared it moves once, when the
  line goes.

## Unreleased — 0.3.0

The move to the second contract DSL (`PLAN.md`, `docs/adr/contract-v2.md`), from E1 to the cut, E11.
**The first DSL is gone**: a contract written with `event`, `payload:`, `trace` and `EhOsContract.Handler`
no longer compiles, and nothing of it is migrated — there was no consumer to migrate. What 0.3.0 is, and
how to write a domain and a contract for it, is in `README.md` and `docs/contract.md`; every key of both
DSLs is in `docs/dsl/`. Until E11, E1–E5 moved no verdict of a first-DSL contract — `mix
eh_os_contract.report` and `graph --overlay --mermaid` gave byte-identical output before and after each —
and from E6 the second DSL ran beside it. The entries below each name their stage.

### Removed — E11a, the first DSL

- `use EhOsContract.Contract` with `event`, `process`, `trace`, `rule`, `example`, `external` and `command`
  keyword declarations, and everything that read them: `EhOsContract.Handler`, `EhOsContract.emit/4` and its
  emitter, `EhOsContract.Job`, handler failures, `EhOsContract.Telemetry`, `EhOsContract.Brief`, the first
  model (`Model.V1`), and the first DSL's findings in `check`, its AsyncAPI projection, report, trace, run,
  graph overlay and deployment rows.
- `mix eh_os_contract.trace` and `mix eh_os_contract.brief`. A promise's verdicts are in the report; a Brief
  for a process owner comes back on the dashboard. `mix eh_os_contract.graph` without a picture flag refuses,
  exiting non-zero with its usage, instead of drawing the first DSL's graph: a script that ran it bare fails.
- The dashboard's "every contract" panel on `/graph`, which drew the first DSL's handler graph.
- **Jobs of `EhOsContract.Job` still in a host's Oban queue have no worker.** Drain the queue before the
  upgrade. A job left behind fails and is discarded, and the handler's work it carried never happens, with
  nothing recording that. Its args hold the event's payload and actor, which erasure does not reach, so after
  draining delete the rows (`worker = 'EhOsContract.Job'`) rather than waiting for a pruner.
- The direct `:telemetry` dependency. It stays in the lock through Ecto and Oban.

### Changed — a host has to act

- **EP4: `idempotency` names its key and its owner.** `idempotency: :event_id` no longer compiles: it is
  `[key: :event_id, owner: :self]`, the owner one of `:self` (the reaction's code keys what it writes),
  `:downstream` (the system an effect calls is given the key) and `:infrastructure` (the engine keys the
  commands a policy or a process manager issues, so the key is `:event_id`). P3 refuses `:downstream` outside
  an effect and `:infrastructure` on one. The callback's `@doc` and the reaction's page say what the owner
  asks of the code. **Moves the version** of every contract with an `idempotency`, which is a map in the model
  and in its export (`eh_os_contract.model.v1`), no longer an atom.
- **#98: a key past 2048 bytes is refused, not failed.** F9's six fields were measured, not proved: a key heavy
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

- **#96: a run and a process manager are told only by an `:id`, and a key has at most six fields.** Two
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

- **#65: a policy on another application's event is a path of the conformance screen. This moves verdicts.**
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

- **What a request controls is bounded where what holds it is.** Past a bound a value does not fit its type:
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

- **Request bytes the log cannot hold are a refusal, not an exception.** Until now Postgres refused to store each
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
      - These were accepted before and are refused now: a space, other non-ASCII UTF-8 such as `zamówienie-1`, a
        key of 256 bytes to 2.7 KB, and an empty `idempotency-key` header.
    - The OpenAPI document gives the header's pattern.
    - A reaction's key is held to it too, since a reaction's actor is a struct any caller can build. The key the
      library derives keeps its form, `<kind>:<contract>:<name>:<event id>:<n>`; one that would break the rule
      (names past what 255 bytes leave, a quoted module) is `<kind>:sha256:<hex>` of it instead.

- **E12c, D12: only a policy takes an event another application publishes.** A read model, an effect or a
  process manager that names a `consumes "<name>"` event no longer compiles: the event arrives in an inbox and
  never enters the log they read, so none of them would ever have been given it. React with a policy, and take
  the event its command records.
- **E12c: V01 creates one more table, `eh_os_contract_inbox`.** V01 is changed in place, as before 0.3.0 is
  first released: a database migrated earlier has no inbox. Recreate it, or create the table V01 now creates.
- **E12c: an `EhOsContract.Bus.Message` has a fifth field, `key`, and it is required.** A transport adapter
  carries it as it carries the id; a test that builds a message gives it one.

- **D11: a domain's `name:` is one segment of an application's namespace.** It begins every name the domain's
  contracts publish and every capability, and nothing checked it: `name: :"acme.billing"` published
  `"acme.billing.x.v1"`, which passed both D11 checks and lies in the namespace of an application `acme`. A
  domain whose name is not lowercase letters, digits, `_` and `-`, starting with a letter and not ending with a
  dash, no longer compiles, even one that publishes nothing, and the refusal points at its `use`. Of the names
  that could publish before, only those with a dot are refused.
- **F1, D3 and D6: a field's name is snake_case, and a value's field is named once.** A contract's fields
  were checked only for uniqueness and a leading `__`, a value's and an entity's only for uniqueness (an
  entity's) or not at all (a value's): `field :"Invoice No"` became a key of the typespec, the JSON Schema and
  the page, `:"a|b"` broke the unit graph's edge it labelled, and a value's field declared twice gave the JSON
  Schema the later definition with the earlier one's `required`. A unit's `identity` is held to the same,
  named once, at the unit: `identity :"a|b"` reached a graph edge and a page table through `consults`. A
  contract or domain declaring such a field no longer compiles.
- **N1: two names that camelize alike are refused where they become one module or alias.** N1 compared names
  exactly, so `event :visit_closed` beside `event :visit_closed_` compiled, with a warning that
  `<Contract>.Events.VisitClosed` was redefined: one event carried the other's struct. The same held for a
  command, event or consumed event (an implementation aliases each as `<Camelized>`) and for two aggregates,
  dcbs, reactions, read models, queries or domain services of one kind. N2 compares `:state` and `:row`, the
  aliases of a unit's state and a read model's row, camelized too, so `command :state_` is refused. A contract
  that declared such a pair no longer compiles.
- **D1: a subdomain's, context's, subject's, value's, entity's and external's name is snake_case.** They were
  held only to uniqueness: `value :"a/b"` generated `<Domain>.Values.A.B`, a module nested in another, and
  `context :"front desk"` broke the context map's diagram; `mix eh_os_contract.pages` refused such a name, but
  only when it ran. Two values whose names camelize alike (`:money_amount`, `:money_amount_`, `:money__amount`)
  generated one module of invariants once either had one, and are now refused as two of one name. A value
  named after a type Elixir builds in (`:map`, `:bool`), whose `@type` failed to compile with an error pointing
  at the library, and one named after a built-in field type (`:date`, `:id`), which a field of that type
  silently meant instead, are refused with a code. A domain that declared one no longer compiles. Field names
  are not covered.
- **D4: an actor's name is snake_case.** A person's is a role, `<domain>.<actor>`, in the manifest EHOS
  reads, and nothing checked its form: `actor :"*", :human` in a domain `acme` was the role `"acme.*"`, and
  `:"billing.clerk"` a role of two segments. A system actor is held to the same form, since `by:` names it as
  it names a person. A domain that declared one no longer compiles.
- **N1 and D9: a name ending in a newline is refused, and so is a decimal in scenario data.** Their patterns
  ended in `$`, which also matches before a final newline: `command :"pay\n"` compiled, and its capability
  `"<domain>.pay\n"` reached `EhOsContract.Model.capabilities/1`, the OpenAPI document and the EHOS manifest.
  The same held for a value invariant's name and a scenario's decimal written `"12.50\n"`: a contract or a
  domain that declared one no longer compiles. `mix eh_os_contract.pages` refuses a page named after a
  domain's element ending in a newline, as it refuses one with a space.
- **D11: a published or consumed name ending in a newline is refused.** The pattern ended in `$`, which
  also matches before a final newline, so `"rehmed.visit.closed.v1\n"` compiled; on a broker such a name
  breaks the subject line. A contract that declared one no longer compiles.
- **E11f: a unit reads only what its `evolve/2` folds.** When every clause of `evolve/2` that does not name
  an event is exactly `def evolve(state, _), do: state`, dispatch decodes only the events it names. A
  boundary's query and its conflict condition narrow to those types, so appending an event it passes
  over no longer conflicts with its decisions, and its commands' `given_types` list only folded types —
  unless it folds none of its events, when it reads and conflicts on all of them as before, since a store
  query cannot be empty.
  Scenario coverage compares a scenario's `given` on the folded types too, so no verdict moves for a
  scenario that names an event the unit passes over. A row of a passed-over type that no longer fits its
  declaration no longer stops the stream; a type the contract no longer declares still does.
- **E11f: an idempotency key belongs to the actor who sent it.** Dispatch looks an accepted key up by the
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
- **E11b: the second DSL takes the first one's names.** `use EhOsContract.Next.Contract` is
  `use EhOsContract.Contract`, and every `EhOsContract.Next.*` module drops `Next`. `Registry.v2_contracts/0`
  is `Registry.contracts/0`, and the scan's key `graph().v2_contracts` is `graph().contracts`;
  `Check.v2_findings/1` is `Check.findings/1`; `Deployment.v2_edge_labels/1` is `Deployment.edge_labels/1`.
  **`Registry.contracts/0` and `Check.findings/1` existed before and meant the first DSL's contracts**: a
  call written before E11 still compiles, and now gets the second DSL's.
- **E11c: the engine's storage is one migration.** `EhOsContract.Migrations.current_version/0` is 1, and V01
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
- **E11a: R2 refuses a process with `correlate []`, and P4 a process manager with `correlate: []`.** Both
  compiled, and then every event of the contract joined one run — the report counted one run for everything
  — and every run of the manager shared one record, state and set of timers.
- **E11a: an empty `:id` is refused**, at dispatch (`{field, :type}`) and in scenario data at compile (S3), as
  an entity's id is. The log read back still accepts one, so what is already written keeps reading.
- **E11a: a promise can be suspended.** `EhOsContract.Dependency.unavailable!/4` takes a contract with an
  event that `depends_on` the external, where it accepted only a first-DSL contract, so an outage recorded
  inside a promise's window now suspends it instead of counting as a violation. `Dependency.observe/3`
  records an outage of an external the contract only `calls:`, where it raised; such an observation
  suspends nothing, since promises read only `depends_on` events.

- **E10: `EhOsContract.Model.to_data/1` publishes the v2 model under the named schema
  `eh_os_contract.model.v1`.** The JSON-ready document includes the contract, its domain, derived human
  capabilities and a digest of that projection. Its declaration and example structure is complete, but
  personal values in scenarios, rule examples, invariant examples and defaults are `null`: the public model
  is not a second store for fixture data. A scenario's event is redacted by the fields of the contract that
  declares it, so a consumer's scenario on a sibling's event does not publish that sibling's personal
  values. What no declaration covers is `null` rather than verbatim: the data of an event or command
  that cannot be found, a query's answer without its read model, a key no field declares, and a
  structured value's example that is not a map but holds a personal field.

- **E9c: a command may be scoped, as a query is (D10).** `command :x, "…", by: :actor, scope: :field` names one
  of its fields; `EhOsContract.Model.capabilities/1` gives the command's capability that `scope:` instead of
  `nil`, and dispatch — and `EhOsContract.Plug` — ask the `Authorizer` with the field's value. A credential
  granted a scoped command without values for its dimension is refused `:unscoped_grant`, as for a query, so a
  host granting one has to send the values (`scp`).
- **E9a: an event a contract records has a capability, and a credential records with it.**
  `EhOsContract.Model.capabilities/1` gives each event declaring `recorded_by:` the capability
  `<domain>.<event>`, kind `:record`, with the roles of its `recorded_by:` actors; `EhOsContract.record/3` asks
  the `Authorizer` for it, as `dispatch/3` does for a command, instead of refusing every credential with
  `{:error, :not_grantable}`, which is gone. `EhOsContract.Plug` serves it as `POST <mount>/records/<capability>`,
  and answers a recording for a unit no command created (`{:error, :not_created}`) with 404 `{"error":
  "not_created"}`.
  A host that checks every capability has an entry point (`EhOsContract.Auth.Testing`, `eh-os` D-34) maps the
  recordings too; D14 now also refuses a recorded event named like another declaration's capability.
- **E9a: only what a person may do is a capability.** `EhOsContract.Model.capabilities/1` gives a command, a
  query or a recorded event a capability only when its `by:` or `recorded_by:` names a `:human` actor, and its
  roles are those people only. A command only a reaction issues (no `by:`) and an event only a `:system` actor
  records have none: a credential naming them is refused `:missing_capability`, and `EhOsContract.Plug`
  answers 404. A host's entry-point check drops them; the application's own `:system` actor reaches them as
  before.
- **EG1: `EhOsContract.Graph.steps_to_mermaid/2` is `contract_to_mermaid/2`**, and draws a v2 contract's full
  graph (below). A caller renames the call; the options (`overlay:`, `since:`, `until:`) and the steps' nodes and
  edges are the ones they were.
- **EL2b: a domain service's `rule` needs `examples:`**, `rule :never_below_zero, "…", examples: [{[1, 3],
  0}]` — the arguments in the order the function takes them, then the result. A rule without one fails the
  compile (S9), and so does an example of the wrong arity or types (S9, X9 for domain values). Each example is a
  test in `use EhOsContract.ScenarioCase, contract: C`, run through `C.DomainServices.<Name>`.
- **EL2b: N2 refuses a callback named after a function every module defines** at its arity: an event
  `:module_info` (its handler would define `module_info/1`) fails the compile, as a domain service's function
  of that name already did.
- **EL2: a subdomain is named, and a context names it.** `subdomain :visits, "Wizyty", type: :core` in the
  domain, then `context :scheduling, …, subdomain: :visits`; `subdomain:` on a context no longer takes the kind,
  and a name the domain does not declare fails the compile (D7). A domain keeping its old contexts can declare
  `subdomain :core, "…", type: :core` and leave them as they are. Every domain's version moves.
- **EL2: a translation needs its `definition:`**, as in ESDM: `translation :en, "Completed", definition: "…"`;
  one without fails the compile. A translation may name words to `avoid` in its language, and an `avoid` may
  give its `reason:`. `mix eh_os_contract.glossary --language` prints them.
- **EL1: `mix eh_os_contract.check` prints two lines a finding**, `LEVEL <rule>: <sentence>` and then where the
  declaration was written (v2 contracts) and the rule's entry in `docs/rules.md`. A script reading the old
  one-line output reads the first line of each pair; one reading it by program should move to `--format json`.
- **E8b: a read model that projects personal data needs `forget/2`**; without it, the `EhOsContract` child
  refuses to start, since an erased subject's data would stay in its tables.
- **E8a: a host whose contract declares personal fields needs a master key**, `config :eh_os_contract,
  EhOsContract.Vault, keys: [...]` (`README.md`); without one, the `EhOsContract` child refuses to start. A host
  without personal fields configures nothing.

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
- **EM1: an `EhOsContract.Store` implementation of the host's own needs `read_query/2`**, and its `append/3`
  takes a third condition, `{:dcb, query, after_position}`, refused with `{:error, :condition_failed}`
  (v2 §10.1). `EhOsContract.Store.Suite` checks both. `EhOsContract.Store.Postgres`, the default, has them.
- **EM1: an appended event is tagged with every required, non-personal `:id` field it carries**, not only its
  unit's identity: `["account_id:a-1", "branch_id:b-7"]` where it was `["account_id:a-1"]`. A consistency
  boundary finds what it consults by these tags, so a `match:` names only such fields (A4 for a local event,
  X6 already for a sibling's). Events appended before this version carry the narrower tags.
- **EM1: a command's row in `eh_os_contract_commands` lists each type it was given once** (`given_types`), in
  the order first read, where it listed one entry per event: a boundary may read the whole history of a type.
  Scenario coverage compares these as sets, so no count moves.

### Added

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
  a rule finer than the status (AppUnite's `:for_sale_not_issued`). Without such a rule it is still refused, and
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
  [{"Wizyta", "Wizyta"}]` — the word of the first end (upstream, or the first of `between:`) and of the
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
  by its capability's name (`{:command, "rehmed.record_payment"}`), with the data as a caller sent it and a
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
  framed by its length, as its key, or its id when the publication declares none (`eh-os` FM-04, FM-08). A message that does not fit what
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
- **EL2: a directed relation may end at an external system**, `relation :conformist, upstream: :ksef,
  downstream: :settlement`, with the other end a context (D5); a name both a context and an external fails the
  compile (D1). `orphan-external-system` counts a relation's end as a use, and `orphan-context-mapping` counts a
  relation to an external as crossed when a contract of its context calls it, depends on it or acts through an
  actor it backs.
- **EL2: `issued_by:` on a field**, the domain external that gives its value (a number P1 or KSeF assigns):
  `field :p1_report_id, :id, issued_by: :medical_event_registry`, with an entity reference too. An unknown
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
  changes — `entity :period, "Okres", context: :client_month, identified_by: :period_id do field … end`. A field
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
  the DSL refuses to compile is not repeated. The sandbox gains one warning (`Rehmed.Contracts.VisitSettlement`
  has no `accountable`), which E6's port had taken out of the output.
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

- `mix eh_os_contract.check` prints its findings in a fixed order: errors, warnings, notices, each by text.
  The lines are the same.

### Fixed

- **An append waits only for appends to the same log.** The append lock had one fixed key, and an advisory
  lock belongs to the whole database: where applications share one, each in a schema of its own, as EHOS
  keeps them (`eh-os` D-54), every application's appends waited for every other's. V01's lock now has two
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
- **The storage works in a schema other than `public`** (issue #51; `eh-os` D-54, D-56).
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
