# Contract v2 — the starting assumptions

**What version two of the library is being built to be, stated before it is built.** Decided with the
product owner on 25 September 2026; the plan that executes it, stage by stage, is [`PLAN.md`](../../PLAN.md),
"Dopisek 25 września (2) — Etap 6". Like [architecture](architecture.md) was for v1, this file is a premise
to validate, not a record awaiting acceptance. Where code proves an assumption wrong, the correction goes
here, dated, under the original sentence — never instead of it. Where this file and `PLAN.md` disagree,
`PLAN.md` is newer.

Code comments cite this file as `v2 §N`, which is why the numbering is stable.

[Architecture](architecture.md), [design rationale](design-rationale.md) and
[technology notes](technology-notes.md) stay the record of v1's assumptions. The claims of theirs that v2
reverses are listed in §18, each with the stage whose code confirms the reversal. They get their dated
corrections then, not before.

## 1. Why v2

v1's contract says *what happens* — events, runs, stages, timed assertions — and checks a log against it.
It does not say what must stay consistent under a write (aggregates, dynamic consistency boundaries), what
is read (read models, queries), where the boundaries run (contexts and their relations), or who may do what
(capabilities). And its compiler checks names, not implementations: a payload is a map validated at run
time, and a rule is a function referenced by MFA.

The evidence is the repository's own test data. `PLAN.md`, "Dopisek 25 września", maps the four sandbox
contracts onto ESDM's vocabulary:

- 12 of the 36 v1 keys have an ESDM counterpart; the other 24 are the verification layer.
- 15 of 29 events have no command that publishes them.
- Almost everything ESDM requires and the contracts lack — contexts with subdomains, context maps,
  aggregates with invariants, actors, read models — already exists in both clients' workshop material.
  Distillation dropped it because the DSL had nowhere to put it.
- The Rehmed model filed two timed promises as invariants, for the same reason.

## 2. Direction and decisions

| Question | Decision (25 September 2026) |
| --- | --- |
| Reference | ESDM (Event-Sourced Domain Modeling, esdm.io, v0.15.0) is the **specification of functionality** v2 copies: its concepts, its validation rules, its tooling (view, glossary, documentation). **No integration**: no YAML, no export, no dependency on its schema versions. The contract stays an Elixir module and the single source — architecture §2 holds. |
| Verification | kept, because ESDM has none: runs, stages, terminal events, timed promises, deadline, cadence, `unverified`, `accountable`, dependency outages as `:suspended`, the contract version on every event, the conformance report |
| Scope | the whole pivot, in stages (E0–E11 in `PLAN.md`) |
| State | **event sourcing now**: the log is the source of truth, aggregate state is rebuilt from it |
| DSL engine | **Spark** (`~> 2.7.3`, MIT, no runtime dependencies), without a comparative spike; E3 pins the properties v2 relies on |
| Event store | **our own, in the library's Postgres**, behind `EhOsContract.Store` — accepted after comparison with Commanded's EventStore (table below) |
| Personal data | **crypto-shredding** (§14), replacing `retain: :hash / :drop` |
| Compatibility | none: every contract in the repository is test data |

**Own store against EventStore.** EventStore v1.4.8 (MIT, Postgres) has streams with `expected_version`, an
`$all` stream, persistent subscriptions with checkpoints and acks, competing consumers, snapshots, links,
Postgres schemas, and accepts an existing Postgrex connection or transaction as `:conn`.

| | Own | EventStore |
| --- | --- | --- |
| One transaction with inline projections and the Oban outbox | yes — the Ecto transaction `Emitter` opens today | via `:conn`, but Oban and our projections go through Ecto, and there is no public API to get the Postgrex connection under an Ecto transaction |
| Dynamic consistency boundaries (PayerSettlement; opening a month by hand) | yes — an append condition over types, tags and position | no; a boundary stream with links works only for boundaries known in advance |
| One log for conformance | yes | rewrite every conformance query onto its tables, or keep a second log |
| Migrations | ours, Oban-style (`EhOsContract.Migrations`) | its own `event_store.create/init/migrate` and schema |
| Concurrency, ordering, subscriptions, snapshots | to build (E2, E7) | built and proven |

The last row is the price, bounded by the `Store` behaviour and a store test suite any implementation must
pass. Realistically the swap the behaviour enables is another Postgres layout, not another database: a
store outside Postgres would lose inline projections and the transactional outbox.

## 3. The flow v2 serves

In the product owner's words, turned into requirements:

1. Workshops produce material; the material is used to build a contract written in Elixir.
2. The contract compiles, so its structure is held firmly.
3. The application is implemented from the contract, and the contract is built into it.
4. The compiler makes sure the implementation matches the contract.
5. At run time events are collected, and the library checks that the application does what was intended.
6. Graphs like EventCatalog's are generated from contracts.
7. **One contract describes one process.**
8. Contracts combine into larger schemes that show the complete system.
9. Contracts define capabilities and access for users and services.
10. **A change to an event's structure in one process is verified by the compiler at every subscriber**,
    so the change is reflected there and consistent (§7).
11. The whole is consumed by EHOS; an API will be needed later.

