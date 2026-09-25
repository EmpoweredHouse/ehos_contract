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

- **Identity is injected.** A unit's identity fields appear in its state, commands and events without being
  declared there; declaring one again is an error.
- **Stage membership is nesting.** Local events sit inside `stage :payment do … end` in their unit; foreign
  events are placed with `include` inside `process`. The order of `stage` entries in `process` is the order
  of stages.
- **Durations.** `within`, `deadline` and `wait` accept only the fixed units of `EhOsContract.Duration`;
  `cadence` may also use calendar units.

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
  handles: :registry_discrepancy_detected, calls: :mail, idempotency: :downstream

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
- *Fields.* F1: unique in a struct, none starting with `__`. F2: well-formed types; an enum is a non-empty
  set with no member repeated (`:open` beside `"open"` counts). F3: `default:` only in `state`. F4: fields
  used as identity, correlation, `match` or tags are neither `optional:` nor `personal:`. F5: `personal: f`
  needs `f` to be a required, non-personal `:id` field of the same struct declaring `subject:`. F6:
  redeclaring an injected identity field is an error.
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
- *Domain.* D1: unique names per kind. D2: at most one translation per language, none into the context's
  own. D3: a value has exactly one of type or fields; `unit` only on numeric types; no cycles. D4: a human
  actor has no `backed_by`. D5: relation roles fit the type; endpoints exist; no relation to itself.

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

### 10.3 Schema

Final shape. E2 reaches it by altering v1's table in place, so v1 keeps running until E11 collapses the
migrations (D2).

```sql
CREATE TABLE eh_os_contract_events (
  position         bigint GENERATED ALWAYS AS IDENTITY (CACHE 1) PRIMARY KEY,
  id               uuid NOT NULL UNIQUE,
  type             text NOT NULL,                -- "<process>.<event>"
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
- **Idempotency.** The host supplies `ctx.idempotency_key` (opaque, never personal data). It is checked before
  loading and again under the lock; a hit returns the earlier events with `duplicate: true`; a hit for another
  command type is `{:error, :idempotency_key_reused}`. Only accepted outcomes bind the key, so a rejected
  command can be retried once state has changed. Internal dispatches — policy, process manager, effect, timer
  — get deterministic keys, `"<issued_by>:<source_event_id>:<index>"`, so redelivery cannot append twice.
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

## 15. Integration hooks — designed, not built

- `public: true` marks an event as published language: a stable subject such as
  `eh.<context>.<event>.v<schema_version>`, and no personal fields.
- A broker relay is another subscription kind: it publishes to NATS JetStream with `Nats-Msg-Id = event.id`
  (JetStream deduplicates on it) and advances its checkpoint after the PubAck. A receiving application turns
  incoming events into commands, the source event id as idempotency key.
- Architecture §9–10 ("no external broker") gets its dated correction when this is built, not before.

## 16. Decisions taken with the plan, and findings

Recommended in the plan and accepted with it on 25 September 2026. Any of them can be reopened; reopening
one is a dated note here.

| | Decision |
| --- | --- |
| D1 | Names: `emits:` (ESDM says `publishes`); `promise` instead of `trace`, which collides with process mining's "trace" (one case's event sequence); event type `"<process>.<event>"`; actor kinds `:human \| :system`, ESDM's pair — a service is a `:system` actor `backed_by` an external. |
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
- The shape of the API EHOS will read: `Model.to_data/1` gets a named schema in E10; transport and versioning of
  that API are EHOS's to specify.