> *Changed 6 October 2026, plan DD, P1c, in the programme the user approved on 5 October.* **Requirement 7
> reads "one contract describes at most one process".** A contract is first the units of one context that
> decide and record; a process is a run with steps and an end, and not every part of a business has one. An
> equipment register — a computer bought, issued, returned — has a lifecycle per computer and no run, and the
> test material gave such contracts an invented process only because R1 refused a contract without one. R1 now
> refuses a second process, and, in a contract without one, what belongs to a run: a unit's `stage` group and a
> `terminal:` event. Two processes in one contract stay refused: requirement 8 combines contracts, not
> processes inside one. ([#190](https://github.com/EmpoweredHouse/eh-os-contract/issues/190))

## 4. The DSL

### 4.1 Two modules

- **`use EhOsContract.Domain, name:, language:`** — one per application: the vocabulary contracts share.
  Contexts with their subdomain and glossary, relations between contexts, actors, value types, subjects of
  personal data, external systems.
- **`use EhOsContract.Contract, domain:, context:`** — one process. Everything that is born in that
  process: aggregates or boundaries with their state, invariants, commands and events; policies, effects,
  process managers, read models and queries; the process itself with its stages and promises; scenarios.
  Facts born elsewhere enter through `consumes`.

Both are Spark DSLs with one top-level section each, so entities are written directly in the module body.
The vocabulary is closed: users cannot add extensions.

### 4.2 Entity reference

`!` required, `*` repeatable, `=` default.

```
DOMAIN   use EhOsContract.Domain, name!: atom, language!: atom
context  name!, label!      subdomain! :core|:supporting|:generic · language · source          [term*]
  term   text!, definition! source                                          [translation*, avoid*]
actor    name!, kind!, label!  kind :human|:system · backed_by [external] (system only) · context
subject  name!, label!      a kind of person whose data may be erased (§14)
value    name!, type?       unit · label · context · [field*]            exactly one of type | fields
external name!, label!      direction! :inbound|:outbound|:bidirectional · unavailable_looks_like · expected_latency
relation type!              upstream + downstream | between [a, b] · terms       (8 mapping types)
entity   name!, label!      identified_by! · [field*]              deferred: nothing reads it yet
field    name!, type!       optional=false · label · personal (id field) · subject · default (state only)

CONTRACT use EhOsContract.Contract, domain!: module (no compile dependency), context!: atom
aggregate name!, label!     source       [identity!, state?, invariant*, command*, event*, stage*]
dcb       name!, label!     source       [identity! (list), consults+, state?, invariant*, command*, event*, stage*]
  consults event!           match [fields] | where "prose"
  invariant name!, label!   source
  command  name!, label!    by [actor] · emits! · rejects · source                     [field*]
  event    name!, label!    terminal=false · public=false · depends_on external · recorded_by [actor]
                            · schema_version=1 · source                                [field*]
  stage    name!            groups the unit's events into a stage of the process        [event*]
policy          name!, label!  handles! · issues! · delivery=:in_transaction · idempotency
effect          name!, label!  handles! · calls [external] · delivery=:at_least_once · idempotency
process_manager name!, label!  correlate! · delivery=:at_least_once · idempotency
                               [state?, starts_on+ (sets, issues), on* (issues, sets, cancels),
                                timer* (wait | at; issues), ends_on*]
read_model      name!, label!  projects! · delivery=:in_transaction                     [field*]  (row)
query           name!, label!  reads! · by · returns=:many|:one                         [field*]  (params)
consumes        contract! (no compile dependency), events!   as: [old: :new]
process         name!, label!  correlate! · accountable actor                          (exactly one)
                [stage* (name!, label?; [include*]), include* (event!, terminal), cadence? ({n, u}, unverified),
                 deadline? ({n, u}, unverified), promise* (name!; from!, eventually!, within, or_else, unverified, source)]
scenario        description!   scope · actor
                [given* (event!, %{}), command | on | query (name!, %{}), expect* (event!, %{}),
                 rejected invariant, issues*, sets*, cancels*, ended]
```

> *Changed 27 September 2026, plan EL2, the user's choice.* **A subdomain is named.** `subdomain name!, label!
> type! :core|:supporting|:generic · source`, and a context's `subdomain!` names one of them (D7) instead of
> giving the kind itself, as `entity …, context:` names its context. ESDM's subdomain lists its contexts
> instead; the user chose the other direction, so that the context says where it belongs. §4.5's domain is
> compiled with the two subdomains it needs added (`contract_examples_test.exs`, `@amendments`).
>
> *Changed 27 September 2026, plan EL2, the user's choice.* **A translation says what the term means in its
> language and what to avoid there**, as in ESDM: `translation language!, text!, definition! [avoid*]`, and
> `avoid text!, reason` at a term and at a translation.
>
> *Changed 27 September 2026, plan EL2, the user's choice.* **An end of a directed relation may be an external
> system**, under the same keys, as ESDM allows: `relation :conformist, upstream: :ksef, downstream: :settlement`.
> The other end is then a context, a symmetric relation joins contexts only, and D1 refuses a name that is both a
> context and an external.
>
> *Added 27 September 2026, plan EL2, a question the user added after EM.* **A field may say which external
> gives its value:** `field :p1_report_id, :id, issued_by: :medical_event_registry`, in a contract (X4) and in a
> domain's value or entity (D8). It composes with an entity reference, `field :invoice_number, {:id, :invoice},
> issued_by: :ksef`, which is why it is an option and not `{:id, :ksef}`. ESDM has no such field. An external
> identifier that is personal data (a PESEL, a patient's number at a payer) is still never an `:id` (§14).
>
> *Added 28 September 2026, plan EL2b, the user's choice of 27 September.* **A value's invariant is checked, and
> shown on examples:** `value :money, :integer do invariant :not_negative, "…", violated_by: [-1],
> satisfied_by: [0, 15_000] end` — both lists required, each example plain data of the value's type, as a
> scenario's is. The domain generates a behaviour, `D.Values.Money`, with one callback per invariant, `(value) ::
> boolean`, and a module bound with `use D, value: :money` defines each (I1, I2). Dispatch holds every value of
> the type to them (§11), and `use EhOsContract.ScenarioCase, domain: D` writes a test per example. ESDM's
> value-object invariants are prose; this is the library's addition, in the shape the aggregate's invariant already
> had.
>
> *Changed 5 October 2026, plan DD, X1.* **`delivery=:in_transaction` of a policy and a read model is a default
> only within a context.** One that takes an event of a sibling contract of another context declares `delivery`
> (X10, L3): left out, it would run in the transaction that records the other context's fact, and its failure
> would roll that fact back — two contexts committing together without the contract saying so. A declared
> `:in_transaction` there compiles, and `check` warns of it (`in-transaction-across-contexts`). Left out within
> one context, it is still `:in_transaction`, and the version does not move.
>
> *Changed 6 October 2026, plan DD, ID1.* **A contract may name itself: `use EhOsContract.Contract, domain!, context!,
> id`.** `id` is the domain's `name:`, then dotted snake_case segments, unversioned (`"rehmed.settlement"`), at most
> 100 bytes, no segment a version (D11, L2), under the domain's namespace (D11, L3) and unique in the application
> (X7). Its identity until
> now came from the module and the process's name; `id` is the step towards an identity a rename of either does not
> move. Optional in ID1 and outside the version; ID3 makes it required and the prefix of event types, which
> amends D1 (§16).
>
> *Changed 7 October 2026, plan DD, P1d, the user's choice of 6 October.* **A process has no `cadence`.** It said how
> often a run is due (`cadence {1, :month}`), and nothing acted on it: the report and the pages printed it, and the
> warning it was declared for, a due run that never started, was rejected on 6 August, since it needs to know which
> runs should exist and the log sees only what was recorded. A contract that declares it no longer compiles. A
> process is digested as it was with none declared, so no other contract's version moves. It comes back with a
> reader that knows what should exist. ([#195](https://github.com/EmpoweredHouse/eh-os-contract/issues/195))
>
> *Added 7 October 2026, plan DD, P2b, in the programme the user approved on 5 October.* **A process may be a
> module of its own:** `use EhOsContract.Process, id!:, label!:, domain!:` (`accountable`, `source`), with `correlate`,
> `stage name, label, include: [{Contract, event | [events]}]`, `ends_on [events]`, `promise` and `deadline`. It names
> contracts without a compile dependency, as `consumes` does, and gathers their events into one run: a clinic's
> visit runs through booking, documentation, reporting and settlement, four contracts, and belongs to none of them.
> It reuses the contract's codes (D11, N1, R2, F9, R3, R5, R6) and adds one rule: a `deadline` needs `ends_on`, since
> a deadline measures a run to its end. §4.1's "one process" per contract is the step before; the `process` block in a
> contract goes in P2h. ([#205](https://github.com/EmpoweredHouse/eh-os-contract/issues/205))
>
> *Added 7 October 2026, plan DD, P2c.* **A process module's runs are filed under its `id:`.** The links compiler
> checks the module against the contracts it names (X1, X2, X5, X6, X7, and the id's domain prefix under D11), and
> dispatch writes a row of `eh_os_contract_event_runs` for every process module that includes the event, its process
> column the module's id (`"rehmed.clinical_visit"`), where a contract's process is filed under its short name. The
> id is namespaced and survives renaming the module, the reason contracts' rows moved to ids in ID3–ID4; a process
> that moves from a contract into a module therefore starts its runs afresh under the new key.
> ([#210](https://github.com/EmpoweredHouse/eh-os-contract/issues/210))

- **Identity is injected.** A unit's identity fields appear in its state, commands and events without being
  declared there; declaring one again is an error.

  > *25 September 2026, E5:* a process manager's `correlate` fields are injected into its state the same way,
  > unless the state declares them. Its timer's callback receives the state alone, and without the run's
  > correlation it could not name the visit its command is about.
- **Stage membership is nesting.** Local events sit inside `stage :payment do … end` in their unit; foreign
  events are placed with `include` inside `process`. The order of `stage` entries in `process` is the order
  of stages.
- **Durations.** `within`, `deadline` and `wait` accept only the fixed units of `EhOsContract.Duration`;
  `cadence` may also use calendar units.

> **25 September 2026, E3 — options cannot sit beside a `do` block.** Elixir parses
> `command :x, "L", by: [:a] do … end` as four arguments: name, label, the keyword list, and `[do: …]`.
> A Spark entity macro takes its positional args plus one options argument, so that call does not compile
> (`undefined function command/4`). With a block, options are written inside it:
> `command :x, "L" do by [:a]; emits [...]; field … end`. Without a block, the trailing keyword list works
> as written. Most examples in §4.5 and §4.6 put options beside a block. The domain entities built in E3
> follow the rule, and E4 has to choose between rewriting the examples that way and generating wrapper
> macros of one more arity. The question goes to the user before E4. *Decided the same day: wrapper macros
> (D13, §16); the examples stand as written.*

> **25 September 2026, after E1 — D10 and D11 (§16) change this reference.** `query` gains `scope`, and
> `param` replaces `field` for its parameters; `actor` gains `scope: [field]`. `event … public:` retires:
> `consumes Contract, events` stays for a sibling process in the same application, and between applications
> an event crosses only through `publish` and `consumes "<name>"`. The table above is left as it was
> written; E4 and E5 build to D10–D12.

> **27 September 2026, EM2.** `entity` is no longer deferred: ESDM coverage came before the sandbox contracts
> (plan, "Po E8 — kolejność zmieniona"), and what reads an entity is the field that names it. The user
> decided both shapes: an entity is declared in the domain, beside `value`, with the context that owns it
> (`context:` required, `identified_by:` one of its fields, a required non-personal `:id`); and a field names
> one as `{:id, entity}`, which the model stores as `type: :id, refers_to: entity`, so the codec, tags and
> typespecs see a plain `:id`. No field of an entity is personal: its rows are the application's, outside the
> log, where erasure cannot reach them. Rules: D6 in the domain, X3 in a contract.

> **27 September 2026, EM2 — a domain service.** ESDM's `domain-service` was the one core kind the four
> contracts did not need (the 25 September mapping), and it came with the coverage the user asked for. It is
> declared in the contract, `domain_service :name, "label" do function :f, "label" do argument …; returns …;
> rule … end end`, and bound like every other kind, `use C, domain_service: :name`. What reads it is the
> module the contract generates, `C.DomainServices.<Name>`: a decision calls the function there, which holds
> the arguments and the result to their declared types and raises on a mismatch (the user's choice over a
> compile-time check alone). No scenario targets it; ESDM has none for it either.
>
> *Added 28 September 2026, plan EL2b, the user's choice.* **A rule of a domain service is shown on examples, and
> they are required:** `rule :never_below_zero, "…", examples: [{[1, 3], 0}]` — the arguments in the order the
> function takes them, then the result, as plain data. S9 refuses a rule without one, and an example of the wrong
> shape or types; X9 checks the values of domain types. `EhOsContract.ScenarioCase` makes each a test that calls
> the function through `C.DomainServices.<Name>`, so its types and its values' invariants are held too, and
> compares the result as a value. This is where a scenario of a domain service would have been.

> **27 September 2026, EM3 — a generated identity.** ESDM's `identifiedBy: {source: generated}` is written
> `identity :booking_id, generated: :uuid` on an aggregate, with `creates: true` on the command that makes
> one (the user's shapes). Dispatch gives that command a UUIDv7 and the receipt returns it; a creating command
> that brings its own is refused, since two ways of making an identity would be one too many. A boundary has
> no generated identity: its identity comes from the command, as ESDM's `command-payload` source does. The
> generator is **UUIDv7**, whose first 48 bits are the creation time to the millisecond: whoever holds an
> identity — in a stream id, a tag, a URL — learns when it was made, and erasure leaves it, as §14 leaves
> every identifier. Chosen over v4 for index locality in the log's `stream_id`; the rest is 74 random bits,
> so identities are not guessable.

> **5 October 2026, plan N1 — one word, one meaning, in both DSLs.** The reference above is left as written;
> three of its words changed. A **status** that ends an aggregate's life (plan LC1, after this reference) is
> `final: true`, not `terminal: true`: `terminal:` is an event's, where it ends a run of the process, and the two
> meant different things in one contract. A **scenario** names the unit or reaction it is about with `target`,
> not `scope`: `scope` is a command's and a query's, where it narrows a grant, and the model already called the
> resolved declaration the scenario's `target`. An **entity** (EM2 above) declares `identity: :service_id`, not
> `identified_by: :service_id` beside a field of that name: the library injects the field, a required, non-personal
> `:id`, as it injects a unit's identity, and an identity some system gives says so on the entity with
> `issued_by:`. The entity is one in Evans's sense — a thing with an identity whose lifecycle the application's code
> or another system keeps, outside this log — and contracts point at it by that identity; EM2's "reference data"
> was a narrower word for the same declaration.

> **5 October 2026, plan N2 — `consumes` for a sibling, `subscribe` for another application.** `consumes` named two
> mechanisms: a sibling contract's events, read from this log (`consumes Module, [:event]`), and another
> application's published event, taken into an inbox by a policy only (`consumes "<name>", as: …`, D11, D12). The
> second is now `subscribe "rehmed.visit.closed.v1", as: :visit_closed do … end`, the word its capability,
> `<name>.subscribe`, already used; `consumes` takes a module only. The examples below that write `consumes "<name>"`
> are left as written.

> **5 October 2026, plan N3 — a timer has a label.** `timer :chase, "Termin dokumentacji", wait: {24, :hour}, …`:
> required and positional, as every other declaration's, and naming what the timer is for, never how long it
> waits — `wait:` or `at:` says that. §4.6's example below is left without one; its compiled copy adds it.

### 4.3 Field types and options

- Built-in types: `:id :string :integer :decimal :boolean :date :timestamp {:enum, [...]} {:list, t}`, plus
  the name of a domain `value`. Every built-in type names a shape, never a thing — a domain type is a
  `value` in the client's domain module, so `:money` belongs to Rehmed, not to the library. `:string` still
  means text a human typed, and `check` still reacts to it.
- Enum members are atoms, optionally with a label: `{:enum, [card: "Karta", cash: "Gotówka"]}`.
- `optional: true` is legal, except on a field used as identity, correlation, `match` or a tag.
- `default:` only in `state`.
- `personal: :patient_id` marks a field as personal data of the subject whose identifier is in the named
  field of the same struct; that field declares `subject: :patient`, a `subject` of the domain (§14).
- A value with one type and a unit (`value :money, :integer, unit: :grosze`) is how a number says what it
  counts — the gap VisitSettlement's moduledoc records and today closes with the `_minor` suffix.

### 4.4 Names Elixir reserves

`when`, `after`, `do`, `end`, `fn`, `and`, `or`, `not`, `in`, `else`, `catch`, `rescue` cannot be macro
names; `then` clashes with `Kernel.then/2`; `for` is a special form; `boundary` reads as the `boundary`
library. Hence `expect` (not `then`), `command` / `on` / `query` as scenario triggers (not `when`), `wait:`
(not `after`), `scope` (not `for`), `dcb` (not `boundary`). Scenario data is a map, because Spark reads a
trailing keyword list as options. A command, event or timer whose callback would clash with a Kernel
function at the same arity (a command called `:send`) does not compile.

### 4.5 A complete example: Rehmed VisitSettlement

This rewrites `sandbox/lib/rehmed/contracts/visit_settlement.ex` and `sandbox/lib/rehmed/settlement.ex`. It
translates rather than fixes: the port keeps what the v1 contract says, including the contested handoff.

```elixir
defmodule Rehmed.Domain do
  @moduledoc "Vocabulary shared by Rehmed contracts: contexts, actors, value types."
  use EhOsContract.Domain, name: :rehmed, language: :pl
  use Boundary, deps: [EhOsContract], exports: [{Values, []}]

  context :scheduling, "Umawianie i zasoby", subdomain: :core           # CTX-01
  context :settlement, "Rozliczenia", subdomain: :supporting            # CTX-05
  relation :customer_supplier, upstream: :scheduling, downstream: :settlement

  actor :reception, :human, "Recepcja"          # A-02
  actor :specialist, :human, "Specjalista"      # A-03
  actor :manager, :human, "Menedżer"            # A-05

  value :money, :integer, unit: :grosze, label: "Kwota"
  value :payment_method,
    {:enum, [card: "Karta", cash: "Gotówka", transfer: "Przelew", voucher: "Bon"]}   # AGG-06
end
```

```elixir
defmodule Rehmed.Contracts.VisitSettlement do
  @moduledoc "(carried over from v1, in English)"
  use EhOsContract.Contract, domain: Rehmed.Domain, context: :settlement

  aggregate :visit_settlement, "Rozliczenie wizyty" do
    identity :visit_id

    state do
      field :total, :money, optional: true
      field :payments, {:list, :money}, default: []
      field :handed_over_on, :date, optional: true
    end

    invariant :payment_lines_sum_to_total, "Linie płatności sumują się do wartości rozliczenia",
      source: "W1 02:02:07; AGG-03 niezmiennik 1"

    command :add_service_line, "Dodanie usługi do rozliczenia wizyty",
      by: :specialist, emits: :service_line_added,
      source: "Event model §4, C-23, aktor A-03; W2 00:51:18" do
      field :service_id, :id
    end

    command :hand_over_visit, "Oznaczenie wizyty jako wykonanej",
      by: :specialist, emits: :visit_handed_over,
      source: "Event model §4, C-68, aktor A-03; Appunite 2026-08-17" do
      field :total, :money          # F1, §16
    end

    command :record_payment, "Przyjęcie płatności za wizytę",
      by: :reception, emits: :payment_recorded,
      source: "Event model §4, C-31, aktor A-02; ESB L8" do
      field :method, :payment_method
      field :amount, :money
    end

    command :close_settlement, "Zamknięcie rozliczenia wizyty",
      by: :reception,
      emits: [:visit_closed_commercially, :visit_closed_without_payment],
      rejects: :payment_lines_sum_to_total,
      source: "Event model §4, C-30, aktor A-02; H28"

    command :book_correction, "Zaksięgowanie korekty rozliczenia",
      by: :reception, emits: :settlement_corrected,
      source: "Event model §4, C-46, aktor A-02; process 10" do
      field :delta, :money
    end

    stage :charging do
      event :service_line_added, "Dodano usługę do rozliczenia wizyty" do
        field :service_id, :id
      end

      event :visit_handed_over, "Wizyta oznaczona jako wykonana i gotowa do rozliczenia" do
        field :total, :money
      end
    end

    stage :payment do
      event :payment_recorded, "Pacjent opłacił wizytę" do
        field :method, :payment_method
        field :amount, :money
      end

      event :visit_closed_commercially, "Recepcja zamknęła wizytę", terminal: true
      event :visit_closed_without_payment, "Zamknięto wizytę bez płatności", terminal: true

      event :settlement_corrected, "Zaksięgowano korektę rozliczenia" do
        field :delta, :money
        field :business_date, :date
      end
    end
  end

  process :visit_settlement, "Rozliczenie wizyty" do
    correlate :visit_id
    stage :charging
    stage :payment
  end

  scenario "wizyta 150 zł i kara 50 zł, zapłacone 200 zł — rozliczenie się zamyka" do
    given :visit_handed_over, %{total: 20_000}
    given :payment_recorded, %{method: :card, amount: 20_000}
    command :close_settlement
    expect :visit_closed_commercially
  end

  scenario "ta sama kwota w dwóch liniach — split jest poprawny, nie defektem" do
    given :visit_handed_over, %{total: 20_000}
    given :payment_recorded, %{method: :card, amount: 15_000}
    given :payment_recorded, %{method: :cash, amount: 5_000}
    command :close_settlement
    expect :visit_closed_commercially
  end

  scenario "zapłacone 150 zł przy należnych 200 — rozliczenie odrzucone" do
    given :visit_handed_over, %{total: 20_000}
    given :payment_recorded, %{method: :card, amount: 15_000}
    command :close_settlement
    rejected :payment_lines_sum_to_total
  end

  scenario "nic nie zapłacono — wizyta zamyka się bez płatności, i to jest legalne" do
    given :visit_handed_over, %{total: 20_000}
    command :close_settlement
    expect :visit_closed_without_payment
  end
end
```

```elixir
defmodule Rehmed.Settlement.VisitSettlement do
  @moduledoc """
  Decides the commercial side of one visit. A partial payment is refused rather than
  modelled: a settlement that can be short is a receivable (AGG-20).
  """
  use Rehmed.Contracts.VisitSettlement, aggregate: :visit_settlement

  @impl true
  def add_service_line(%AddServiceLine{visit_id: id, service_id: s}, _state),
    do: emit(%ServiceLineAdded{visit_id: id, service_id: s})

  @impl true
  def hand_over_visit(%HandOverVisit{visit_id: id, total: total}, _state),
    do: emit(%VisitHandedOver{visit_id: id, total: total})

  @impl true
  def record_payment(%RecordPayment{visit_id: id, method: m, amount: a}, _state),
    do: emit(%PaymentRecorded{visit_id: id, method: m, amount: a})

  @impl true
  def close_settlement(%CloseSettlement{visit_id: id}, %State{total: total, payments: paid}) do
    case Enum.sum(paid) do
      0 -> emit %VisitClosedWithoutPayment{visit_id: id}
      ^total -> emit %VisitClosedCommercially{visit_id: id}
      _short_or_over -> reject :payment_lines_sum_to_total
    end
  end

  @impl true
  def book_correction(%BookCorrection{visit_id: id, delta: d}, %State{handed_over_on: day}),
    do: emit(%SettlementCorrected{visit_id: id, delta: d, business_date: day})   # F2, §16

  @impl true
  def evolve(state, %VisitHandedOver{total: t, __meta__: m}),
    do: %{state | total: t, handed_over_on: DateTime.to_date(m.occurred_at)}

  def evolve(state, %PaymentRecorded{amount: a}), do: %{state | payments: [a | state.payments]}
  def evolve(state, _changes_nothing), do: state
end

# sandbox/test: one generated test per scenario
defmodule Rehmed.VisitSettlementScenariosTest do
  use EhOsContract.ScenarioCase, contract: Rehmed.Contracts.VisitSettlement
end
```

### 4.6 The other kinds, in short

Names the material does not provide are marked *illustrative*; a real port does not invent them.

> **25 September 2026, after E1:** `public: true` below is superseded by D11 (§16). Inside one application the
> `consumes` + `policy` shape stays and needs no flag; `query` below gains `by:` capabilities with `scope` (D10).

> **25 September 2026, E4 — D14 (§16) renames the last example's result.** Written per actor, as below, it is
> the model's `grants`. `EhOsContract.Model.capabilities/1` gives the same capabilities under the names EHOS
> grants: `%{"rehmed.record_payment" => %{kind: :command, name: :record_payment, roles: ["rehmed.reception"],
> scope: nil}, …}`. The domain's `name:` is read from the compiled domain at the call, because a contract
> records no compile dependency on it (§8).

```elixir
# consumes + public + policy (TaxVision; the command name is illustrative)
event :registry_data_consistent, "Dane firmy zgadzają się z rejestrami", public: true   # in AccountingMonth

consumes Taxvision.Contracts.AccountingMonth, :registry_data_consistent
policy :tasks_follow_consistent_registry, "Zgodne rejestry — taski na miesiąc",
  handles: :registry_data_consistent, issues: :generate_monthly_tasks

defmodule Taxvision.Tasks.TasksFollowConsistentRegistry do
  use Taxvision.Contracts.MonthlyTasks, policy: :tasks_follow_consistent_registry
  @impl true
  def registry_data_consistent(%RegistryDataConsistent{company_id: c, period_id: p}),
    do: issue(%GenerateMonthlyTasks{company_id: c, period_id: p})
end

# effect — side effects only; an external call cannot run in the transaction
effect :notify_about_discrepancy, "Powiadom księgową o rozjeździe",
  handles: :registry_discrepancy_detected, calls: :mail,
  idempotency: [key: :event_id, owner: :downstream]

# a fact recorded rather than decided (D6): an observation, or an integration's answer
event :visit_completed, "Pacjent wyszedł z gabinetu", recorded_by: :specialist do
  field :service_id, :id
end
event :p1_report_sent, "Wysłano zgłoszenie zdarzenia medycznego do P1",
  recorded_by: :p1_integration, depends_on: :medical_event_registry   # a :system actor backed_by the external

# process manager (ClinicalVisit; the command name is illustrative)
process_manager :documentation_chase, "Pogoń za dokumentacją wizyty" do
  correlate :visit_id
  starts_on :visit_completed, sets: :chase
  timer :chase, wait: {24, :hour}, issues: :chase_documentation
  ends_on :visit_closed_clinically
end

# read model + query (R-07)
read_model :daily_totals, "Suma dnia według metody płatności", projects: :payment_recorded do
  field :business_date, :date
  field :method, :payment_method
  field :total, :money
end
query :daily_totals_for, "Suma dnia dla recepcji", reads: :daily_totals, by: [:reception, :manager] do
  field :business_date, :date
end

# a run over foreign events, and a promise (ClinicalVisit)
consumes Rehmed.Contracts.Scheduling, :visit_completed
consumes Rehmed.Contracts.Reporting, [:p1_report_sent, :p1_reporting_not_required]
process :clinical_visit, "Wizyta: wykonanie, dokumentacja i zgłoszenie zdarzenia medycznego" do
  correlate :visit_id
  stage :departure do include :visit_completed end
  stage :closing
  stage :reporting do
    include :p1_report_sent, terminal: true
    include :p1_reporting_not_required, terminal: true
  end
  promise :medical_event_reported_within_statutory_window do
    from :visit_completed
    eventually :p1_report_sent
    within {2, :day}
    or_else :p1_reporting_not_required
    source "Dz.U. 2025 poz. 866"
  end
end

# dynamic consistency boundary (PayerSettlement)
dcb :payer_period, "Rozliczenie płatnika za okres" do
  identity [:payer_id, :period_id]
  consults :visit_marked_settled_with_payer, match: [:payer_id, :period_id]
  consults :visit_excluded_from_invoice, match: [:payer_id, :period_id]
  consults :visit_completed, where: "wykonana wizyta tego płatnika w tym okresie"   # check: not machine-checkable
  invariant :every_delivered_visit_settled_or_excluded,
    "Każda wykonana wizyta płatnika w okresie jest na fakturze albo wykluczona z powodem", source: "AG:694"
  command :issue_payer_invoice, "Wystawienie faktury miesięcznej dla płatnika", by: :manager,
    emits: :payer_invoice_issued, rejects: :every_delivered_visit_settled_or_excluded do
    field :invoice_id, :id
  end
  stage :invoicing do
    event :payer_invoice_issued, "Wystawiono fakturę miesięczną dla płatnika", terminal: true do
      field :invoice_id, :id
    end
  end
end

# capabilities, derived from by: and recorded_by:
EhOsContract.Model.capabilities(Rehmed.Contracts.VisitSettlement)
#=> %{reception: %{commands: [:book_correction, :close_settlement, :record_payment], queries: []}, ...}
with :ok <- EhOsContract.Capability.check(%RecordPayment{} = cmd, roles),
     do: EhOsContract.dispatch(cmd, actor: %{subject: user_id, roles: roles})   # dispatch checks again
```

> *Corrected 3 October 2026, plan EP4.* The effect above first read `idempotency: :downstream`, one atom
> that could be the key or who keeps it, and the sketch's other examples used it as the key
> (`:event_id`). `idempotency` now names both, ESDM's `key` and `owner`: `:self` (the reaction's code keys
> what it writes), `:downstream` (the system it calls is given the key) or `:infrastructure` (the engine
> keys it, as it does a policy's commands). The line is rewritten because the test that compiles this
> section reads it as written.

## 5. What a contract generates, and how an implementation binds to it

A generator transformer runs last. It builds the model once, persists it, and queues nested modules with
`Spark.Dsl.Transformer.async_compile/2` and `Module.create/3`, passing the declaration's file and line so
go-to-definition lands on the DSL. Into the contract module itself it evaluates
`__eh_os_contract_model__/0` and a `__using__/1` that delegates to `EhOsContract.Implementation`.

**Generated modules**, per contract `C`:

| Module | What |
| --- | --- |
| `C.Commands.RecordPayment` | struct: `@enforce_keys` on non-optional fields, `@type`, `__meta__` (actor, time, correlation — set by dispatch) |
| `C.Events.PaymentRecorded` | struct, same shape |
| `C.Aggregates.VisitSettlement` (with `.State`) | behaviour: one callback per command, `(command, state) :: decision`, plus `evolve/2` |
| `C.Dcbs.*`, `C.ProcessManagers.*` (with `.State`) | same pattern |
| `C.Policies.*` | one callback per handled event, `(event) :: issued` |
| `C.Effects.*` | one callback per handled event, `:: :ok \| {:error, term}` |
| `C.ReadModels.*` (with `.Row`), `C.Queries.*` | one callback per projected event, and one per query reading the model |

Domain types are referenced as remote types from the `Values` module the domain generates; remote types
create no compile dependency. The event type stored in the log is the stable string
`"<process>.<event>"`, never a module name, so renaming a module does not orphan history.

> *Changed 6 October 2026, plan DD, ID3 ([#173](https://github.com/EmpoweredHouse/eh-os-contract/issues/173)).* **The
> event type is `"<contract id>.<event>"`.** A contract's required `id:` (D11) replaces the process's name: renaming
> a process no longer changes a stored type, while renaming the id, or moving an event to a contract with another id,
> does. This amends D1 (§16) and the `type` comment of the events table in §10. Logs written under the old types are
> not read: an upgrading application resets the engine's schema (the user's decision, recorded on the issue).

> *Corrected 30 September 2026, plan E11f.* **True of dispatch's fold, not of the rest of the engine.**
> Every row also stores its contract's module name in `contract`, and every `_commands` row does too, and
> most readers select or resolve by it:
> - ordered subscriptions, process managers and effect jobs decode a row through that name, and fail on the
>   first row written under the old one;
> - a consumer's key, `"<contract>:<kind>:<name>"`, carries it: subscriptions, process-manager runs,
>   timers and queued effect jobs belong to the old key;
> - an idempotent retry is replayed only for the same contract name;
> - the conformance report — `Paths`, `Coverage`, drift, `Deployment`, `Dependency` — filters on
>   `contract == inspect(module)`.
>
> Decoding by the reader alone was tried in E11f and reverted: the renamed read model, registered anew at
> position 0 with no `reset/0`, then projected the log a second time, silently. A module rename is a change
> with history (`change-contract`) until the engine recognises a contract by something that survives one.

**Binding.** `use C, aggregate: :visit_settlement` (or `policy:`, `effect:`, `read_model:`,
`process_manager:`, `dcb:`) checks that exactly one unit is named and exists — a misspelling gets a
did-you-mean — and returns `@behaviour`, aliases for the unit's commands, events and state, an import of the
macros this kind may use, and `@before_compile EhOsContract.Implementation`.

**The implementation macros** check at compile time, at the call site:

```elixir
defmacro emit(ast) do
  {contract, _kind, unit} = unit!(__CALLER__)
  structs = literal_structs!(ast, __CALLER__)   # %M{}, [%M{}, ...], a `for` producing %M{}; else CompileError
  allowed = allowed_events(contract.__eh_os_contract_model__(), unit, __CALLER__.function)
  # inside a command callback: that command's emits; anywhere else: the union of the unit's emits
  Enum.each(structs, &refuse_unless_allowed!(&1, allowed, __CALLER__))
  Module.put_attribute(__CALLER__.module, :eh_os_contract_emitted, {__CALLER__.function, names(structs)})
  quote do: {:ok, List.wrap(unquote(ast))}
end
```

- `reject/1,2` takes an atom literal that must be in the current command's `rejects:`, and expands to
  `{:error, %EhOsContract.Rejection{}}`.
- `issue/1` takes command-struct literals that must be in the policy's or process manager's `issues:`.
- `@before_compile` checks that every expected callback is defined (the error shows the clause to add) and
  that `evolve/2` covers every event, scanning clause heads with `Module.get_definition/2` unless a
  catch-all clause exists. It defines `__eh_os_implementation__/0`: the unit and the emits it recorded.

**What stays at run time:** field values against their types (casting, enum membership, nil on required
fields), capabilities at dispatch, the backstop that emitted events are within `emits:` and rejections
within `rejects:`, routing a stored type to its struct, and encryption.

> **25 September 2026, E5 — what the table above left open, as built.** The generator is a transformer after
> `Build` that calls `Module.create/3` at each declaration's file and line; it writes the structs and
> behaviours from one list, `EhOsContract.Next.Contract.Callbacks`, which the implementation macros check
> against as well. Choices the table does not make: **`evolve/2` is expected only when a state is declared**
> — a unit whose state is its identity alone has nothing to fold — and it folds a boundary's consulted events
> as well as its own, and a process manager's triggers. **A process manager has one callback per reaction or
> timer that issues**, `(event, state)` and `(state)`; what it sets and cancels is declared, so it has no
> callback. **A read model's callback takes the event alone**, `(event) :: :ok`, until E6 runs projections
> and says what they write through. **A query's callback sits in `C.Queries.*`, beside its parameters**,
> since `use C, query: :q` binds to it and the implementation matches on the struct. An event received from
> another application gets `C.Received.*`. **`reject/1` only:** a second argument would carry details, and a
> rejection travels to logs and callers, so `EhOsContract.Rejection` names the invariant and nothing else
> (§17). `emit/1`, `reject/1` and `issue/1` are imported in every implementation, so a macro in the wrong
> kind is refused by I7 with a reason, not by the compiler as an undefined function.

> **7 October 2026, plan DD, T2a ([#240](https://github.com/EmpoweredHouse/eh-os-contract/issues/240)) — a
> decision may read an entity.** "A decision is a function of the command and the unit's state" left no place for
> what the application keeps outside the log: whether a booked visit is reported to the state register depends on
> the service booked, and the clinic keeps its services. The caller sending the flag makes the decision trust a
> claim; the decision reading the database itself leaves no record of what it read, and a scenario cannot supply
> it. So **a command may declare `reads: [service: :service_id]`**, naming a required field of its own typed
> `{:id, entity}`, and is then issued only by an actor, never by a reaction, whose lookup would run inside the
> transaction that reacted (A8); **its callback is then `(command, state, reads) :: decision`**, `reads` holding
> each row under its name, with the fields the domain declares for the entity. The rows come from the host
> (`EhOsContract.Entities`, asked as the actor who issued the command, so a host with several tenants answers
> with that tenant's rows), are read once per command before its transaction, so a conflict's retry decides on
> the same rows, and are kept with the command's record (`inputs` of `eh_os_contract_commands`, migration V02);
> entities hold no personal data (D6), so the record needs no sealing. A row not found is the caller's error, a
> field naming nothing (`{field, :unknown}`), not a rejection. A scenario gives the row with `given_entity` (S12,
> X9). A decision is still a pure function of its arguments; it has three of them. Rejected: putting the rows in
> `__meta__`, which says who and when and comes back with the log; folding them into the state, which is the
> unit's history and would then depend on when it was read.
> ([#240](https://github.com/EmpoweredHouse/eh-os-contract/issues/240))

> **7 October 2026, plan DD, A1 — a command may name the person who must issue it.** `by:` names roles, so any
> specialist could close a colleague's visit, and a rule of the business — "the visit's own specialist closes it"
> — had nowhere to stand but the decider, which never sees the credential. **A command may declare `actor_is
> :specialist_id, or_rejects: :invariant`**: the credential's subject must be the one that field of the unit's
> state holds (A9: a non-personal `:id` of the state or the identity, an invariant in `rejects:`, not on a command
> that creates its aggregate, and only on a command people issue). Dispatch checks it after folding the state and
> before the decision, and refuses as a lifecycle's precondition does, on the invariant with a `rejected` row, so
> the report counts it as any business refusal. A `:system` actor and a reaction act for the application and are
> not compared. **No exception for a role** (the user's decision): an override is a command of its own, so the
> report can tell it from an ordinary close. Rejected: comparing in the decider through `__meta__`, which would
> leave the rule invisible to the contract and to the report; a field of the command, which the caller fills
> and so would name themselves. ([#247](https://github.com/EmpoweredHouse/eh-os-contract/issues/247))

## 6. Checks, in five layers

**No rule depends on a Spark verifier.** Verifiers run in `@after_verify`, Spark turns their errors into
warnings, and they do not re-run on incremental compiles — so a rule written as a verifier would be a hard
error only under `--warnings-as-errors`, and only sometimes. Modelling rules must never be compiler
warnings for the same reason: the gate would turn them into errors.

**L1 — the Spark schema.** Unknown option or entity, missing required option, wrong type.

**L2 — transformers** (hard errors in `@before_compile`, each with the DSL file and line and a did-you-mean
where it helps; every violation is reported as a diagnostic before the single raise):

- *Names.* N1: snake_case; unique per namespace — units; commands, events, timers and consumed aliases
  together; invariants per unit; stages; promises. N2: no reserved words, no Kernel clash at the callback's
  arity.

  > *Added 5 October 2026, after the review of #139.* **N1**, and **D1** in the domain, also refuse a label
  > that is given and blank, empty or only whitespace, on every declaration that has one, a field's included.
  > L1 could not: a label's schema is a string, and `""` is one. #139 refused it for a timer alone, under P4;
  > the rule is one for every label, so it moved here. F2 and D3 refuse an enum member's blank label. A struct
  > written as data, in a scenario's rows or an invariant's examples, is not a declaration and is not asked.
- *Fields.* F1: unique in a struct, none starting with `__`. F2: well-formed types; an enum is a non-empty
  set with no member repeated (`:open` beside `"open"` counts). F3: `default:` only in `state`. F4: fields
  used as identity, correlation, `match` or tags are neither `optional:` nor `personal:`. F5: `personal: f`
  needs `f` to be a required, non-personal `:id` field of the same struct declaring `subject:`. F6:
  redeclaring an injected identity field is an error.

  > *Added 27 September 2026, E8.* **F7**: a field whose value the library keeps outside the log is not
  > personal, since erasure (§14) reaches only what the log encrypts — a process manager's state, stored in
  > `_process_managers`, and a query's `scope` parameter, whose value the authorization package writes with
  > every decision. §14's gate list names the first and not the second; the second came from EA's security
  > review. A query's `param` takes no `personal:`, so at L2 F7 sees only a manager's state; a domain value
  > holding a personal field, at any depth, in either place is refused at L3, where the domain is known.

  > *Added 3 October 2026, issue #96.* **F8**: a field a run or a process manager's record is told by — an
  > event's field a `correlate` names, a manager's state field its own `correlate` names — is an `:id`,
  > `{:id, entity}` or a domain value resting on `:id` (L3), as `match:` already was (A4). Its value is joined
  > into an index key, and since the value bounds of 3 October only an `:id` has a length bound, 255 bytes;
  > `correlate` on a `:string` let 3 KB of a request's text fail the append with a 500, or stall a manager's
  > subscription. **F9**: a unit's identity and each `correlate` have at most six fields, measured against
  > Postgres 17 (`EhOsContract.Key`). Hashing a key past a length would have needed no rule, and was rejected:
  > a hashed stream or run key can no longer be read in the log or on the dashboard.

  > *Added 3 October 2026, issue #98.* **F9 was a sample, not a bound.** Six fields of 255 bytes are 4595
  > bytes once `|` and `%` are escaped, past the 2704 a btree entry holds, and they fit only when Postgres
  > compresses the entry, which it keeps only when that saves a quarter; nor did F9 count the name in front
  > of the key, a module's in a process manager's. A key is now counted after escaping, with that name,
  > against a budget of 2048 bytes (`EhOsContract.Key.budget/0`): dispatch refuses a command over it with
  > `:key_too_long` (422), and a process manager stops at the event with `EhOsContract.Key.TooLongError`.
  > F9 stays as the compile-time refusal of shapes that would mostly fail anyway.
- *Units.* A1: `emits` is non-empty and a subset of the unit's own events. A2: every event is emitted by at
  least one command of its unit **or declares `recorded_by`** — stricter than ESDM, because in an
  event-sourced system any other event can never occur. A3: `rejects` ⊆ the unit's invariants. A4: a DCB has
  at least one `consults`; each names an existing event and has `match` or `where`; `match` ⊆ the DCB's
  identity. A5: `state` at most once. C1: a command is reachable — a non-empty `by:`, or a local policy or
  process manager issues it.
- *Consumers.* P1: a policy handles local or consumed events and issues local commands only. P2: an effect
  with `calls:` cannot be `:in_transaction`. P3: `:at_least_once` requires `idempotency`. P4: process
  manager triggers are events or its own timers; a timer has exactly one of `wait` / `at`; `at` names a
  `:timestamp` field of its state; `sets` / `cancels` name its own timers. P5: `projects` names local or
  consumed events; `reads` names a local read model.

  > *Corrected 25 September 2026, E4.* P3 as written refuses §4.6's own process manager, which is
  > `:at_least_once` by default and names no `idempotency`, while E4's acceptance is that §4.6 compiles as
  > written. A process manager's commands and timers take keys the library derives from the run (§17,
  > "deterministic keys; timers as events"), so it has nothing to name. P3 applies to policies and effects.

  > *Corrected 3 October 2026, plan EP4.* `idempotency` is `[key:, owner:]`, and only an effect's owner is
  > `:downstream`: a policy and a process manager issue commands to this engine, never to a system that
  > could keep a key. Nor is an effect's owner `:infrastructure`: the engine keys the commands a reaction
  > issues, by the event's id (`Consumer.reaction_key/5`), and not an effect's call — so `:infrastructure`
  > keys on `:event_id`.

- *Process.* R1: exactly one `process`. R2: its `correlate` fields are present in every local event. R3: if
  the process declares stages, every local event sits in a stage group and every `include` has a stage; if
  it declares none, no groups. R4: `include` names consumed events only. R5: a promise's `from`,
  `eventually` and `or_else` are events of the run. R6: `within`, `deadline` and `wait` use fixed units and
  non-negative counts.
- *Consumes.* K1: a contract cannot consume itself; consumed aliases do not collide with local names.
- *Scenarios.* S1: the trigger resolves; the unit is inferred or given with `scope`. S2: `given` and
  `expect` events belong to that unit or to what it consults or projects. S3: data keys are declared fields,
  and `given` and commands supply every required one. S4: `rejected` names an invariant in the command's
  `rejects:`. S5: `expect` ⊆ the command's `emits:`. S6: trigger and outcome fit the kind of unit. S7: the
  scenario's `actor` is in the command's `by:`. S8: **every invariant is covered by at least one `rejected`
  scenario** — the successor of architecture §18's gate, kept an error although ESDM makes it a warning.

  > *Made precise 25 September 2026, E5, while the S rules were written.* **S1** also refuses a scenario with
  > no trigger or with more than one: E4's model kept the first of two and dropped the other without a word.
  > **S3**: a unit's identity is not required in scenario data, because a scenario is one stream and §4.5's
  > own scenarios name no `visit_id`; given, it has to be an `:id`. Values of built-in types are checked here,
  > at L2, and only values of domain types, and data of an event consumed from a sibling, are left to X9.
  > **Time in scenario data** is an ISO 8601 string, `"2026-09-01T09:00:00Z"` for a `:timestamp` and
  > `"2026-09-01"` for a `:date`: a `~U` literal would put a `DateTime` into the model, which §9 keeps plain
  > data, so S3 refuses it with that reason. **S6** accepts two targets: a command to an aggregate or a
  > boundary, followed by `expect` or `rejected` and not both; and an event delivered to a policy (followed by
  > `issues`) or to a process manager (followed by `issues`, `sets`, `cancels` or `ended`, each one its
  > declaration allows for that trigger). An effect's outcome is outside the log, and nothing yet says what a
  > read model's rows or a query's answer should be, so neither is a scenario's target until a stage gives
  > them a word; `query` stays in the vocabulary and is refused with that reason. **S8** counts per unit: two
  > units may each have an invariant of the same name. *Later the same day, with `ScenarioCase`:* `on` may name
  > a process manager's timer, which fires, since a timer is one of its triggers (P4) and nothing else could
  > state what it issues; and two scenarios may not share a description, which names the test generated for each.
  >
  > *26 September 2026, E6: a query's scenario, after ESDM's read model scenario.* ESDM's Given-When-Then
  > extension has a read model variant: given events, **when** a query with its parameters, **then** a
  > `result` (or the materialized read model). v2 takes it with the word `answers`: `query :q, %{…}` followed by
  > `answers [%{…}]`, or for a query returning one, `answers %{…}` or `answers nil`. S2: `given` events are
  > ones the read model the query reads projects. S3: the parameters are the query's, and each row names
  > fields of that read model. S6: exactly one `answers`, and it belongs to a query's scenario only. ESDM
  > leaves how a result is compared open; `EhOsContract.ScenarioCase` asks for **exactly as many rows as
  > named, each matching a different answered row on the fields it names, in any order**. Events stay a
  > subsequence, since a flow grows by events; an answer is wholly determined by its givens, and "the other
  > clinic's visit is not in it" is often the point. The read model alone, ESDM's materialized variant, is not
  > a target: a scenario reaches it through a query. `answers` enters the model only on a query's scenario, so
  > the word moved no existing contract's version.
  > *Added 27 September 2026, plan EL2, the user's choice after asking whether the engine can check it.*
  > **A command's constraint is checked as an invariant is** (ESDM's `constraints`, which ESDM leaves prose):
  > `constraint :positive_amount, "…"` inside the command; A3 lets `rejects:` name it; **A7**: it is named once,
  > never as an invariant of the unit, and it is in the command's `rejects:`; **S8** asks a `rejected` scenario
  > of that command for each; I5 lets `reject/1` name it. A query's constraint is prose, since a query refuses
  > nothing. A value's invariants get a validator in their own stage (EL2b).
  >
  > *Added 28 September 2026, plan EL2b.* **S9**: a domain service's rule gives at least one example, each
  > `{[argument, …], result}` with the function's arity, each value of its declared type (`nil` only where
  > optional), none given twice, since each names its test. **X9** reads those examples too, for the values of
  > domain types.
- *Domain.* D1: unique names per kind. D2: at most one translation per language, none into the context's
  own. D3: a value has exactly one of type or fields; `unit` only on numeric types; no cycles. D4: a human
  actor has no `backed_by`. D5: relation roles fit the type; endpoints exist; no relation to itself.

  > *Added 28 September 2026, plan EL2b.* **D9**: a value's invariant is named as the function that checks it
  > is — snake_case, once in its value, no clash with what Elixir defines at arity one (N2's list), and not
  > `:required`, `:type` or `:generated`, which a refusal puts where an invariant's name goes — and it gives at
  > least one `violated_by:` and one `satisfied_by:`, each plain data of the value's type, none `nil` and none
  > in both. **At run time** a value that fits its type is held to its invariants wherever a type is:
  > a command's fields and a recorded event's are refused, `{field, {:invariant, name}}`, 422 `{"invalid":
  > {"<field>": "<invariant>"}}`; an event a decision returns raises, as one not fitting its type does; a
  > query's parameters are refused and a domain service's arguments and result raise. What the value is made of
  > is asked first — a list's items, a value's fields, the value an alias stands for — then its own. **The log
  > read back is never held to them**, so an invariant added later leaves history readable. `check` warns,
  > `value-without-implementation`, of a value nobody checks in a domain whose contracts have code.
  > **What history can still meet:** a policy or process manager that builds a command from an old event's
  > value is refused on an invariant added since, and the refusal of a reaction's command rolls back the
  > command that set it off, or stops an ordered consumer at that event. Adding an invariant is therefore a
  > change to the model, like narrowing a type: the values already in the log need a look first. A value's
  > implementation is found as a declaration's is (§10.5): among the configured applications and the
  > domain's own; its binding joins the wiring version of every contract of the domain (§13).

**L3 — a Mix compiler, `compile.eh_os_contract`** (hard diagnostics on every compile, because references
between DSL modules record no compile dependency, §8):

- X1: `domain:` points to a domain that declares `context:`.
- X2: every `by:`, `recorded_by:`, `accountable` and scenario `actor` names an actor of this context.
- X3: every non-built-in field type is a domain value; every `subject:` a domain subject.
- X4: `depends_on` and `calls` name domain externals.
- X5: a consumed contract exists, and the event is `public`.
- X6: **the fields a subscriber's declarations use — in `correlate`, `match`, `include` and `projects` —
  exist in the publisher's current schema with compatible types** (§7).
- X7: process names, and therefore event types, are unique across the system.
- X8: each unit has at most one implementation.
- X9: scenario values fit their types.

  > *Made precise 25 September 2026, E5b, while the L3 rules were written* (`EhOsContract.Next.Contract.Links`).
  > **X2**: an actor "of this context" is one that names this contract's context or none. **X5**: since D11
  > there is no `public` to require; the consumed contract has to be a v2 contract **of the same domain**, since
  > one of another domain is another application's, reached only through `publish`, and it declares every event
  > named. **X6**: the fields used are the process's `correlate` for every event it `include`s, a process
  > manager's `correlate` for every event it handles, and a boundary's `match:` for every event it `consults`;
  > compatible means the same type, and neither optional nor personal, as F4 asks of a local event. `projects`
  > names an event and no field of it: which fields a projection reads is in its implementation, which matches
  > on the publisher's struct (§7, the third mechanism), so for `projects` X6 is X5. **X8** covers everything
  > code implements, not only units: dispatch and scenarios need one implementation of a policy or a query too.
  > **X9** checks values of domain types wherever a scenario gives one, and the data of an event consumed from a
  > sibling in full — keys, required fields, types — where S3 could see no fields. The parts of D10, D11 and D14
  > that need the domain or other contracts are L3 as well, and are numbered by their decision, as in L2: every
  > actor asking a scoped query carries the scope (D10), a `publish` is named under the domain's `name:` (D11),
  > and a command's or a query's name is unique among the contracts of one domain (D14). **Which modules**: the
  > compiler reads the `.beam` files in the project's compile path, with no configuration, and looks up by name
  > the domain and the siblings a contract names. **Locations** (§9): L3 reads the declarations Spark keeps in
  > the compiled module (`spark_dsl_config/0`), with their file and line, so nothing new is persisted beside the
  > model; the line of a contract's `use` is added to Spark's persisted data, and an implementation's `use` to
  > `__eh_os_implementation__/0`. L5 does not repeat L3 yet: both projects in this repository register the
  > compiler, and that repetition comes with the rest of L5 (E10).

**L4 — implementation macros** (`CompileError` at the call site). I1: the unit exists. I2: every callback is
defined. I3: `evolve` is covered. I4: `emit` gets literals allowed there. I5: `reject` names an invariant in
the command's `rejects:`. I6: `issue` names commands in `issues:`. I7: each macro only where its kind allows
it — `emit`/`reject` in aggregates and DCBs, `issue` in policies and process managers, none in effects or
read models.

**L5 — `mix eh_os_contract.check`** (warnings and notices; it also repeats L3 as errors for projects that do
not register the compiler):

- ESDM's completeness rules: aggregate without events, event without consumer, read model without query,
  process manager without `ends_on` or with only timer reactions, event name repeating its unit's prefix,
  orphan actor / external / relation, a context no contract uses, a cross-context `consumes` with no
  relation, a `consults` with only `where`.
- Kept from v1: backward edges, competing in-transaction consumers of one event, promises finer than their
  run, promise without `within` (notice), deadline without a terminal event (notice), missing `accountable`,
  `unverified` declarations, no contracts found; a `:string` field not marked personal (notice).
- New: declared `emits` the implementation never produces; a unit without an implementation (notice — a
  contract without code is legal, D3); a public event whose schema changed since the deployed version while
  another application may consume it (§7).

  > *Made precise 27 September 2026, EL1, while L5 was written* (`EhOsContract.Check.Catalog`,
  > `docs/rules.md`). **Every rule has a stable name**, the user's choice: ESDM's where the rule is ESDM's,
  > without its `esdm/<category>/` prefix, and one in the same style for the library's own
  > (`process-without-accountable`). L2 and L3 keep their codes. Levels are fixed per rule and nothing
  > silences one, as in ESDM; `--format json` and `--warnings-as-errors` are ESDM's too. Where the list above
  > was loose: **"event without consumer"** counts a promise naming the event, or `terminal: true`, as a
  > reader, since the conformance report reads it — without that, every event a run ends on would warn with
  > no way to silence it; **"aggregate without events"** covers a boundary as well, and ESDM's
  > `aggregate-without-commands` is not a rule, since a unit of `recorded_by:` events has no command on
  > purpose (D6); **"a context no contract uses"** is ESDM's `bounded-context-without-content`; **"a
  > cross-context `consumes` with no relation"** also counts a field naming an entity another context owns
  > (EM2), and so does `orphan-context-mapping`; **"only timer reactions"** leaves `ends_on` aside, as ESDM
  > leaves `endsWhen`. **Not built:** the public-schema rule, which needs the deployed version from the
  > database while every other rule reads compiled modules only — it comes with `publish` leaving the
  > application (E12); and v1's "promises finer than their run", which no v2 contract can be asked about
  > until the sandbox's are written anew (E9). **L5 repeats L3** for a project without the compiler.

## 7. A change to an event, and its subscribers

A change to an event's structure in the publishing process is verified by the compiler at every subscriber,
so the change is reflected there and consistent. Three mechanisms together deliver it:

1. **One source of structure.** A subscriber never declares a copy of someone else's event. It uses the
   struct generated from the publisher's contract (`Publisher.Events.X`), so a change of fields is there at
   once.
2. **The subscriber's declarations, checked by L3 on every `mix compile`** against the publisher's current
   schema: the event exists and is public; the fields used in `correlate`, `match`, `include` and `projects`
   exist with compatible types. The error names both the subscriber and the publisher.
3. **The subscriber's implementation.** Policies, projections and process managers match on the same struct,
   and expanding a struct records a compile dependency on its module. A change of fields therefore
   recompiles the implementation; the compiler refuses unknown keys in the patterns, and Elixir's type system
   reports access to fields that no longer exist — warnings, which the gate makes errors.

Adding an optional field is compatible. Removing a field, renaming it, changing its type, withdrawing
`public: true` or removing the event breaks the compilation of every subscriber that uses it; a subscriber
that does not use the field keeps compiling. A change to an event that already has history in the log also
needs a `schema_version` and an upcaster (§10.6). Between applications, over a broker, the compiler cannot
reach: there `check` compares a public event's schema with the deployed version, and impact analysis across
applications belongs to EHOS.

> **25 September 2026, after E1 — D11 (§16).** Everything above holds inside one application, where
> publisher and subscriber are compiled together. "Withdrawing `public: true`" no longer exists: a sibling
> process's event is consumable without a flag. Between applications the subscriber has no publisher code to
> compile against, so it declares the fields it reads in `consumes "<name>"` and EHOS's composition check
> (C-3, C-4 in `eh-os`) compares that with the publisher's registered model. Removing or retyping a field of a
> `publish` is a new versioned name, not an edit.

## 8. Compile-time dependencies

```
Rehmed.Domain  <..no-depend..  Rehmed.Contracts.VisitSettlement  <==compile==  Rehmed.Settlement.VisitSettlement
                               (+ Commands.*, Events.*, Aggregates.*)          (use + macros read the model;
Contracts.ClinicalVisit ..no-depend (consumes)..> Contracts.Scheduling         struct literals = compile deps)
```

- The only compile dependencies go from an implementation to its contract, and from an implementation to the
  structs it expands — its own contract's or a publisher's.
- `domain:` and `consumes` are expanded through Spark's `no_depend_modules`, so they record no dependency.
  Adding a contract gives it no incoming edges and recompiles nothing else, as in v1; cycles between
  contracts (A consumes B, B consumes A) are legal.
- The price of recording no dependency is that incremental compiles do not revisit those references — which
  is why L3 runs on every compile.
- A contract never depends on its implementation: the successor of v1's "a rule is an MFA, never a
  capture". Implementations name the contract; the contract names nothing.

## 9. The compiled model

`__eh_os_contract_model__/0` returns plain data — maps, lists, atoms, strings, integers, booleans; durations
as `%{amount: 24, unit: :hour}` — so it encodes to JSON for EHOS unchanged:

```elixir
%{format: 1, kind: :contract, domain: Rehmed.Domain, context: :settlement,
  process: %{name: :visit_settlement, label: "…", correlate: [:visit_id], stages: [...], includes: %{}, promises: %{}},
  units: %{visit_settlement: %{kind: :aggregate, identity: [:visit_id], state: %{...}, invariants: %{...}}},
  commands: %{close_settlement: %{unit: :visit_settlement, by: [:reception], emits: [...], rejects: [...], fields: %{}}},
  events: %{payment_recorded: %{unit: :visit_settlement, type: "visit_settlement.payment_recorded",
            stage: :payment, terminal: false, public: false, recorded_by: [], fields: %{...}}},
  policies: %{}, effects: %{}, process_managers: %{}, read_models: %{}, queries: %{}, consumes: [],
  scenarios: [...], capabilities: %{...},
  version: "3f9c…", public_digest: "…", digests: %{"command:close_settlement" => "…", "scenario:*" => "…"}}
```

- **Digest rules.** Collections of declarations are maps keyed by name, so declaration order does not matter;
  values with set meaning (`by`, `emits`) are sorted; `stages` and `correlate` keep their order. Hashing is
  `EhOsContract.Digest`, unchanged. Spark's source annotations are left out; locations for L3 diagnostics are
  persisted separately. The domain has its own digest, so a change to a value type shows in `Deployment` as
  a `value:money` change.
- **Accessors.** `EhOsContract.Model` (`events/1`, `event/2`, `command/2`, `unit_of/2`, `run/1`,
  `capabilities/1`, `version/1`, `module_for/3`) replaces the query functions v1 generates on every contract
  (`events/0`, `event/1`, `processes/0`, …).
- **The system.** `EhOsContract.System` derives the whole system — contexts, contracts, `consumes` edges,
  capabilities — from the registry's scan, never from a parent module listing contracts.

*Corrected 25 September 2026, while E1 built the v1 subset of this model.* "Collections of declarations are
maps keyed by name, so declaration order does not matter" is true of the digest. It is not true of the data.
Every v1 reader that prints a list prints it in declaration order: graph nodes, the report's processes and the
brief's rows all come out that way. So a model keyed by name would reorder their output, and E1's
acceptance criterion (a byte-identical report and graph) could not hold. The E1 model therefore keeps
**lists in declaration order**, and the v2 model has to carry that order as well, either as lists or as an
explicit position. The digest ignores order, as it already does: `EhOsContract.Digest` makes declaration
order insignificant, so nothing about the version changes. Two smaller points came out of the same work.
The v1 subset needs `processes/1`, because a v1 contract may hold several processes where v2 has one
`process`. And v1 has none of the concepts behind `unit_of/2`, `run/1`, `capabilities/1` and
`module_for/3`, so E1 left those accessors out rather than stubbing them.

## 10. The store

### 10.1 Behaviour

```elixir
defmodule EhOsContract.Store do
  @type position :: non_neg_integer()
  @type query :: [%{types: [String.t()], tags: [String.t()]}]   # items OR-ed, tags AND-ed
  @type condition ::
          :none
          | {:stream, String.t(), expected_version :: non_neg_integer()}   # 0 = must not exist yet
          | {:dcb, query(), after :: position()}
  @callback lock(repo :: module()) :: :ok
  @callback append(module(), [map()], condition()) ::
              {:ok, [EhOsContract.Recorded.t()]} | {:error, :wrong_expected_version | :condition_failed}
  @callback read_stream(module(), String.t(), after_version :: non_neg_integer()) :: [EhOsContract.Recorded.t()]
  @callback read_query(module(), query()) :: {[EhOsContract.Recorded.t()], head :: position()}
  @callback read_all(module(), after :: position(), pos_integer(), [String.t()] | :all) :: [EhOsContract.Recorded.t()]
end
```

It isolates the SQL, not the transaction model: every call runs inside the caller's Ecto transaction.

*Corrected 25 September 2026, while E2 built the behaviour.* Three things in the sketch above did not survive
contact with the compiler and with v1's readers:

- `after ::` does not compile, because `after` is a reserved word in Elixir. The built behaviour names the
  parameter `after_position`.
- The callbacks return `EhOsContract.Event` rows, not an `EhOsContract.Recorded` struct. Every v1 reader
  and handler already takes `%EhOsContract.Event{}`, and E2 changes none of them. A decoded read type
  earns its own struct when `Codec` starts decoding payloads (E6), not before.
- E2 builds the `:none` and `{:stream, id, expected}` conditions only. `{:dcb, query, after}` and
  `read_query/2` come in E9 with PayerSettlement, the first contract that needs them. So the condition
  arrives together with its first reader.

> **27 September 2026, EM1 — the boundary as built.** The condition and `read_query/2` came before
> PayerSettlement, with the dispatch of a boundary's command as their reader (plan: the ESDM gaps before the
> sandbox contracts). Three things the sketch did not say: (1) a boundary reads **its own events under its
> whole identity** besides what it `consults`, as an aggregate reads its stream, so it sees its own history
> without consulting itself — and consults its own events explicitly when a narrower match is the point, as
> a seat consults every subscription to its course; (2) a `consults` with `where:` alone reads **every
> event of the type**, since prose cannot be a tag, so any new one is a conflict — correct and coarse, and
> L5's "a `consults` with only `where`" says so; (3) a boundary's events carry **no stream**: the condition
> is the query, and the store refuses a stream on an entry appended under it.

### 10.2 Ordering: one global, transaction-scoped advisory lock

Positions from a sequence commit out of order under concurrent writers, and a reader following
`position > checkpoint` would skip a row committed late. Three known answers: serialize appends with one
advisory lock; filter by `xid8` below `pg_snapshot_xmin`; track gaps with a high-water mark. **v2 uses the
lock.** A single writer handles hundreds of commands a second; a clinic's visits and a bookkeeper's
company-months are orders of magnitude below that. In return:

- readers see positions in commit order with no gap to wait on (holes left by rollbacks are permanent and
  harmless);
- stream and DCB conflict checks need no isolation tricks;
- the **prefix property** — every visible position up to H is committed — makes DCB checks cheap (§10.4).

Requirements: one fixed 64-bit lock key, taken by the store and again by a statement-level `BEFORE INSERT`
trigger as a safety net for inserts that bypass it (the lock is re-entrant); `CACHE 1` on the identity; READ
COMMITTED, asserted by the store; transaction-scoped and row locks only, so PgBouncer in transaction mode
still works. Moving to `xid8` later is an internal change: all historical rows are committed, so a
`transaction_id` column can be back-filled with a constant.

> **30 September 2026, issue #51 — "one" lock is one per database, not one per log.** The key is fixed, and an
> advisory lock belongs to the whole database, not to a schema. EHOS puts every application of an instance in
> one database, `apps`, each in a schema of its own (`eh-os` D-54, which says so of advisory locks), so every
> application built on the engine there takes the same lock: their appends serialize with each other's, and
> the capacity argument above is shared by all of them. Correctness holds — each log still sees its positions
> in commit order — and nothing is changed yet; the options (a two-integer key derived from the schema) are in
> `PLAN.md`. A key per schema removes only the accidental coupling: advisory locks carry no privileges, so a
> neighbour that takes the key can still stall the log, which D-54 accepts.

> **30 September 2026, later — one key per log.** V01 now takes `pg_advisory_xact_lock(class, log)`: `class` is
> the engine's, and `log` comes from the name of the schema the log is created in, both computed at migration
> and written into the lock function and the trigger. Appends to one log still serialize; logs in two schemas
> of one database no longer wait for each other. The "one fixed 64-bit lock key" above is one fixed key per log.

### 10.3 Schema

Final shape. E2 reaches it by altering v1's table in place, so v1 keeps running until E11 collapses the
migrations (D2).

```sql
CREATE TABLE eh_os_contract_events (
  position         bigint GENERATED ALWAYS AS IDENTITY (CACHE 1) PRIMARY KEY,
  id               uuid NOT NULL UNIQUE,
  type             text NOT NULL,                -- "<process>.<event>" (from ID3: "<contract id>.<event>", §8)
  schema_version   integer NOT NULL DEFAULT 1,
  contract         text NOT NULL,
  contract_version text NOT NULL,
  stream_id        text,                         -- 'accounting_month:c-1|p-7'
  stream_version   bigint,
  tags             text[] NOT NULL DEFAULT '{}', -- 'payer_id:p-1', 'visit_id:w-1'
  process          text,                         -- the home run; all runs are in _event_runs
  instance_id      text,
  command_id       uuid,
  correlation_id   uuid NOT NULL,
  causation_id     uuid,                         -- the command, or the timer event, that caused it
  actor            text NOT NULL,
  occurred_at      timestamptz NOT NULL,         -- dispatcher clock, injectable; what Trace and Run measure
  recorded_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  payload          jsonb NOT NULL,               -- personal fields as ciphertext
  metadata         jsonb NOT NULL DEFAULT '{}',  -- command type, issued_by, chain, idempotency key
  CHECK ((stream_id IS NULL) = (stream_version IS NULL)),
  CHECK (stream_version > 0)
);
CREATE UNIQUE INDEX ON eh_os_contract_events (stream_id, stream_version) WHERE stream_id IS NOT NULL;
CREATE INDEX ON eh_os_contract_events USING gin (tags);
CREATE INDEX ON eh_os_contract_events (type, position);
CREATE INDEX ON eh_os_contract_events (correlation_id);
CREATE INDEX ON eh_os_contract_events (command_id);
CREATE INDEX ON eh_os_contract_events (occurred_at);
CREATE INDEX ON eh_os_contract_events (contract, contract_version);
-- triggers: take the append lock before every INSERT statement; refuse UPDATE, DELETE and TRUNCATE

CREATE TABLE eh_os_contract_event_runs (         -- every run an event belongs to (D7), rebuildable
  position bigint NOT NULL, process text NOT NULL, instance_id text NOT NULL,
  PRIMARY KEY (position, process));
CREATE INDEX ON eh_os_contract_event_runs (process, instance_id);

CREATE TABLE eh_os_contract_commands (           -- replaces _handler_failures
  id uuid PRIMARY KEY, contract text NOT NULL, type text NOT NULL,
  issued_by text NOT NULL,                       -- 'actor:<subject>' | 'policy:<n>' | 'pm:<n>' | 'effect:<n>'
  idempotency_key text, causation_event_id uuid, correlation_id uuid NOT NULL,
  outcome text NOT NULL CHECK (outcome IN ('accepted','rejected','failed')),
  invariant text, failed_in text, error text,
  given_types text[] NOT NULL DEFAULT '{}', emitted_types text[] NOT NULL DEFAULT '{}',
  first_position bigint, last_position bigint, process text, instance_id text,
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp());
CREATE UNIQUE INDEX ON eh_os_contract_commands (idempotency_key)
  WHERE outcome = 'accepted' AND idempotency_key IS NOT NULL;

CREATE TABLE eh_os_contract_snapshots (stream_id text PRIMARY KEY, stream_version bigint NOT NULL,
  state_schema text NOT NULL, state bytea NOT NULL, seen_types text[] NOT NULL,
  subjects text[] NOT NULL DEFAULT '{}', taken_at timestamptz NOT NULL);
CREATE TABLE eh_os_contract_subscriptions (name text PRIMARY KEY, kind text NOT NULL, mode text NOT NULL,
  position bigint NOT NULL DEFAULT 0, version text NOT NULL,
  status text NOT NULL DEFAULT 'running',        -- running | stale | rebuilding | failing
  failed_position bigint, failure text, attempts integer NOT NULL DEFAULT 0, updated_at timestamptz NOT NULL);
CREATE TABLE eh_os_contract_process_managers (name text, correlation text, state bytea NOT NULL,
  timers jsonb NOT NULL DEFAULT '{}', position bigint NOT NULL, completed_at timestamptz,
  PRIMARY KEY (name, correlation));
CREATE TABLE eh_os_contract_subject_keys (subject_type text, subject_id text, key_version integer,
  kek_id text NOT NULL, wrapped_key bytea NOT NULL, inserted_at timestamptz NOT NULL,
  PRIMARY KEY (subject_type, subject_id, key_version));
CREATE TABLE eh_os_contract_erasures (subject_type text, subject_id text, erased_at timestamptz NOT NULL,
  requested_by text NOT NULL, PRIMARY KEY (subject_type, subject_id));
-- kept: _deployments (digests for the new kinds), _dependency_observations; _event_handlings becomes _effect_runs
```

Recovering a test database that leaked rows (the `MIX_ENV=test mix run` trap in `CLAUDE.md`) stays
`ecto.drop`: the append-only trigger rules out `DELETE`.

> **29 September 2026, E11c — the collapse as built.** `EhOsContract.Migrations.V01` creates this shape in
> one step and `current_version/0` is 1 (D2). Where it differs from the sketch above: (1) times are Ecto's
> `utc_datetime_usec`, `timestamp` without a zone, as every earlier version had them, not `timestamptz` — the
> engine writes and reads UTC only, and changing the type was not part of the collapse; (2) there is no
> `_effect_runs`: an effect delivered `:at_least_once` runs as an Oban job (`EhOsContract.EffectJob`), and
> `_event_handlings` and `_handler_failures` are not created; (3) no snapshot table, as the E8a note below
> says. The v1 indexes on `type`, `causation_id`, `instance_id` and `(process, instance_id)` are not created
> either: runs are read through `_event_runs`, and `(type, position)` covers `type`. Nothing migrates from
> before the cut — there was no consumer, so a database with an older schema is recreated (decision of the
> user, 29 September; `PLAN.md`, "E11c — co wyszło").

### 10.4 Appends

```sql
SELECT pg_advisory_xact_lock(<key>);
-- {:stream, id, n}: conflict unless it returns n
SELECT coalesce(max(stream_version), 0) FROM eh_os_contract_events WHERE stream_id = $1;
-- {:dcb, items, p}: conflict if true
SELECT EXISTS (SELECT 1 FROM eh_os_contract_events WHERE position > $1
  AND ((type = ANY($2) AND tags @> $3) OR (type = ANY($4) AND tags @> $5)));
INSERT INTO eh_os_contract_events (...) VALUES (...), (...) RETURNING position, id, recorded_at;
```

- **The head trick.** `read_query` reads `max(position)` as H first, then runs the query bounded by
  `position <= H`. By the prefix property, nothing matching up to H means nothing matching at all, so the
  condition always passes `after = H`, and the conflict check is a primary-key range scan over only what was
  appended since the read — never a scan of history.
- **Keys.** A stream id is the unit's name, `:`, then its key values in declared order joined with `|`,
  escaped the way `EhOsContract.Instance` escapes today. That escaping moves into one `EhOsContract.Key`,
  used by stream ids, tags, instance ids and idempotency keys alike — otherwise the escaped-separator defect
  fixed on 21 August would exist in four copies. A unit's key fields are always tags, so DCBs can consult
  aggregate events.
  > **27 September 2026, EM1.** "A unit's key fields are always tags" is too narrow for a boundary that
  > consults another unit's events on fields that are not that unit's key — PayerSettlement matches
  > `visit_marked_settled_with_payer` on `payer_id` and `period_id`, while the visit's key is `visit_id`.
  > Tagging only the fields some boundary matches today would leave the events appended before a new
  > boundary untagged, and it would never see them. So **every required, non-personal `:id` field of an
  > event is a tag**, its unit's key among them, and `match:` names only such fields (A4 for a local event;
  > X6 already required `:id` of a sibling's). A subject's identifier is such a field, so "every event about
  > subject p-17" is now one lookup in the tags' index, which erasure leaves alone — as it leaves the same
  > identifier in the payload and in stream ids, by the design above. That holds only while an `:id` is an
  > opaque identifier: a natural one, such as a PESEL, must never be an `:id`, as it must never be an
  > idempotency key.
  > **28 September 2026, E9c.** "`:id` field" includes a field typed by a domain value whose base type is `:id`:
  > TaxVision names a period "2026-07" and holds the name to a format by the value's invariant, and a month's
  > boundary matches Registry Watch's events on it. The value is still an opaque identifier in the sense above
  > — a month's name, not a person's number. A unit's identity stays a plain `:id`, so the invariant holds where
  > a field is typed by the value and not on an identity.
- **Idempotency.** The host supplies `ctx.idempotency_key` (opaque, never personal data). It is checked before
  loading and again under the lock; a hit returns the earlier events with `duplicate: true`; a hit for another
  command type is `{:error, :idempotency_key_reused}`. Only accepted outcomes bind the key, so a rejected
  command can be retried once state has changed. Internal dispatches — policy, process manager, effect, timer
  — get deterministic keys, `"<issued_by>:<source_event_id>:<index>"`, so redelivery cannot append twice.

  > *Corrected 30 September 2026, plan E11f, the user's decision.* **A key belongs to the actor who sent it.**
  > As first built, a hit was looked up by the key alone and the unique index was on the key alone, so one key
  > was shared by the whole application. A second actor with the same capability sending a key the first had
  > used got the first one's receipt — its events, with personal fields opened, whatever the second actor's
  > scope — and its own command was not run. Two clients numbering their requests the same way would lose
  > commands without a trace. The lookup and the index are now on the actor's label and the key together
  > (`issued_by`, `idempotency_key`). *Rejected:* a global key with the documentation asking for an
  > unguessable one, which leaves safety to every client and fails silently; the actor's key plus a digest of
  > the command, which `_commands` would hold beside no payload, and which low-variety fields make guessable.
- **Conflicts.** On `:wrong_expected_version` or `:condition_failed` the dispatcher rolls back, reloads,
  decides again, and retries up to three times with jitter — only when it owns the transaction. Inside a
  caller's transaction it returns `{:error, :conflict}`, the same rule `HandlerFailure` follows in v1.

### 10.5 Registry

Every lookup is keyed by the qualified type: `consumers_of(type)`, `event_module(type)`,
`command!(contract, module)`. v1 keys handlers on the event atom alone, so two contracts declaring `:opened`
would receive each other's events; v2 fails boot on a duplicate type. An unknown type read from history
comes back as `%EhOsContract.UnknownEvent{}` — strict on write, defensive on read, as in v1.

### 10.6 Schema evolution

Once data is real, `evolve/2` folds every old event forever — the cost architecture §7–8 and the Commanded
row of design-rationale rejected event sourcing for. v2 answers it with a `schema_version` on every event and
an upcaster callback per type; `check` fails when an event's data digest moves while the log already holds
rows of that type and no upcaster covers the old version.

## 11. Dispatch

```elixir
def dispatch(contract, %mod{} = command, ctx) do
  decl = Registry.command!(contract, mod)
  ctx = Context.new(ctx)            # actor %{kind: :human | :system, subject, roles}, now, correlation, key
  with :ok <- Capability.check(decl, ctx.actor),        # by: roles or system actors; authentication stays with the host
       :ok <- Codec.validate(command),
       :new <- Idempotency.lookup(ctx) do
    retrying(ctx, fn ->
      {state, condition, given} = Loader.load(decl, command)          # snapshot + stream tail, or DCB query
      with {:ok, events} <- Decider.decide(decl, command, state),     # impl.<command>(cmd, state)
           :ok <- Emits.verify!(decl, events) do                      # backstop for §5's compile check
        in_own_transaction(fn -> commit(decl, events, condition, given, ctx) end)
      end
    end)
  end
end

defp commit(decl, events, condition, given, ctx) do
  :ok = Store.lock(repo())
  {:ok, recorded} = Store.append(repo(), Enrich.rows(decl, events, ctx), condition)  # tags, runs, encryption
  Commands.accepted!(decl, ctx, given, recorded)
  Runs.index(recorded)              # _event_runs, inline
  Inline.project(recorded)          # inline projections, in registry order
  Inline.react(recorded, ctx)       # inline policies: nested dispatch, same transaction, cycle guard kept
  Effects.enqueue(recorded)         # Oban.insert_all — the outbox, as in v1
  recorded
end
```

- Two things carry over from v1's `Emitter`: the failure record written after a rollback (now a `failed` or
  `rejected` row in `_commands`, generalizing `HandlerFailure`) and the `chain` cycle guard.
- **Recorded facts (D6).** `EhOsContract.record(contract, %Event{}, ctx)` appends an event that declares
  `recorded_by:` — an observation, or an integration's answer — with the capability check against
  `recorded_by`, the unit's stream condition, no decider, and `evolve/2` folding it as usual.
- After its own commit the dispatcher notifies an `Oban.Notifier` channel (§12).
- **Queries.** `EhOsContract.query(contract, %Q{}, ctx)` checks the capability; an optional
  `ctx.min_position` waits until the backing projection's checkpoint reaches it (`dispatch` returns the last
  position, which is enough for read-your-writes on async projections); then `impl.handle_query/2`. The
  library routes and authorizes; the host's code answers, and queries are not logged — a read is not a fact.

*Corrected 25 September 2026, D14 (§16).* `ctx.actor` carries capabilities, not roles. EHOS's credential
(`eh-os` D-33) lists capabilities in `cap` and names no role, so `Capability.check` cannot compare roles with
`by:`. It asks an `EhOsContract.Authorizer` behaviour whether the actor holds the declaration's capability.
The default implementation compares against the capabilities in `ctx.actor` and records nothing; a `:system`
actor is checked against `by:` or `recorded_by:` alone. A refusal writes nothing to the log or to `_commands`.
Verifying a credential, and the row that records each decision, belong to `eh_os_contract_auth`, which
implements the behaviour.

*26 September 2026, before E6: the `Authorizer`'s shape, as the user accepted it.* **The check stands at the
application's door, and the criterion is where a call comes from, not what kind of actor makes it.** A call
that arrives with a credential is asked of the `Authorizer`. Today that is a person; a system will be too,
once EHOS issues credentials to systems (`eh-os` D-23, G-2). What the application's own code issues is held
to the contract instead: a reaction, to what its `issues:` names; a `:system` actor of the domain, to the
declarations whose `by:` or `recorded_by:` name it. It is not asked of the `Authorizer`, for three reasons:
the application would be asking itself, EHOS issues no credential to a job (`eh-os` D-34), and an inline
policy refused inside the transaction of a person's command would fail that command for a reason that is not
the person's.

- `%EhOsContract.Actor{}` built from a credential carries `subject`, `capabilities` and `scopes` exactly as
  `sub`, `cap` and `scp` are issued, strings included, so the package that builds it converts nothing.
- One callback, `authorize(actor, request) :: :ok | {:error, reason}`. The request names the kind (command or
  query), the capability, the contract and its version, and, for a scoped query, the dimension and the value
  asked for, both as strings in the form `scp` carries. Comparing in that form means a grant value that is not
  of the field's type never matches, instead of failing a cast.
- `EhOsContract.Authorizer.check/2` is the decision itself, pure: `:missing_capability`, `:unscoped_grant` (a
  scoped capability with no values, refused because empty is not "all"), `:outside_scope`. The default
  implementation is `check/2` alone; `eh_os_contract_auth` calls it and adds its row.
- **An implementation can narrow what a credential grants, never widen it.** After `:ok` the engine runs
  `check/2` again from the actor and raises when that refuses. Grants therefore travel in the credential, as
  EHOS issues them (`eh-os` ARCHITECTURE §6.4). The rows a query returns are checked against the actor's
  scopes too, whatever the implementation said.
- **A credential recording an event through `record/3` is refused** until E9 names the capability for it:
  EHOS grants commands and queries only, so nothing could grant it. A `:system` actor records as before.

  > **28 September 2026, E9a:** named and built. An event a person records has the capability
  > `<domain>.<event>` (kind `:record`), asked of the `Authorizer` as a command's is, and served as
  > `POST /records/<capability>`. Only what a person may do has a capability: an event only a `:system`
  > actor records, and a command only a reaction issues, have none (plan, E9a review).

> **26 September 2026, E6 — what the sketch above left open, as built.** `EhOsContract.Dispatcher` behind
> `EhOsContract.dispatch/3`, `record/3` and `query/3`; the modules the sketch names (`Registry.command!`,
> `Capability`, `Loader`, `Decider`, `Emits`, `Enrich`) are steps of it, not modules. **Order**: the actor,
> then the fields (`EhOsContract.Codec`), then the idempotency key, then the stream folded through `evolve/2`,
> the decision, and the decision held to its declaration — an undeclared event or invariant, or an event
> whose fields do not fit, raises and appends nothing. **Rows**: `accepted`, `rejected` with its invariant,
> `failed` with where it failed (`decider`, `evolve`, `read_model:<name>`, `policy:<name>`) and the
> exception's module, never its message; `record/3` writes `accepted` with the type `"record:<event>"`.
> **Inline policies**: a nested dispatch is keyed `"policy:<contract>:<name>:<event id>:<index>"`, one segment
> more than §10.4, because the index of accepted keys spans the application and two contracts may each have a
> policy of one name on one event. A nested dispatch whose command is rejected leaves the first command
> standing, since a rejection is the unit's answer; a nested conflict cannot happen, because the append lock is held from the
> transaction's first append. **Not built in E6**: `Runs.index` and `_event_runs`, effects, `min_position`
> and the notifier (E7); the DCB condition (E9). **Implementations are found by a scan** of the host's
> applications, kept in `:persistent_term` (`EhOsContract.Implementations`), not by the boot registry of
> §10.5; failing boot on a duplicate type is not built either. **HTTP**: `EhOsContract.Plug` serves
> `POST …/commands/<capability>` and `GET …/queries/<capability>` with the actor another plug built.

> *Added 30 September 2026, plan E11f, the user's choice.* **A unit reads only what its `evolve/2` folds.**
> TaxVision's `TurnoverMatching` decoded every statement of the month, each a whole list of turnovers, on
> every match, although its `evolve/2` passes statements over — quadratic in a statement's length. When
> every clause of `evolve/2` that does not name an event struct is exactly `def evolve(state, _), do:
> state`, the implementation records the events it folds (`__eh_os_implementation__/0`, `folds`), and
> dispatch decodes only those. An aggregate still reads its whole stream, whose version is the condition,
> and records every type it met in `given_types`. A boundary's query, and so its conflict condition, is
> narrowed to the folded types: nothing else can change its state, so nothing else can change a decision. A
> boundary that folds none of its events keeps its whole query, since a store query cannot be empty.
> A type the contract no longer declares is still decoded, and stops the stream. `Coverage` compares a
> scenario's `given` on the folded types, since a boundary's `given_types` hold no other. Any other
> catch-all, or a guarded variable, reads everything, as before. *Rejected:* a DSL word listing the folded
> events (`folds [...]` on the unit), which repeats what `evolve/2` already says and can drift from it;
> restructuring the sandbox so the statement lives in a unit of its own, which leaves the trap for the next
> client; leaving it until measured.

## 12. Consumers

- **Inline projections and policies** run in the dispatch transaction. A projection writes only its own
  tables and advances its own subscription row (`UPDATE … SET position = $p WHERE name = $n AND status =
  'running'`; no row means it is being rebuilt and the update is skipped). A policy dispatches nested
  commands, and its internal dispatch goes through the capability check too. Lock order is always the append
  lock, then read-model rows; host code never writes read-model tables, which rules out deadlocks.
- **Effects** run as Oban jobs — unordered, at least once. Job arguments are `%{"effect" => name,
  "event_id" => id}`: the job loads and decrypts the event when it runs, so no payload ever lands in
  `oban_jobs` (closing the hole v1's `Emitter` comment describes, where the queue carried what retention
  meant to remove). The idempotency key is the event id; duplicate facts are stopped at decision time, so v1's
  "an async handler needs `identity`" gate goes — `identity` stays, for per-item promise evaluation. An
  effect records an external result by `record/3`-ing an event as its system actor.
- **Ordered subscriptions** — async projections, process managers, async policies, later the broker relay.
  One `EhOsContract.Subscription` GenServer per consumer, on every node:

  ```elixir
  repo.transaction(fn ->
    case repo.query!("SELECT position FROM eh_os_contract_subscriptions
                      WHERE name = $1 AND status = 'running' FOR UPDATE SKIP LOCKED", [name]) do
      %{rows: []} -> :idle                                   # another node holds it, or it is not running
      %{rows: [[pos]]} ->
        events = Store.read_all(repo, pos, consumer.batch, consumer.types)
        Enum.each(events, &consumer.handle/1)                # projection writes, or one process-manager step
        advance!(name, List.last(events))                    # same transaction: applied exactly once
    end
  end)
  ```

  It wakes on the `Oban.Notifier` notification and polls every second (covering transactions the caller
  owns and lost notifications). Batches are 500 for projections and 1 for anything that dispatches, because a
  dispatch takes the append lock and would hold it for the batch. A failing event is retried with backoff,
  then isolated with `status = 'failing'` and `failed_position` — **never skipped automatically**, because an
  ordered consumer that skips is a read model that silently lies; `--skip` and `--reset` are mix-task
  decisions for a person. Not Oban: its ordered queues are commercial (the reason Oban Pro Workflows were
  rejected in technology-notes §4), and a pump job per subscription would still need the row lock.
- **Supervision.** The `EhOsContract` child becomes a supervisor. At boot: `Registry.load!`,
  `Deployment.record!`, register checkpoint rows and mark changed consumers `stale`, then start the runners —
  unless `subscriptions: :manual`, which tests use together with `EhOsContract.Testing.drain/1`.
- **Process managers and timers.** Each step is one transaction: compute the correlation, load the row,
  `impl` returns `{state, commands, timer_ops}`, dispatch the commands with deterministic keys, upsert the
  row, insert Oban `TimerJob`s with `scheduled_at`, advance the checkpoint. **A fired timer does not call the
  process manager**: the job checks its token is still current and appends `eh_os_contract.timer_elapsed` to
  the stream `$pm:<name>:<correlation>`, and the process manager reacts when its runner reaches that event in
  order. Replay is deterministic because timer firings are in the log, and the observed graph gets its
  timer → command → event edges. ClinicalVisit's 24 hours: leaving the room starts the timer, the clinical
  close cancels it, and when it fires the process manager asks for the documentation — while the
  `reported_or_chased_within_a_day` promise checks that it does.
- **Rebuild.** A consumer whose version digest changed is marked `stale` at boot. An async projection resets
  and catches up. An inline projection flips to `rebuilding` under the append lock, catches up through the
  runner, and flips back under the lock at the head. A process manager replays with reactions suppressed,
  then reconciles pending timers.
- **Snapshots** are off by default (VisitSettlement streams are about 20 events); when on, one is taken on
  read once a stream's tail passes a threshold, and a snapshot whose state schema digest differs is ignored.

> **26 September 2026, E7a — what the sketch above left open, as built.** `EhOsContract.Consumer` is what one
> read model, policy or effect does with one event, shared by dispatch, the runners and the effect job. **The
> policy chain** is a list of `"<contract>:<policy>:<type>"` in the event's `metadata`, so an ordered policy
> continues the chain its event came down. **Effects**: an `:in_transaction` effect acts after the policies and
> its `{:error, _}` rolls back; an `:at_least_once` one is an `EhOsContract.EffectJob` in Oban's `:events`
> queue, and dispatch refuses to insert it when Oban runs on another repo. A job whose effect has no module is
> cancelled. **Subscriptions**: one row per ordered consumer, and one per inline read model, which dispatch
> advances as it projects — a query and an update per inline read model per dispatch. A consumer's version
> is the digest of its declaration and of every event it takes. After a failure the row fences the event:
> the next step applies what precedes it, then the event alone; three attempts, then `failing`. A `stale`
> subscription goes on taking events until it is rebuilt. **Rebuilding needs the implementation's optional
> `reset/0`**, because a read model writes the host's tables (the user's choice); a policy is never rebuilt,
> only takes the new version. **A new ordered consumer starts at position 0** — a new policy reacts to
> history, with keys derived from each event, as Commanded's handlers start from the origin — and a new
> inline read model at the head. **Supervision**: `config :eh_os_contract, subscriptions: :manual` skips
> registration and runners, and `EhOsContract.Testing.drain/1` runs subscriptions and effect jobs inside a
> test's transaction; `mix eh_os_contract.subscriptions` lists them and takes `--skip` and `--reset` (all
> three the user's choices). **Not built in E7a**: process managers and timers (E7b); `_event_runs` and its
> readers (E7c); `min_position` on queries (§11). The notification is not observed by a test, because the
> sandbox never commits; the runners' one-second poll is.

> **26 September 2026, E7b — process managers and timers, as built.** A process manager is an ordered
> consumer, one event a step, with the append lock taken first because it dispatches; P4 now refuses one
> delivered `:in_transaction`. A run is a row keyed by `Key.join` of its correlation values; the state is the
> generated struct in the external term format. **Which reaction**: a `starts_on` event starts a run that has
> no row, an `on` event reaches a running one, anything else changes nothing. The reaction's callback gets the
> event and the state *before* it, as `ScenarioCase` already called it, and then `evolve/2` folds the event.
> Commands go out as `pm:<name>`, keyed `"pm:<contract>:<name>:<source id>:<index>"`. **A timer's token is the
> id of the event that set it**, and `wait:` counts from that event's `occurred_at`, so a replay recomputes the
> same timers. `EhOsContract.TimerJob` is unique on its arguments, snoozes until `Clock.now/0` reaches the
> timer, and appends `eh_os_contract.timer_elapsed` to `$pm:<key>:<correlation>` only while the token is the
> run's; the process manager ignores a firing whose token is gone, which is what makes a timer fired twice
> dispatch once. **A rebuild** forgets the runs, replays with reactions suppressed and, at the head, schedules
> the pending timers again; a stale process manager is rebuilt at boot, since the library owns its table and
> needs no `reset/0`. **A new process manager starts with the same replay**, unlike a new policy (E7a): it
> learns the runs already in the log and steers none of them. At the head a timer that came due with no job
> queued is dropped, because it came due while nothing steered its run; one whose job is still queued, after a
> rebuild of a running process manager, fires.

> **26 September 2026, E7c — a new policy starts like a new process manager.** This reverses the E7a note's
> "a new policy reacts to history" (the user's decision after the E7b review): what is in the log when a
> consumer is first registered is history, and nothing new reacts to history by itself. A policy keeps no
> state, so its replay with reactions suppressed is its registration at the head of the log. Reacting to
> history is a person's `--reset`, which moves the policy back to position 0; the keys derived from each event
> keep what it already issued from being issued twice. An ordered read model still starts at position 0. In a
> host's tests the first `EhOsContract.Testing.drain/1` is the deploy.

## 13. Runs, promises and conformance on the new log

- **Runs.** `process` and `instance_id` are computed at append for the event's home process, as v1's
  `Instance.key` does. An event a contract `include`s into its own process gets a row in `_event_runs` for
  that run too (D7) — an object-centric answer to architecture's review trigger "one event belongs to two
  processes", which v1 made inexpressible. `_event_runs` is an internal inline projection: rebuildable when a
  contract starts including an old type. `Trace` and `Run` read runs from it and keep their arithmetic;
  they measure `occurred_at` (injectable clock), with `position` breaking ties.
- **Paths.** The static graph is command → event (`emits`), event → policy / process manager / effect →
  command (`issues`), and timer → command. Observed edges come from `events.command_id` joined with
  `commands.causation_event_id`.
- **The four questions**, on the richer model: *untraversed* — a declared path no run took (the denominator
  is still distinct runs); *drift* — v2 refuses an undeclared emit or issue at run time, so drift now means
  history under older declarations (`Deployment.declared_edge?`) or rows written outside dispatch; *promises*
  — as v1, per run and per item; *deployed version* — as v1. Two sources change: **in flight** is pending
  effects, scheduled timers and subscription lag; **failing** is failed commands (attributed through
  `failed_in`), subscriptions in `failing`, discarded effects.
- **Scenario coverage.** A scenario is covered when an accepted or rejected command of its trigger type
  carried its `expect` types as a subsequence (v1's `ContractExample` semantics), or the same rejecting
  invariant, and had its `given` types in `given_types`. Matching is by type only — matching on data would
  mean storing command payloads, which is personal data. Two findings follow: a scenario never observed, and a
  decision outcome no scenario declares.

> **26 September 2026, E7c-1 — the verdicts on the new log, as built.** **Runs**: the store writes every run of
> an event in the append that writes it, the home run from the entry's `process` and `instance_id` and the
> included ones dispatch names under `runs:`, from an index of which v2 contracts' processes `include` which
> type (`EhOsContract.EventRun`). A v1 event gets its home run too, and no v1 reader reads the table. Not
> built: filling the table for old events when a contract starts including their type — "rebuildable" above
> is still a sketch. **`Trace` and `Run`** branch on the model; a v2 contract's `promise` and `deadline` are
> judged over `_event_runs` with v1's arithmetic, unchanged, and the v1 queries are the ones they were.
> **Paths**: a step is a command's emit, a policy's or process manager's issue on an event, a timer's issue,
> or an effect on an event (`EhOsContract.Paths`). Taken is counted in runs through `events.command_id` and
> through `_commands.issued_by` with its causation event. An effect leaves nothing in the log when it acts,
> so whether it was taken is unknown: never untraversed, only waiting or failing. **Waiting** is subscription
> lag (only for a consumer with a row), scheduled timer jobs and effect jobs; **failing** is failed commands
> attributed by `failed_in` — a consumer's stage to that consumer's steps, anywhere else to every step the
> command emits — a `failing` subscription, and discarded effect jobs. A step reached from a waiting one, down
> the chain, is not untraversed either: a branch is several steps and only its head waits in a queue. **Drift** is an event of the deployed
> version that no declared command emits, which includes one written around dispatch. **The wire**:
> `conformance.v2` for a v2 contract, `v1` for a v1 one. **Not yet**: the boot records no v2 deployment,
> so the deployed version has no `since`, and a promise's declaration boundary is always `nil`; and
> scenario coverage — both E7c-2.

> **6 October 2026, plan DD, P1a (#183) — a step counts occurrences, not runs.** "Taken is counted in runs"
> above no longer holds. A step belongs to its contract, which may have no process, so it counts how often it
> was taken: the events of its type its command appended, or the command rows its reaction issued, accepted or
> rejected (an idempotent redelivery writes no row). Failed commands count likewise. Two deposits on one account
> are two, where they were one run; the argument for runs — a single busy account would read as a
> well-travelled path — loses to a contract without a process having no count at all. So does the argument for
> failures counted in runs, that a retry loop on one run would read as a wide outage: fifty failures read "50
> commands failed", which is what happened, and a process's runs still say how much of the business a failure
> touches. A process keeps its runs, durations and promises, judged per run as before.

> **8 October 2026, plan DD, S2 — a promise has scenarios, and a scenario's events may be dated.** Until now a
> promise was judged only on the log, so its owner first saw it judged in a report. A process module now carries
> scenarios of its promises: the events and when they happened, the moments an external system was seen
> unavailable, the moment of judgement, and the verdict and route expected. They run as tests through the same
> rules the report applies (`Trace.judge/3`), without a database. An outage in a scenario is only of an external
> that the promise's `eventually` or `or_else` depends on, the same narrowing the report applies. Every scenario,
> a contract's too, may date a given (`at:`); a given's moment never goes back, since a log holds events in the
> order they happened (the user's decision of 8 October: allowed in every scenario, not only a promise's). A
> contract that still declares its own `process` gets no promise scenarios: that form is being removed (#221).
> [#251](https://github.com/EmpoweredHouse/eh-os-contract/issues/251)

> **8 October 2026, plan DD, O1 — the report checks the order of a process's stages.** The stages were an order
> nothing read. The report now counts, per process, the runs that entered a later stage before an earlier one,
> and names the pairs, under a key of its own (`out_of_order`), never among a contract's undeclared transitions:
> it is a claim about the process, and it can be addressed to someone else. Agreed with EHOS
> (EmpoweredHouse/eh-os#297): by position in the log, never by timestamp; only stages a run reached; the period
> takes a run by its first event and does not cut it; a stage entered by its first event; the count and the pairs,
> never which runs. [#260](https://github.com/EmpoweredHouse/eh-os-contract/issues/260)

| Fate | Modules |
| --- | --- |
| Kept unchanged | `Digest`, `Duration`, `Dependency` |
| Kept, extended | `Deployment` (digests for the new kinds, consumer bindings); `Trace`, `Run` (qualified types, runs from `_event_runs`, `depends_on` from the model); `Conformance` and `Conformance.Wire` (new sources; schema `eh_os_contract.conformance.v2`); `Report`, `Report.Sentence` (new sentence kinds); `Graph` (static graph from the model, observed graph through `_commands`) |
| Replaced | `Emitter`, `Payload`, `Emission` → `Dispatcher`, `Store`, `Codec`; `Job` → `EffectJob`, `TimerJob`; `HandlerFailure` → `_commands`; `Handler` → DSL consumers; `ContractExample` → `Scenario`; `Instance` escaping → `Key` |
| Rewritten on the model | `Check`, `AsyncAPI` (public events only), `Telemetry` spans |

## 14. Crypto-shredding

- **Declaration.** The domain declares `subject :patient, "Pacjent"`. An identifier field declares
  `subject: :patient`; a personal field declares `personal: :patient_id`. The model exposes each personal
  field as `{field, subject_type, subject_id_field}`.
- **Gates.** A personal field may not be a unit key, a tag, a correlation or instance field, `identity`,
  process-manager state, or a field of a public event.
- **Writing.** Under the append lock `Enrich.rows` gets or creates the subject's data key with
  `INSERT … ON CONFLICT DO NOTHING`, and refuses the append if the subject has an erasure record. Each value
  is JSON-encoded and encrypted with `:crypto.crypto_one_time_aead(:aes_256_gcm, dek, iv, json, aad, true)` —
  a 12-byte IV, AAD `type|field|subject|key_version`, so a ciphertext cannot move to another field — and
  stored as `{"$eh":"enc1","k":kv,"d":b64(iv<>tag<>ct)}`. Data keys are 32 random bytes, wrapped by a master
  key from an `EhOsContract.Vault` behaviour (configuration by default, a KMS optionally).
- **Rotation.** Rotating the master key rewraps every data key — a table scan, no event rewritten. Rotating a
  subject's data key adds a `key_version` for new events; old versions stay until erasure deletes them all.
- **Reading.** `Codec` fetches every key a batch needs in one query. A missing key yields
  `%EhOsContract.Erased{subject: …}` in that field, and generated types admit `Erased.t()` on personal
  fields, so `evolve/2` has to tolerate it. There is deliberately no long-lived key cache: a cache on another
  node would outlive an erasure.
- **Erasure.** `EhOsContract.erase(type, id, ctx)` is one transaction under the append lock: delete the keys,
  insert the tombstone, delete snapshots whose `subjects` contain the subject, append
  `eh_os_contract.subject_erased` (no personal data in it), run the inline projections' `forget/2`. Async
  projections get the same event in order; a projection that consumes personal fields without `forget/2`
  fails boot.
- **After erasure.** Process-manager state holds nothing personal (by the gate), Oban jobs hold ids, `_commands`
  holds no payloads and rejections are invariant names. **Conformance reads only types, times, instance ids,
  identities and tags, so erasure changes no number by construction** — pinned by a golden test in E8. The log
  still says that subject p-17 had a visit on 3 September, and that is the point.
- **For the product owner, not for engineering:** backups, WAL and replicas keep data keys until they expire
  (the key store can move behind the behaviour to shorter retention); and whether destroying a key counts as
  erasure is a question for counsel (EDPB, UODO).

> **27 September 2026, E8a — what the build settled.** (1) The vault's `wrap` and `unwrap` take a context, the
> data key's row (`subject_type|subject_id|key_version`), bound as additional data, so a wrapped key moved to
> another subject's row does not unwrap; a KMS takes it as an encryption context. The vault also has `current/0`
> and `check/0`: the engine refuses to boot when a contract declares personal fields and the vault cannot seal
> them, and `mix eh_os_contract.rewrap` rewraps what a retired master key wraps. The default vault takes a list
> of master keys from configuration, the first wrapping (decision of the user, 27 September). (2) The field's
> path in the AAD is dotted, `contacts.phone`, with no list index. (3) A personal field left `nil` is stored
> `nil`, not sealed: absence is not personal. (4) **Snapshots do not exist** — §10.3 describes their table and
> no migration creates it — so erasure has none to delete; whoever builds them adds `subjects` and the deletion.
> (5) **`key_version` is always 1**: rotating a subject's data key waits for someone who needs it (both by the
> user's decision, `PLAN.md`, E8). (6) The keys a reader needs are found from the declared fields: a sealed
> field's subject is its sibling's value, so the envelope carries no subject.

> **27 September 2026, E8b — erasure as built.** (1) `erase/3` is host-gated and idempotent: `actor:` is
> recorded, no `Authorizer` is asked, and it never returns `{:error, _}` (it raises only on a subject no domain
> declares). It says what it found — `{:ok, :erased}`, `{:ok, :no_data}` (no data key for that id, recorded all
> the same) or `{:ok, :already_erased}`, which
> appends nothing (decisions of the user; the result replaced a plain `:ok` after the E8b review, since a
> mistyped id was indistinguishable from an erasure). (2) The refusal is narrower than "an append for the subject": an event is refused,
> `{:error, :subject_erased}`, only when it carries personal data of an erased subject — the one case where
> a key would be created again. An event naming the subject's id and nothing personal is appended. The
> check runs under the append lock, after `prepare/2` and before anything is stored or sealed, and writes no
> `_commands` row; over HTTP it is `410`. (3) `eh_os_contract.subject_erased` is stored with `contract:
> "EhOsContract"`, no stream and no run, so no contract's conformance reads it. (4) A read model takes the
> event only when it projects personal data, and `forget/2` is called only for the subject types whose data
> it projects (`Codec.personal_subjects/2`); a read model that projects personal data without `forget/2`
> fails boot. (5) A missing key reads as `Erased` only for a subject in `eh_os_contract_erasures`; any other
> missing key raises (E8a review).

## 15. Integration hooks — designed, not built

- `public: true` marks an event as published language: a stable subject such as
  `eh.<context>.<event>.v<schema_version>`, and no personal fields.
- A broker relay is another subscription kind: it publishes to NATS JetStream with `Nats-Msg-Id = event.id`
  (JetStream deduplicates on it) and advances its checkpoint after the PubAck. A receiving application turns
  incoming events into commands, the source event id as idempotency key.
- Architecture §9–10 ("no external broker") gets its dated correction when this is built, not before.

> **25 September 2026, after E1:** superseded by D11 and D12 (§16) and stage E12 in `PLAN.md`. The relay stays
> a subscription over the log, but it publishes through an `EhOsContract.Bus` behaviour rather than to NATS
> directly, and the receiving side is an inbox, not a direct command.

## 16. Decisions taken with the plan, and findings

Recommended in the plan and accepted with it on 25 September 2026. Any of them can be reopened; reopening
one is a dated note here.

| | Decision |
| --- | --- |
| D1 | Names: `emits:` (ESDM says `publishes`); `promise` instead of `trace`, which collides with process mining's "trace" (one case's event sequence); event type `"<process>.<event>"` (*changed 6 October 2026, plan DD, ID3: `"<contract id>.<event>"`, §8*); actor kinds `:human \| :system`, ESDM's pair — a service is a `:system` actor `backed_by` an external. |
| D2 | Migrations collapse into one version at the cut, as V01 did ("the final shape, not the history"). |
| D3 | A contract without an implementation stays legal (Rehmed, the invented fixtures); `check` notes it. |
| D4 | ESDM's rules split as §6 does: structural rules are L2/L3 errors, completeness rules are L5 warnings. |
| D5 | Stages by nesting inside units, and `include` for foreign events. |
| D6 | The 15 events no command publishes — observations and integrations' answers — declare `recorded_by:` and enter through `record/3`; no command name is invented, which "names come from the workshop" forbids. |
| D7 | An event included in another contract's process belongs to that run through `_event_runs`. |
| D8 | F1 and F2 go to the process owner; they do not block. |
| D9 | One branch per stage, small commits with the gate green; pushing, pull requests and merges are the user's. |

Findings from rewriting VisitSettlement:

- **F1 — where the total comes from.** A pure decision cannot compute `visit_handed_over.total`: service lines
  carry no price and the handover carries no amount. §4.5 lets the application supply `total` with the
  command; the model owner has to decide.
- **F2 — which day a correction belongs to.** v1 says the date is "stamped by the system" and also "the day it
  belongs to". §4.5 takes it from the handover date in the state; stamping the dispatch time would reproduce
  the incumbent's defect.
- **F3 — two workarounds retire.** `optional:` makes DEC-05's mixed-payer case expressible, and `unit:`
  replaces the `_minor` naming convention.

### Added 25 September 2026, after E1: D10–D12

Taken after reading EHOS's architecture (`eh-os`: `docs/ADR.md` D-01, D-03, D-04, D-15, D-16, D-34, G-9,
G-14, G-16; `docs/ARCHITECTURE.md` §3). Two of them contradict decisions recorded there; the list of what
`eh-os` would have to correct is in `PLAN.md`, because this repository does not write there.

| | Decision |
| --- | --- |
| D10 | **A query is part of the agreement and grants a capability.** It is derived exactly as a command's is, from the declaration, never written as a separate string. `scope` narrows it to rows: it names a field of the read model, every actor in `by:` must carry that field as a scope dimension (`actor :reception, :human, scope: [:clinic_id]`), and a grant carries the values. Contradicts `eh-os` D-01 (queries are not in the contract) and narrows the third permission surface of its D-15, which leaves query authorization to the application. |
| D11 | **An event crosses to another application only through a `publish` declaration.** A `publish` names a versioned integration event under the application's own namespace, the domain event it comes from, a subset of that event's fields and the fields that make two deliveries the same fact (`eh-os` D-04). `public: true` retires. Inside one application, `consumes Contract, events` of a sibling process stays, without a flag, checked by the compiler as §7 says. |
| D12 | **A received integration event goes to an inbox, not into the domain log.** The inbox row and the reaction commit together; the reaction's own fact carries the source message as its cause. `include` (D7) therefore covers only events in the same log; a run across two applications is correlated by `correlation_id` and assembled by EHOS (`eh-os` G-14). |
| D13 | **Options stay beside a `do` block; the library supplies the missing arity.** Taken 25 September 2026, after E3 found that `command :x, "L", by: [:a] do … end` is a four-argument call that Spark's entity macros (positional args plus one options list) do not define. The user chose to keep the shape of §4.5–4.6 over writing options inside the block: the contract a process owner reads keeps "name, label, who, what it emits" on one line and fields in the block. For every entity that takes a block, the library defines one more arity that moves the block into the options, `command(name, label, opts, do: block)` → `command(name, label, opts ++ [do: block])`, which Spark's macro reads as `opts[:do]` (checked on `context` in E3). The wrappers are generated from the entity definitions, not written by hand. **Conditions, pinned by tests in E4's first commit:** a DSL error still points at the file and line of the declaration, not at the wrapper; the formatter keeps the four-argument form without parentheses in a consumer (the wrappers' arities are exported beside `spark_locals_without_parens`, which does not list them); the domain DSL gets the same wrappers. If either of the first two fails, the fallback is options inside the block, and the question returns to the user. |
| D14 | **The contract declares who may act; a separate package verifies who is acting.** Taken 25 September 2026, after comparing v2 with stage 4 of `eh-os` (D-32, D-33, D-34, D-40): v2 cited `eh_os_contract_auth` as if it existed, no stage built it, and §11 checked roles that EHOS's credential does not carry. The user kept the contract library to its DDD scope and put authentication beside it, for now as a third package in this repository. The contract names the actors that may issue a command or a query (`by:`; actors are roles, §18) and derives the names EHOS relies on: a capability is `<domain>.<command>` or `<domain>.<query>`, a role `<domain>.<actor>`, with `<domain>` the domain's `name:`, so a command or query name is unique across an application, not only within a contract. `dispatch` and `query` ask an `EhOsContract.Authorizer` behaviour (§11, corrected). `eh_os_contract_auth` implements it: it verifies EHOS's credential against keys it keeps in the application's database, builds `ctx.actor` from `sub`, `cap` and `scp`, and records every decision in its own table. The engine does not depend on it. A scoped capability with no granted values is refused. The package's manifest task projects the model onto `ehos.manifest` (E10). |

> **27 September 2026, EA — the two rows of an accepted command are two facts.** D14 left open that an accepted
> command is written twice, once in the auth package's table and once as `accepted` in `_commands`. It is not one
> fact: the engine asks the `Authorizer` before its transaction, so the package's row records that the credential
> allowed the call, and `_commands` what became of the command, which may still be rejected on an invariant or fail
> in code. Both stay. The package is `eh_os_contract_auth`: `EhOsContract.Auth` is the `Authorizer`, one row per
> decision in `eh_os_contract_auth_decisions`; `EhOsContract.Auth.Plug` verifies the bearer credential; a credential
> that does not verify gets 401 and no row, since it names nobody. `PLAN.md`, stage EA, has the rest.

> **25 September 2026, E4's first commit — D13's conditions hold, and one assumption under them was
> wrong.** `EhOsContract.DslWrappers` generates the wrappers from the entity definitions and imports them where
> Spark imports the entities: a top-level entity's through the section, a nested one's through its parent.
> Both conditions are pinned in `test/dsl/dsl_wrappers_test.exs` and, in a consumer, in
> `sandbox/test/rehmed_domain_test.exs`. A refusal beside a wrapped block, whether Spark's schema check or
> a D rule, carries the declaration's file and line. The formatter keeps the four-argument form without
> parentheses, **but not because of an export**: it never adds parentheses to a call that has a `do` block,
> whatever `locals_without_parens` lists. The wrappers' arities are therefore not exported, and
> `spark_locals_without_parens` stays what `mix spark.formatter` writes. One thing D13 did not foresee: an
> entity with an optional positional argument already has the arity its shorter wrapper would take.
> `value :address, label: "Adres" do … end` reaches Spark's `value(name, type, opts)` with the keyword list
> in `type`. Without a block, Spark itself reads a keyword list in the last optional argument as options.
> The wrappers give such an entity a `transform` that applies the same rule when a block follows, and that
> checks the options against the entity's schema. Spark checks the argument's own type before any transform
> runs, which `consumes "<name>", as: :x do … end` showed later the same day (its optional argument is a list
> of atoms), so the wrappers also widen that type to accept the keyword list the transform moves out. A contract entity that takes a block therefore never gives
> an optional positional argument a keyword list as a legal value.

**D10 in the contract and in the implementation.**

```elixir
# in the domain
actor :reception, :human, "Recepcja", scope: [:clinic_id]

# in the contract
read_model :open_visits, "Wizyty do rozliczenia", projects: [:visit_handed_over, :payment_recorded,
                                                             :visit_closed_commercially] do
  field :clinic_id, :id
  field :total, :money
  field :paid, :money, default: 0
end

query :open_visits_for_clinic, "Otwarte wizyty w przychodni",
  reads: :open_visits, by: [:reception], returns: :many do
  param :clinic_id, :id
  scope :clinic_id
end

# the implementation
defmodule Rehmed.Settlement.Queries do
  use Rehmed.Contracts.VisitSettlement, query: :open_visits_for_clinic

  @impl true
  def open_visits_for_clinic(%OpenVisitsForClinic{clinic_id: id}, _ctx),
    do: Repo.all(from r in OpenVisits.Row, where: r.clinic_id == ^id)
end
```

- **Checked at compile time (L2):** the `scope` field is a field of the read model and a `param` of the
  query, with the same type; every actor in `by:` declares it as a scope dimension; a query without `by:` is
  refused, since nobody could be granted it.
- **One authorization path for commands and queries** (§11): the credential is verified locally by
  `eh_os_contract_auth` (`eh-os` D-34); the principal's type is in `by:`; a grant for this application and
  environment carries the capability; the `scope` parameter is within the grant's values; the implementation
  runs; every returned row's `scope` field is checked again, so a wrong `where` cannot leak another clinic's
  rows. A refusal is recorded, as for commands; an accepted query is telemetry rather than a row, because reads
  outnumber writes by orders of magnitude. A query writes nothing to the log, so conformance does not see it.
- **What `scope` does not do:** one field, equality against granted values. "Only the visits I took" is
  still the implementation's rule, and so is anything that depends on more than one field. Whether commands
  get the same `scope` is open (§19).
- **Reached the same way from everywhere** (`eh-os` D-12): in the same application `EhOsContract.query/3` is a
  function call; from outside, `EhOsContract.Plug` mounted in the host's router serves the commands and queries
  of the model (`POST …/commands/<capability>`, `GET …/queries/<capability>`), and the OpenAPI document and the
  generated client come from the model, not from the running server.

*Corrected 25 September 2026, D14.* "The principal's type is in `by:`" and "a grant … carries the capability"
are one check, the one §11's note describes: the capability is in what the verified credential grants.
"A refusal is recorded" means by the `Authorizer` that `eh_os_contract_auth` implements, not by the engine.
The grant's values arrive as the credential's `scp` (`eh-os` D-40, proposed), as sorted strings, so the check
casts them to the field's type; a scoped capability without an entry there is refused.

**D11 and D12, from both sides.**

```elixir
# the publisher: Rehmed
publish :visit_closed, as: "rehmed.visit.closed.v1",
  from: :visit_closed_commercially,
  fields: [:visit_id, :closed_at],
  idempotent_on: [:visit_id]

# the subscriber: another application
consumes "rehmed.visit.closed.v1", as: :visit_closed do
  field :visit_id, :id
  field :closed_at, :timestamp
end

policy :invoice_on_visit_close, "Faktura po zamknięciu wizyty",
  handles: :visit_closed, issues: :add_invoice_line
```

- **Refused at compile time:** a `publish` naming a field the source event does not have, or a `personal:`
  field (a copy on a broker cannot be crypto-shredded, §14), or a name outside the application's namespace
  (`eh-os` C-2); `idempotent_on` naming a field outside `fields`; a `consumes "<name>"` whose policy matches a
  field the declaration does not list.
- **What each side knows.** The publisher knows only that the event leaves; it never names a subscriber. The
  subscriber's `consumes` derives the capability `rehmed.visit.closed.subscribe`, which the application
  requests and an owner grants per environment (`eh-os` D-10); EHOS turns the grant into a route of its v1
  relay or a broker consumer and its ACL, which closes `eh-os` G-16 once a broker exists.
- **Relay.** One more ordered subscription over the log (§12): for every event with a `publish`, it builds the
  message from `fields`, gives it the id `<source event id>/<publish name>`, calls `EhOsContract.Bus.publish/2`
  and advances its checkpoint on acknowledgement. The log is the outbox; there is no outbox table to prune.
- **Inbox.** The subscriber's runner takes messages from `Bus`, and in one transaction writes
  `(name, message id)` to the inbox table (a duplicate is acknowledged and dropped), runs the policy and
  dispatches its command with `causation_id` set to the message id and `correlation_id` taken from the
  message; it acknowledges after the commit.
- **`EhOsContract.Bus`** is a behaviour: publish a batch with ids, subscribe a durable consumer by name,
  acknowledge. The library ships a local adapter for tests and one application; the transport adapters (EHOS's
  v1 relay, JetStream through `gnat`) are EHOS's, and one shared test suite runs against every adapter. The
  library does not depend on NATS.

> **7 October 2026, #180 — where the namespace comes from.** The rule that every published name, and since the
> contract ids moved to `id:` (ID1–ID4) every contract's `id:`, lives under "the application's own namespace" (D11)
> left that namespace to the domain's `name:`, a literal the developer writes. Nothing tied it to the application
> EHOS registered, so two applications naming their domains alike would publish on each other's names. The
> namespace is the EHOS application's name: the domain's `name:` must equal it exactly, so it is itself a name EHOS
> takes (lowercase letters, digits and dashes), as the manifest generator already required; `:my_shop` matches
> neither `my_shop`, which EHOS never issues, nor `my-shop`. EHOS enforces it, by a bus credential that allows
> publishing only under the registered name and by refusing such a manifest at registration
> (EmpoweredHouse/eh-os#201). The library checks it early: `eh_os_contract_auth` refuses to start when its
> configured `audience` is not `<application>/<environment>` with both parts present, when that application is
> the name of no domain with contracts (advising the dashed rename when a domain differs only by `_`), or when
> another domain in the same application publishes, since it would publish under a name that is not the
> application's; it checks whenever it starts, since it requires an `audience`. A release may hold other domains
> with contracts, as the sandbox does, as long as only the application's own publishes.
> ([#180](https://github.com/EmpoweredHouse/eh-os-contract/issues/180))

> **1 October 2026, before E12 — what the relay guarantees, and what `Bus` does not.**
>
> - **Why the log can be the outbox.** With event sourcing the state change and the fact are one append: a
>   unit's state is the fold of its events, so there is no table written beside an outbox row, and nothing
>   to tear apart. The relay reads only committed events and, by §10.2, sees positions in commit order, so it
>   neither publishes a fact that did not commit nor skips one that committed late. It advances its
>   checkpoint only after `Bus` confirms the batch, so a relay that stops between the two publishes the batch
>   again under the same message ids. A message can therefore arrive twice at a consumer subscribed when it
>   was published, never zero times and never without its fact. The inbox makes a second arrival harmless;
>   deduplication by the transport (JetStream's `Nats-Msg-Id`) is welcome and not required. What a consumer
>   subscribed later gets is the adapter's (`EhOsContract.Bus` promises only what is published after it
>   first subscribed), so when a subscriber's consumer is created, relative to the publisher's relay, is
>   E12c's to settle.
> - **Not through Oban.** An effect's Oban job is an outbox because the effect calls a system no transaction
>   reaches, and the job is inserted in the event's transaction (§11, `technology-notes.md` on Oban). A relay
>   built the same way, a job per published event, was rejected: `oban_jobs` would be a second outbox beside
>   the log; jobs carry no order, where the log's comes free; and what has left would be the state of many
>   jobs instead of one position.
> - **`Bus` promises no order.** Messages of one publisher leave in log order, but a subscriber may receive
>   them in any order, and after a redelivery an earlier message may arrive after a later one. Between two
>   publishers there is no order to keep. *Rejected:* order per publisher, which narrows the transport to a
>   serial consumer (JetStream with one unacknowledged message at a time, or HTTP sent serially to each
>   subscriber) and lets one message a subscriber cannot take stop everything behind it; order per key
>   (`publish … ordered_by:`), a new DSL key and partitioned consumers before any subscriber has asked for
>   it. The price: a subscriber whose reaction depends on two messages arriving in order waits for both, with
>   a process manager. Adding order later is additive, since a subscriber written for no order still works,
>   and the reverse would break every subscriber that relied on it; so a later `ordered_by:` goes in beside,
>   and an adapter that cannot keep it refuses the publication instead of dropping the order silently.

> **1 October 2026, E12b, as built — the relay.** `EhOsContract.Relay`: one ordered subscription per `publish`,
> keyed `"<contract>:relay:<name>"`, fed by the same runner and rows as a policy, reading up to 100 events of
> the one type it publishes. Four things the text above left open:
>
> - **The id's second half is the versioned name** (`as:`, `"rehmed.visit.closed.v1"`), not the declaration's
>   name, which stays inside the publisher as its source event does (`eh-os` D-41 leaves the source out of the
>   manifest for that reason). Two publications of one event — `v1` beside `v2` while consumers move — still
>   get two ids.
> - **`{:error, reason}` from the transport is not a failure of the event**: no attempt is counted, the position
>   holds, and the runner tries again after five seconds. Counted like a policy's, a broker outage of a few
>   seconds would leave the relay `failing` for a person to restart, and skipping would lose the event. A raise
>   is a defect and is counted; three, and the relay stops at that position.
> - **With no bus configured, the relay waits.** Its row is written at the first boot and its position holds,
>   so configuring a bus later publishes everything since. *Rejected:* refusing to boot — a host that publishes
>   but runs no broker in development could not start; registering the relay only once a bus exists — it would
>   start at the head then, and what was appended in between would never leave.
> - **It starts at the head of the log**, as a policy does: a `publish` added to a contract with history does
>   not publish that history. A rebuild moves it to position 0, and it publishes the log again under the same
>   ids.
> - **The broker is called inside the step's transaction**, which keeps one publisher per relay across nodes
>   (the row is taken `FOR UPDATE SKIP LOCKED`) at the price of a pooled connection held while it publishes;
>   so `EhOsContract.Bus.publish/2` has to return within seconds, well under the repo's timeout. *Rejected:*
>   publishing outside the transaction and advancing afterwards only if no one else did — no connection held
>   over the network, but every node would publish every batch, multiplying the traffic on the broker, and
>   the failure bookkeeping would race. Decided by the user after the E12b review.
> - **`{:error, _}` is only for what retrying fixes.** An adapter raises for a message the broker refuses for
>   good (over its size limit, say), so the relay stops at it instead of retrying it forever out of sight.

> **1 October 2026, E12c, as built — the inbox.** `EhOsContract.Inbox`: one durable consumer per
> `consumes "<name>"` that a policy handles, `"<contract>:inbox:<name>"`, which decodes each delivery into the
> contract's received struct and, in one transaction, writes its row to `eh_os_contract_inbox` and runs the
> policies, acknowledging after the commit. Where the text above was not enough:
>
> - **A row is keyed by the message's key, not its id**, and the key travels with the message, a fifth field
>   of `EhOsContract.Bus.Message`: the SHA-256 of the versioned name and the `idempotent_on:` values, which the
>   relay computes over an encoding that frames each value by its length (`Digest.document_digest/1`), so a
>   delimiter inside a value cannot give two facts one key. A redelivery and the same fact under a new id
>   (`eh-os` FM-04 and FM-08) find the row. The
>   id stands in for the key when a publication declares no `idempotent_on:`, or one of its values is `nil`,
>   which identifies nothing. The publisher's declaration says what one fact is, as D-04 has it, and a
>   publisher whose `idempotent_on:` is too narrow loses a second, real fact to it. *Rejected, by the user:*
>   keying by the id alone and leaving FM-08 to the subscriber's unit — every subscriber writes the same check,
>   and the publisher's `idempotent_on:` serves no one; an `idempotent_on:` of the subscriber's own on
>   `consumes` — a second copy of the publisher's declaration, free to drift from it.
> - **The cause is the inbox row, not the message.** The text says the command's `causation_id` is the
>   message id; a cause is a UUID in both tables that hold one, and a message id, `<event id>/<name>`, is
>   not. The policy's commands name the row's id, and the row holds the message id.
> - **Only a policy takes a received event**, which the text implied by naming only the policy. A read model,
>   an effect or a process manager that names one is refused (`D12`): a read model is rebuilt from the log and
>   the other two read theirs from it, where the event never is. One that reacts to such an event takes what a
>   policy's command records; that is also how a subscriber waits for two messages with a process manager, as
>   the note on order above says it does.
> - **When the consumer exists**, which the note before E12 left open. The engine starts every inbox before
>   any relay, and `EhOsContract.Bus.consumer/2`'s child is subscribed once it has started, so in one node —
>   two applications on `EhOsContract.Bus.Local` — nothing a relay publishes, its backlog at boot included, is
>   published before its subscriber listens. Between nodes the durable consumer is the transport's, created
>   when EHOS grants `<name>.subscribe` (`eh-os` D-41), and what was published before the grant is history,
>   which comes from the owner, not the bus (`eh-os` D-03). *Rejected, by the user:* a durable consumer
>   registered at the first boot, through a third callback of `Bus` — the application would create the
>   consumer the grant is meant to control; leaving it to the transport, with `Bus.Local` keeping everything
>   for a new consumer — a subscriber deployed later would react to the publisher's history, where nothing
>   new reacts to history by itself (§12).
> - **A transport that is down stops nothing.** Each inbox is kept by `EhOsContract.Inbox.Keeper`, which
>   starts the consumer in its own `init`, so the order above holds when the bus is up; starts one that
>   stopped after running again at once, as a supervisor would; and logs one that does not start, or stops
>   again at once, and starts it five seconds later: a transport that refuses does not fail the boot, and the
>   supervisor's restart intensity does not take the runners and relays down, as a relay with no bus waits.
>   An adapter's start has to return quickly for this to hold, since the boot waits for it.
> - **Who may publish is the transport's.** The inbox takes what its consumer is delivered, key and
>   correlation included; the grant that limits who publishes under a name is the transport's, by the same
>   D-41 that limits who subscribes.
> - **What it does not acknowledge.** A message that does not fit the fields the contract consumes, and one
>   whose policy raises, rolls back and is answered `:nack`, logged by name, id and kind of failure: nothing is
>   lost while the declaration or the code is put right. The inbox counts no attempts; the transport's limit
>   (JetStream's `MaxDeliver`) stops a message that never succeeds.
> - **`<name>.subscribe` drops the version**, as the example above has it: `consumes "rehmed.visit.closed.v1"`
>   asks for `rehmed.visit.closed.subscribe`. It is in `EhOsContract.Model.capabilities/1` with no roles, the
>   application's and never a person's, and nothing in the engine asks for it; only for an event a policy
>   handles, since only then is there an inbox to read what the grant delivers.
> - **What the policy is told.** The received struct's `__meta__` has the message's correlation, so the
>   subscriber's facts join the publisher's run, and the row's id; no position, no actor and no time, which the
>   message does not carry.

## 17. Risks

| Risk | Mitigation |
| --- | --- |
| The architecture becomes the project — one of architecture.md's own falsifiers | a kind enters only with its reader; every stage closes with a `PLAN.md` entry; E3 can stop the DSL half |
| Spark: verifier errors are warnings; completion only in ElixirLS (Expert has none yet); code generation costs compile time; one lead maintainer | no rule on verifiers (§6); version pinned to `~> 2.7.3`; E3 pins error locations, `boundary`, formatter and digest stability with tests |
| Global lock throughput and hold time | inline work kept cheap; telemetry on lock wait and hold; `xid8` as the escape hatch (§10.2) |
| Event schema evolution | `schema_version`, upcasters, the `check` rule (§10.6) |
| The Ecto SQL sandbox against long-running subscriptions: the lock lives to the end of a test, LISTEN never fires, runners run outside the sandbox | database tests stay `async: false`; `subscriptions: :manual` with `drain/1`; unique stream ids per test; never `MIX_ENV=test mix run` |
| A poison event blocks an ordered consumer | `failing` status and a report finding; never a silent skip |
| Replaying a process manager dispatches again | reactions suppressed in replay; deterministic keys; timers as events |
| Personal data in error text, logs, telemetry or job arguments | rejections are atoms, errors truncated, no payloads in telemetry or jobs |
| Crypto-shredding's legal standing | §14; the owner's question, not ours |

## 18. What v2 reverses in the v1 record

Each correction is a dated note under the original claim, added in the stage whose code confirms it.

| Claim | Where | Stage |
| --- | --- | --- |
| "We need event *history*, not event *sourcing*", and the rejection of Commanded and full CQRS/event sourcing — say which of its reasons (aggregates, upcasting, "harder for a model to generate") v2 now accepts, and what still holds ("kept from it: the correlation model") | design-rationale | E6 |
| The Ash paragraph ("worth borrowing the declarative-resource idea"): Spark adopted, Ash's runtime still not | design-rationale | E3 |
| §7–8: the log written in the state change's transaction → the append *is* the state change; retention `:hash` / `:drop` → crypto-shredding | architecture, design-rationale §7–8, technology-notes §3 | E6, E8 |
| §9–10: the dispatch split survives as inline against async; handlers become projections, policies and effects; "no external broker" is still true | architecture, design-rationale, technology-notes §4 | E7 |
| §15 "version one watches, it does not steer" → process managers steer and promises watch; the 22 September note "no list of the events it emits" reversed by `emits:`, checked at compile time and dispatch | architecture §15, design-rationale §15, technology-notes | E6–E7 |
| §18: a rule by example → an invariant with Given-When-Then scenarios; `given` becomes a list of events; the decision stays in code | architecture, design-rationale | E5 |
| The review trigger "one event belongs to two processes" → answered by run membership (D7) rather than made inexpressible | architecture, review triggers | E7 |
| technology-notes §1 (the DSL), §2 (enforcement), §12 (prior art: ESDM added; the EventCatalog-like renderer built), §13 (Spark; own store and dispatch) | technology-notes | E4–E10 |

Still valid: §2 — the contract is code and the only source, with no YAML beside it; §5–6; §11–12; §13's three
layers; and [identity seam](identity-seam.md) — ESDM's actors are roles, not identities.

> *29 September 2026, E11d.* Every row above has its dated note: the last, technology-notes §1, §2, §12 and
> §13, went in with the cut, which deleted the v1 code those sections describe.

## 19. Open questions

- The ten defects found in the four contracts (`PLAN.md`, 25 September) stay questions; ports translate, they do
  not fix. Defects 2 (the TaxVision window belongs in `unverified`) and 5 (`open_month` has a source in
  US-MON-01) go in as one-line changes with their citations.
- `consults … where:` is prose, so nothing checks it mechanically; whether some criteria can be `match`es is a
  modelling question per boundary.
- H177 in the Rehmed material makes the handoff a conditional command and moves the price freeze to settlement,
  contradicting DEC-18, on which `visit_handed_over` stands. It waits for ratification.
- The upcaster contract — one callback per type and version, or a chain — is decided in the stage that first
  needs it.
- Whether commands get `scope` as queries do (D10). The TaxVision material has the case
  (`actor_company == company_id`, `PLAN.md` 22 September, step C).
  > **28 September 2026, E9c — answered.** They do, the user's choice of 27 September (plan, "Po E8 —
  > kolejność zmieniona"): `command :open_month, "…", by: :accountant, scope: :company_id`. The scope is one
  > of the command's fields — its unit's identity or declared, and required; the command names `by:`; every
  > actor in `by:` carries the dimension; the field is not personal (F7). Dispatch asks the `Authorizer`
  > with the field's value, as it asks for a scoped query, and `EhOsContract.Plug` asks with the value as it
  > was sent when a command does not decode. `Model.capabilities/1` gives the command its `scope:`. What it
  > still does not do is what query `scope` does not: one field, equality against granted values.
- What carries a message between two containers in EHOS's v1, where `eh-os` D-03 names "an in-process relay":
  only EHOS can answer, and only the `Bus` adapter depends on it.
- The shape of the API EHOS will read: `Model.to_data/1` gets a named schema in E10; transport and versioning of
  that API are EHOS's to specify.
