# Technology notes

> **19 October 2026:** the client's name in this file was replaced by a description, "the first client" (an
> accounting firm), and its examples translated into English, with module names, identifiers and the national
> registry they name renamed to match ([#375](https://github.com/EmpoweredHouse/eh-os-contract/issues/375)). What
> happened and what each example illustrates did not change.

**How it is built and what it looks like.** Code shapes, schemas, tables, library choices,
implementation traps. Reference material, not a document to read end to end — see
[§16](#16-where-to-look-for-what) for which section shows which decision's shape.

The numbered sections here are what `notes §N` in a code comment points at. They are a different numbering
from the decisions in [architecture](architecture.md), which are `§N` without the word *notes*, and the two
are not in correspondence — `§16` here is a lookup table, `§16` there is what ships.

Where a note says a mechanism works one way and the code works another, the code is right and the note is a
bug: corrections are dated in place rather than rewritten, so that what was assumed stays comparable with
what happened.

Vocabulary is fixed in [design rationale](design-rationale.md#vocabulary). In particular **process**
always means a business process; where an OTP process is meant, the text says *BEAM process*.

## 1. The contract, and the code it governs

The contract is a module built from a DSL:

```elixir
defmodule Bookkeeping.Contract.Invoicing do
  use PNS.Contract

  event :invoice_issued,
    label: "Invoice issued",
    owner: Bookkeeping.Invoicing,
    payload: %{invoice_id: :id, amount: :integer, client_id: :id}

  event :filing_rejected_by_authority,
    label: "The authority rejected the filing",
    owner: Bookkeeping.Filing,
    depends_on: :e_invoicing,
    payload: %{filing_id: :id, closing_id: :id, reason: :string},
    retain: %{reason: :hash},
    identity: [:filing_id, :reason],
    process: :month_end_closing,
    stage: :filing

  event :invoice_filed,
    label: "Filing sent",
    owner: Bookkeeping.Filing,
    payload: %{filing_id: :id, closing_id: :id},
    process: :month_end_closing,
    stage: :filing,
    terminal: true

  process :month_end_closing,
    label: "Month-end closing",
    stages: [:collection, :calculation, :filing],
    instance: [:closing_id],
    cadence: {1, :month},
    deadline: {25, :day},
    unverified: [:deadline]

  trace :closing_completes do
    from :documents_collected
    eventually :invoice_filed, within: {5, :day}
    or_else :closing_abandoned
  end

  # The tax authority's mandatory e-invoicing registry — a real government system,
  # not a stand-in.
  external :e_invoicing, label: "E-invoicing registry", expected_latency: {2, :hour}

  rule :filing_requires_complete_month,
    label: "We do not file for an incomplete month",
    function: {Bookkeeping.Filing, :prepare, 1},
    source: "Workshop 07-07, WF 01:50:54"

  example "complete documents — the filing goes through",
    rule: :filing_requires_complete_month,
    given: %{documents_collected: true, bank_statement: :present},
    command: {:prepare_filing, %{closing_id: "4712"}},
    then: [:audit_file_generated, :invoice_filed]

  example "no bank statement — command rejected",
    rule: :filing_requires_complete_month,
    given: %{documents_collected: true, bank_statement: nil},
    command: {:prepare_filing, %{closing_id: "4712"}},
    rejected_with: :bank_statement_missing
end
```

*Corrected 29 September 2026, v2 plan E11* ([contract v2](contract-v2.md) §4, §18). **The DSL above is
v1's, and E11a deleted it.** v2 writes a process as two Spark DSLs: `use EhOsContract.Domain` — contexts,
actors, subjects, values, entities, externals, relations — and `use EhOsContract.Contract` — units that
decide (`aggregate`, `dcb`) with their commands, events and invariants, consumers (`policy`, `effect`,
`process_manager`, `read_model`, `query`), one `process` with its `promise`s, and `scenario`s. There is no
`owner:`: an implementation names the declaration it implements (`use C, aggregate: :x`), never the other
way round. `retain:` became `personal:` with crypto-shredding (E8). Every key is in the reference generated
from the extensions, `packages/eh_os_contract/docs/dsl/`.

*Corrected 13 October 2026, plan DD, P2h* ([contract v2](contract-v2.md) §4.2, [#221](https://github.com/EmpoweredHouse/eh-os-contract/issues/221)).
**A contract has no `process` any more.** The run, its stages, `ends_on`, promises and deadline are a third
module, `use EhOsContract.Process`, which includes events from the contracts that declare them; a contract's
units have no stage groups and its events no `terminal:`.

The labels are not placeholders. In the first client's contract `label`, `source` and the two `example` titles
were read by a real accountant in Polish, the language the workshop was run in, and the engine passes them through
untouched (see `docs/contract.md`'s note on `event`'s `label`). They are shown above in English, as the note at
the top of this file says; the contract itself carries its client's words, never a translation.

`use PNS.Contract` accumulates the declarations in module attributes and generates the query
functions at `@before_compile`: `event?/1`, `event/1`, `events/0`, `process/1`, `traces/0`,
`external/1`, `rules/0`, `examples_for/1`. They are called twice at different times — at compile time by the handler macro, and
at runtime by the dashboard and the conformance queries.

Every mechanism discussed elsewhere has its slot here. `label` is the business name for the
workshop and the client-facing view. `owner` gives event ownership. `depends_on` enables the third
conformance answer (§5). `deadline` drives the stalled-process monitor.

`cadence` is how often an instance is due, which is what the "never observed" window is computed
from (§9). Without it the overlay has to guess, and a monthly closing reads as a dead path six days
after the last one completed.

**`cadence` is optional, and the universality gate showed that this is load-bearing rather than
permissive.** An *event-driven* process has no cadence and cannot be given one: a treatment episode is
not due on any schedule, it starts when a referral arrives. So the fallback §9 describes for
cadence-less processes is not an edge case — it is the normal state for a whole class of them. The word
is domain-neutral; the mechanism behind it is specific to calendar-driven process shapes.

**An event declares which process and which stage it belongs to; the process declares only the order of its
stages.** The first shape had it the other way round — the process listed its events inside `stages:` — which
meant every event name appeared twice in the contract, adding an event took two edits a hundred lines apart,
and reading an `event` told you nothing about where it sat. The split now follows one question, **how many of
these are there**: a stage and terminality are one per event, so they live on the event; cadence, deadline and
run identity are one per process. Stage *order* stays on the process because it is the only thing an event
cannot state about itself. `terminal: true` replaced the `terminal:` list for the same reason.

A consequence worth recording: **"an event belongs to at most one process" stopped being a check and became
inexpressible**, because `process:` is a single key. See the §15 review trigger in the ADR.

**`stages` declares order between gates, and nothing inside a gate.** A flat ordered event list was the
first shape and it was wrong: the workshop says both *one long process* and *the phases are not fully
sequential — the gates are*. Order inside a stage would be our invention presented as the client's model, and
the backward-edge check (§4) stands on it, so a check would be enforcing our invention. Omitting `stages:`
means exactly one stage and no claim about order; events of such a process then carry no `stage:`.

`identity` names the payload fields that make two occurrences the same business fact. It is where the
idempotency key comes from (§4), it belongs to the event rather than to a handler, and it must include
whatever *distinguishes* facts — not only what groups them.

**`instance` names the payload fields that say which *run* an event belongs to, and it is required on
every process.** It is a different question from `identity`, and the two are needed together: identity
is what makes two occurrences the same fact, instance is what makes two events part of the same run.
Identity belongs to the event, instance to the process — a run is a property of the process, and
repeated on each event the declaration would drift between them.

The reason is technical, not reporting. `trace` asserts *after X, eventually Y*; without run identity a
Y found for another company in another month counts as satisfaction. The same hole sits in the
counters: an edge traversed 49 times by one client and one traversed once by 49 clients have an
identical occurrence count, and the difference between them is exactly the silence the product exists
to surface. The prototype counted per event type and hid it.

Three compile-time gates follow, all from one property — `instance_id` is computed at emit time from
the payload **after `retain`**, so it is reproducible from the log alone, and the log has one column for
it. Every event of a process must carry the instance fields and must not `:drop` them. **An event may
belong to at most one process**, which is the *process row is the wrong idea* stop condition from the
ADR review triggers made mechanical instead of waiting for a review. And a `trace` may not span two
processes, because each carries its own run identity.

**`population` is deliberately absent, and this is where the reason is recorded so it does not come
back.** It pulled client entities into the library, which kills universality, and it answered a question
that belongs to the client application — *which company has no open July*. `instance` answers the
question `population` was reached for, telling one run from another, without naming a single business
object: the engine counts distinct runs and never enumerates them.

The full word list is exposed as `PNS.Contract.vocabulary/0` and pinned by a test in the universality
gate. A criterion nobody checks is a sentence in prose; adding a domain-specific word now fails a build
the same day rather than surfacing at a quarterly review.

**Payload types must separate identifiers from free text**, because one mechanism depends on it. With
`:string` for everything the retention check reported every `company_id` and produced 33 findings on 11
events, which is a check that gets switched off within a week. `:id`, `:timestamp`, `:integer` and `:enum` are
distinct types and **`:string` means text a human typed** — the only kind the retention check reacts to.
Seven findings on the same contract, one of them real: an email address heading into the log verbatim.

*Corrected 6 August: the set is closed and `:period` is not in it.* This paragraph used to list `:period` as
one of the identifier-ish types, and that was the whole problem — it read as a shape while naming a thing an
accountant recognises. The universality gate could not catch it, because that gate asks whether describing a
second domain forced a **new** word and never whether an existing one is surplus; counting caught it instead,
since the medical contract has fourteen payload fields and used `:period` zero times. A period is now `:id`,
and what the identifier refers to is the client application's business. The legal set is
`PNS.Contract.payload_types/0` and a compile gate closes it, because before that gate any atom was a legal
type — so removing the word without closing the set would have been undone by whoever next found it handy.

`unverified` lists declarations the **process owner has not confirmed**. They stay in the contract, because
without them the mechanism has nothing to watch, but they cannot count toward the evidence report: a false
metric is worse than a missing one when it is the metric the product sells. `mix pns.check` reports them on
every run.

`rule` names one pure function and nothing else; `example` pins it with a case that is both readable
aloud and executable (ADR §18). The reference is an **MFA tuple, not `&Mod.fun/1`** — a capture
would make the contract depend on the domain at compile time, and since handlers depend on the
contract, every domain change would recompile them. `mix pns.check` verifies the function exists.

`retain` marks payload fields the log must not keep verbatim: `:persist` is the default, `:hash` and
`:drop` are declared per field. The default is deliberate — the log is the evidence artifact and an
empty one proves nothing — but it means the personal-data surface grows by omission, so the check
should report fields carrying free text with no `retain` entry rather than failing the build.
**The policy governs every store the payload passes through, not only the log** — a hashed field that
travels intact inside job arguments is a retention policy that looks satisfied and is not. The consequence
belongs in the contract rather than in code: if a handler needs the raw value, that field cannot be `:hash`.
Changing `retain` bumps `version/0` like any other declaration, which is correct: the shape of the
evidence changed, and the log should record which policy each event was written under.

It also generates `version/0`: a hash of all declarations computed at compile time. That is the
`contract_version` stamped on every event (§3), so it cannot be forgotten or hand-maintained.

*Amended 16 October 2026 (plan DD, V5):* not of all declarations, of what they allow. A label, a `source:`, a
scenario's description and a domain's glossary are the agreement's words, and correcting one moved the version,
stamped every later event differently and marked every read model stale, with nothing agreed changed. The words
now have a digest of their own, `text_digest`, recorded beside the version on each deployment, so the report
can say that only the words changed. [#322](https://github.com/EmpoweredHouse/eh-os-contract/issues/322)

**The serialisation has to be canonical across runtime versions.** This value separates legitimate history
from drift (§9), so a hash derived from `:erlang.term_to_binary` can shift on an OTP upgrade and reclassify
every past event as historical — with no contract change at all.

*Done on 6 August, and the OTP upgrade was the less dangerous of the two defects.* The old hash was taken over
a list in declaration order, so **moving one `event` block above another moved the version** — an ordinary edit
with the same consequence as a runtime upgrade, and far likelier to happen. The contract is a set of
declarations rather than a sequence, so member order within a kind is now insignificant, and sorting happens on
the canonical form of a whole declaration rather than on a name key — which means there is no declaration shape
the hashing has to be taught about, including the one kind that has no name.

The distinction the canonical form exists to hold: **collections of declarations are sorted, values inside a
declaration are not.** `instance: [:company_id, :period]` is not the same agreement as its reverse, because the
run key is those values joined in order; sorting them would make two different keys hash alike. `stages:` is
the same case, since stage order is what makes a backward edge backward. Both deployment identities are
computed from this one form now, so there is no longer one hash that is canonical and another that is merely
hardened.

The fix necessarily performs the reclassification it prevents, once: every existing version moved. The report
reads that honestly as events from an earlier agreement, but the scheduling consequence is worth stating —
**this had to land before any client log holds history worth preserving**, which is why it went ahead of the
payload work it was originally grouped behind.

**One contract per bounded context, not one global module.** Handlers take a compile-time
dependency on their contract, so a single global one means every event added recompiles every
handler. The context wraps it, following the `use MyAppWeb, :controller` pattern:

```elixir
defmodule Bookkeeping.Invoicing.Handler do
  defmacro __using__(opts) do
    quote do
      use PNS.Handler, unquote([{:contract, Bookkeeping.Contract.Invoicing} | opts])
    end
  end
end
```

### Splitting, without aggregation

A parent contract that includes its children looks tidy and reintroduces the problem: the parent
depends on every child at compile time, handlers depend on the parent, and one event recompiles
everything. There is no aggregating module.

Instead each contract module self-registers, the same way handlers do — `use PNS.Contract` injects
`__pns_contract__/0`, and the registry collects them at boot. Adding a contract recompiles nothing
else, and a handler depends on exactly one.

The unit of splitting is the **process**, which is already first-class, is the dashboard's
navigation unit, and is what a workshop produces:

```
sandbox/lib/<client>/contracts/
  month_end_closing.ex
  invoice_correction.ex
  client_onboarding.ex
  invoicing.ex          # context-level events belonging to no process
```

At roughly six lines per declaration, fifty events is a three-hundred-line file. Several thousand
events firm-wide spread across a few dozen files, each named after something a person can point at
in a workshop.

Cross-contract references — a trace spanning two contexts — resolve **by name at boot**, not by
module reference, or the compile-time dependency comes back. `mix pns.check` verifies they resolve.

### Lifecycle

Written once from the workshop: the board and transcripts are compiled into contract modules, by
hand at first with model assistance, then reviewed. That review is the mandatory gate.

After that there are exactly two ways it changes.

*Intentional.* The business wants something different. A person edits the contract, impact analysis
runs, then code. Governed by the change-a-contract skill.

*Drift.* Something undeclared was observed, and the system **proposes** the addition as a pull
request. A person accepts or rejects.

There is no third path. In particular it is never regenerated from the code.

### Ownership

Developers edit the contract, because it is code and has to compile. The **process owner approves
the content**, because it is business meaning — the same split as the workshop.

Mechanism: `CODEOWNERS` on `lib/*/contracts/`. A contract change needs the process owner's
approval, not only a developer's.

The reason is not procedural. The contract is the artifact the client authorised (ADR §1). If a
developer can change it quietly, the charter's Authority property stops holding.

### Not yet

A workshop-to-contract compiler. Write three contracts by hand, see what repeats, then automate.
Built before three examples exist, it encodes assumptions rather than patterns — the same trap as
building the project generator early.

### The code it governs

Business logic is a pure function:

```elixir
def add_apartment(command) do
  with :ok <- validate(command) do
    [PNS.event(:apartment_added, %{id: command.id, city: command.city})]
  end
end
```

A command goes in, an error or a list of events comes out. A generated shell invokes it and
publishes what came back. Side effects live only in handlers.

Testable with no setup, and it is the shape a model generates most reliably: bounded input,
explicit rules, explicit output, no environment.

## 2. Compile-time enforcement

```elixir
defmodule Bookkeeping.Invoicing.OnOrderApproved do
  use PNS.Handler, event: :order_approved, publishes: [:invoice_issued]

  @impl PNS.Handler
  def handle(%{order_id: id}, ctx), do: # ...
end
```

`use PNS.Handler` at compile time:

- sets `@behaviour PNS.Handler`; missing `handle/2` fails the build under `--warnings-as-errors`
- checks `:order_approved` exists in the contract
- checks `publishes:` against the contract
- registers the edge in the registry, which is where the static graph comes from

*Corrected 29 September 2026, v2 plan E11* ([contract v2](contract-v2.md) §6). **`use PNS.Handler` is v1's,
and gone.** v2 enforces in five layers: Spark's schema (L1), the rules of one module (L2), a Mix compiler for
the rules between modules (L3, `compile.eh_os_contract`), the implementation macros at the call that breaks
them (L4), and `mix eh_os_contract.check` (L5). Every refusal of L2–L4 is listed by its code in
`packages/eh_os_contract/docs/contract.md`, and a test holds that list to the code.

A compilation tracer (as `boundary` uses) sees every remote call, so a direct call into another
process's module is a compile error. Every implementation must also pass a shared
`ExUnit.CaseTemplate` covering idempotency, unknown payloads and context propagation.

**Dynamic event publication is illegal.** Event names must be literals. This is what makes the
static graph a fact rather than a heuristic — narrow the API instead of improving the analysis.

Mechanics worth being precise about, since three of them are easy to get wrong.

**Read config with `Application.compile_env!`, not `get_env`.** The compiler records the read and
forces recompilation when the value changes. `get_env` in a macro captures the build-time value and
drifts silently.

**Call the contract from the macro body, not inside `quote`.** That runs the check at the
handler's compile time and creates the compile-time dependency that makes the compiler order the
contract first. Use `__CALLER__` for file and line so the error points at the handler rather than
into the library.

**The registry is a marker function plus a boot-time scan, not a generated module.** Generating one
module holding the whole graph would require every handler compiled first, which a per-module macro
cannot arrange. Instead the macro injects `__pns_handler__/0` into each handler, and the registry
scans once at boot:

```elixir
{:ok, mods} = :application.get_key(:bookkeeping, :modules)

mods
|> Enum.filter(&(Code.ensure_loaded?(&1) and function_exported?(&1, :__pns_handler__, 0)))
|> Enum.map(& &1.__pns_handler__())
```

Cached in `:persistent_term`. The property that matters is preserved: the graph comes from the
binary that is actually running. `Code.ensure_loaded?` is needed because in dev modules load
lazily; a release in `:embedded` mode has them all.

**Recompilation cost.** Every handler depends on its contract at compile time, so changing the
contract recompiles its handlers. That is partly wanted — they should be rechecked — but not across
three hundred modules, which is why the contract is split per context (§1). Watch it with
`mix xref graph --label compile-connected`.

**`publishes:` needs the tracer, not the macro.** Checking the declaration against the contract is
easy. Checking that the handler *only* publishes what it declared means reading its body, which a
macro does not do. A compilation tracer in `elixirc_options` sees every remote call, so it can
collect calls to `PNS.publish/2` and compare. This is what makes the ban on dynamic publication
load-bearing: with literals the tracer always recovers the name, with a computed name it never can.

**Per-module versus whole-program.** The macro checks what one file can show: the event exists, the
declared publishes exist, the callback is implemented. Everything needing all modules at once —
every declared event has a handler or is marked terminal, no orphan handlers, declarations match
what the tracer saw, backward edges under threshold — belongs in `mix pns.check`, which loads the
app and builds the registry. The split is forced by the compilation model, not chosen.

`mix xref` is not part of any of this. It is exact for function calls and blind to event edges,
which is the asymmetry the registry exists to fix.

## 3. Event log

```
events:           id, type, version, contract_version,
                  correlation_id, causation_id,
                  payload, actor, occurred_at

event_handlings:  id, event_id, handler, attempt,
                  status, duration_us, error
```

`contract_version` is what keeps the overlay honest. The static graph describes the code that is
deployed right now; the log spans every version since the first deploy. An event removed last
month is legitimate history, not drift. Without this column every deploy that drops an event
produces false positives, and the dashboard is distrusted within two releases. Cheap now,
impossible to backfill later.

Outcomes belong to the handler, not the event. An event does not fail; a handler processing it
fails. Status on the event gives a dashboard that cannot answer which handler is broken.

Model `attempt`. "Succeeded after three tries" is a different state from "succeeded", and a
flapping handler is a useful signal.

`correlation_id` and `causation_id` are set by the framework, never the publisher. Trap: an Oban
job runs later in another BEAM process, so correlation must be serialised into job args or meta at
enqueue. Miss it and the chain breaks at the boundary most interesting processes cross.

Payload retention is declared per field in the contract (`retain:`, §1). **Policy decided 3 August:
persist by default** — a field nobody marked is stored, `:hash` and `:drop` are explicit, and nothing
forces a decision on personal-looking fields, because missing evidence is a silent product failure while
excess data is visible and fixable. Volume is handled by an Oban job purging by age, which bounds the
conformance window. The payload itself is declared in the contract and stored as JSON, read defensively:
interpret the fields you understand, show the raw value where you cannot.

*Corrected 26 September 2026, v2 plan E6* ([contract v2](contract-v2.md) §10.3, §11). The table above is
v1's; the store's shape is v2 §10.3, with positions, streams, tags and `eh_os_contract_commands`. For a v2
contract `event_handlings` gives way to that table: a command's outcome is one row, accepted, rejected with
its invariant, or failed with where it failed and the exception's module, never its message, since a message
may quote a value. `correlation_id` and `causation_id` are still set by the framework: dispatch makes the
command the cause of its events, and the event a policy reacted to the cause of the policy's command. The
payload is written by `EhOsContract.Codec` in the log's JSON form and read back into the contract's structs.
Retention: E8.

*Corrected 13 October 2026, plan DD, P2h* ([contract v2](contract-v2.md) §10.3, [#221](https://github.com/EmpoweredHouse/eh-os-contract/issues/221)).
Neither table has `process` or `instance_id` since storage version 3 (V03): an event's runs are rows of
`eh_os_contract_event_runs`, one per process module that includes it, and a command row names no run. The
engine refuses to start on storage newer than its own version, since a node of an older release would write the
removed columns.

## 4. Delivery

The split is the transaction boundary, not a preference.

| | In transaction | After transaction |
| --- | --- | --- |
| Handler does | Touches only the same database — projections, derived state, local read models | Anything outside it — mail, HTTP, external APIs, payments |
| Runs | Inside the state change's transaction | Oban job, enqueued in that transaction |
| On failure | Whole transaction rolls back, caller gets the error | Retries with backoff |
| Idempotent | Not required — nothing happened | Required |
| Declared | default | `:async` |

**Enforced, not chosen.** A handler performing I/O outside the repo must be `:async`. That is a
lint over the handler's own calls, so the developer does not decide sync or async — they write the
handler, and the check says whether the declaration matches what it does.

**Failure semantics.** An in-transaction handler that raises rolls the transaction back. This is
correct only because such handlers are restricted to same-database derived state: if a projection
cannot be written, it must not diverge from its source, and there is nothing to retry because
nothing happened. The same behaviour applied to a mail-sending handler would let a side concern
veto a business operation, which is why those cannot be synchronous. The alternative — swallowing
the error — reintroduces silent failure, the exact thing this product exists to detect.

Oban's deciding property is transactional enqueue: the job is inserted in the state change's
transaction, giving an outbox for free. Impossible against an external broker.

**Why not everything async.** One model is conceptually cleaner, but read-after-write stops being
reliable — the user issues an invoice, returns to the list, and does not see it. In back-office
software that is a support cost. In-transaction projections give strong local consistency and
never need reconciling.

**Residual cost, honestly.** Two models remain. Async handlers must be idempotent, test
differently, and carry correlation across the job boundary; in-transaction handlers do none of
that, and moving one to async later is a rewrite rather than a flag. The boundary would exist
either way, though — unnamed, as "this code happens to do HTTP inside a transaction", which in
Ecto also holds a pool connection open for the duration.

Oban Pro Workflows (DAG of jobs) noted, not adopted: commercial, and assertions over observed
behaviour fit better than orchestrating a plan.

| Mechanism | Guarantee | Failure mode |
| --- | --- | --- |
| `Phoenix.PubSub` | At-most-once, no queueing | Subscriber briefly down misses it; a raising handler still consumed it; no retry |
| `GenStage` | Buffered, acked on dispatch | Consumer crashing mid-processing leaves the event considered delivered |
| Oban | At-least-once, persistent | Handlers run more than once; idempotency mandatory |

PubSub is fine for disposable signals — live UI, presence, cache invalidation. Never for an event
in an evidence artifact: with at-most-once delivery, a missing event is indistinguishable from a
process that never ran.

*26 September 2026, v2 plan E7, as built.* The table above is v1's handler. In v2 the row is a consumer's
`delivery`: `:in_transaction` runs in the dispatch transaction (read models, then policies, then effects),
and `:at_least_once` is either an ordered subscription over the log, one row in
`eh_os_contract_subscriptions` with its position (read models, policies, process managers), or an
`EhOsContract.EffectJob` in Oban's `:events` queue inserted in the dispatch transaction (effects). Oban's
transactional enqueue is still what makes an effect's job an outbox. A poison event stops a subscription at
its position until a person skips it; a query reads its own write with `min_position:`. Details in
`contract-v2.md` §12. A skip puts the row back in the status it failed in, which storage version 5 keeps in
`resume_status`, so a rebuild or a process manager's replay goes on past the skipped event; dispatch leaves a
failing inline read model to the runner, as a rebuilding one
([#550](https://github.com/EmpoweredHouse/eh-os-contract/issues/550)).

### Idempotency

Every async handler eventually processes the same event twice. **The event declares `identity:` in the
contract** — the payload fields that make two occurrences the same business fact — and the key is derived
from it. The generated suite asserts a second delivery has no additional effect; a handler without a passing
idempotency test does not merge.

This said "handlers declare an idempotency key" until the prototype implemented it, which contradicted
ADR §9–10. The ADR is right, for two reasons that only surfaced in code. *One notification or two for two
discrepancies in the same month* is a question for the process owner, and they read the contract, not handler
modules. And the identity of a fact is one thing while handlers of the same event may be several — held on
the handler it drifts between them.

**The key must include whatever distinguishes facts, not only what groups them.** `[:company_id, :period]`
swallowed a second, *different* discrepancy in the same month; the fix is to include the field that carries
the difference. Getting this wrong is silent: the second problem simply never notifies.

**Two synchronous handlers on one event have no defined order.** The registry scan yields them in module
order, which is incidental. Either declare an order or forbid the second handler; leaving it to chance is a
latent bug that appears the first time one handler depends on another's projection.

**A synchronous handler that raises leaves no evidence.** The transaction rolls back the handling row along
with the event, which is correct — nothing happened — and it means the most interesting failure is invisible
in the artifact that exists to make failures visible (§3). Diagnosis needs the failure written outside the
transaction, or telemetry.

*Built on 6 August, and it wanted both rather than either.* Telemetry is the seam the client's error tooling
attaches to, which is where error collection belongs — but telemetry only exists where somebody configured a
collector, and the gap is about the artifact. So there is also a durable row, in a table of its own with no
foreign key to the log, because the event it would reference was rolled back and never existed.

Three things about it that were not obvious before writing it:

**The write cannot happen where the failure is noticed.** That frame is inside the doomed transaction, so its
insert rolls back too. It happens in the emitter's outermost frame — the one that opened the transaction —
after the rollback, when the connection is free. No second connection and no task, which also means nothing
writing around the sandbox in tests. The limit that follows is stated rather than worked around: when the
caller opened the transaction, the engine never gets its turn and the trace is theirs to write, because a
durable write from inside somebody else's doomed transaction is not possible on one connection.

**The context has to travel, and it must not arrive.** The frame that knows which handler failed on which run
is about to disappear, so the exception is wrapped to carry that out — and then unwrapped, with the handler's
own exception and stacktrace reraised at the caller. Letting the wrapper out would turn a diagnostic mechanism
into a breaking change in every caller's error handling, which a test caught on the first run.

**It is not only for diagnosis, which is why it has a reader.** A path whose handler crashes every run reads
in the conformance layer as declared and never observed — a dead or untested path, both false, and both
sending a developer's defect to the process owner as a question about their process. So the report uses this
table to tell *never attempted* from *attempted and failing*, counting failing **runs** rather than failures.
Third instance of one rule, after zero runs and queued work: no answer is not the answer being no.

### Choreography and orchestration

Pure choreography holds for two or three steps. Beyond that the flow lives in no single place and
cyclic dependencies appear. Field consensus: orchestrate where compensation is required.

Accounting with corrections and reversals is the compensating case. Trace assertions detect that a
process stalled; they do not drive it. ADR §15 settles this provisionally — contract declares a
process, version one detects only, compensation hand-written per process. Commanded's process
manager is the reference to read first.

Two things follow:

**Stalled-process monitor.** A periodic scan of instances past deadline without a terminal state.
Without it a stalled process emits nothing and is invisible.

**Backward-edge check, from the first commit.** The registry knows which process and stage each
event belongs to, so it can flag a module subscribing to an event downstream of its own
participation. That is the signature of compensation leaking, and the automated review trigger for
ADR §15. A handful of lines over data the registry already holds.

## 5. Conformance

Static graph = possible (superset). Observed graph = actual (subset, weighted). The join is the
product.

| Process-mining term | Here |
| --- | --- |
| Fitness | Observed but not declared — drift |
| Precision | Declared but never observed — dead contract or untested path |

**Trace assertions evaluate per run, and there are four verdicts of which three are computable.** Satisfied
carries *how* — via the consequent or via the declared alternative, because a run that ended through the
alternative is **conforming**, not an exception, and a report calling it a problem gets switched off after one
month. Violated is the window elapsing with neither. Pending is the window still open, which also covers a
consequent whose handler is asynchronous and whose job is still queued — the fourth overlay state of §9,
reappearing in a second mechanism, and the cost is worth stating: a job wedged past the window counts as a
violation, correctly, because the notification did not go out.

Three semantic choices, each reversible without breaking anything else, hence each pinned by a test. The
window runs from the **first** occurrence of the antecedent rather than the last, or a process outruns its own
deadline forever by re-emitting it — not hypothetical where a check gets repeated. The window applies to the
**alternative** as well, or a run that ends correctly three months late is "satisfied"; this one belongs to
the process owner to confirm, not to us. And a run that never reached the antecedent is **not evaluated at
all** — neither satisfied nor violated, since counting it as a violation raises an alarm for every case not
yet started.

The fourth verdict, **suspended**, is not computable and the missing piece is engine-side rather than
conceptual: nothing records that an external dependency was unavailable, so `unavailable_looks_like` is a
sentence with no reader (§10). Until it has one, a registry outage inside an assertion window counts as a
violation — which blames the client for someone else's server. The prerequisite is small: a log of
unavailability **observations** per declared dependency, written by the adapter on the seam that already
exists. Observations rather than intervals, because an adapter knows only that one call failed, never when the
service came back. Suspended then means: an observation inside the window, against a dependency that some
event on that path declares.

*Built 6 August 2026, and this paragraph was still saying otherwise on 22 September.* The prerequisite it
describes exists — `PNS.Dependency` records unavailability observations, `depends_on` decides which
dependency's outage can suspend which assertion, and `:suspended` is the fourth verdict `PNS.Trace`
returns. The design above is what was built, almost exactly: observations rather than intervals, for the
reason given.

Recorded here late, and the lateness is the finding. A claim in this file that a thing has no reader is
the kind that goes stale silently, because nothing compares these files against the code — which is the
one service this whole document is supposed to render. Found while correcting the same class of staleness
about `deadline`. See [PLAN.md](../../PLAN.md), "Rozstrzygnięte 6 sierpnia".

**Events from one command are siblings, not a chain.** A decision function returns several intentions at
once; none caused another, the same command caused all of them, so they share `correlation_id` and carry no
`causation_id`. The overlay is built from causation, which is right — and leaves those events with no edges
at all, so a diagram shows them floating unconnected and reads as broken to the very audience it is for.
They need their own relation, visibly distinct from causation: `correlation_id` where `causation_id` is null.
Drawn as an arrow it would be read as causation and someone would build logic on it.

Two more outputs from the same join: changing a publisher yields every downstream subscriber
**ranked by production volume**, and a change breaking a trace assertion is blocked in CI.

**Example coverage is a third output, and it has no equivalent elsewhere.** Rule examples live in
the contract in the same event vocabulary the log records, so the sets join: distinct event
sequences observed per process, against the examples that describe them. What comes out is *which
real paths nobody wrote an example for, ranked by how often they happen*. Line coverage cannot say
this — it measures code rather than business paths and is blind to frequency. The reverse direction
is the familiar three states: an example whose path is never observed is a dead rule or an untested
one. Note the layering: this compares declared examples with observed paths, never test results with
the log. A green suite is a fact about CI, not evidence from production.

Two weaknesses in examples, named rather than mitigated away. They **under-specify**: three of them pass
under an implementation that special-cases three inputs, which is the standing cost of specification by
example and the reason the reviewed pure function stays part of the gate. And they are a **maintenance
surface** that rots the way all tests rot — tolerable only because an example *is* a test and fails
loudly, unlike prose. That is also the argument for keeping them in the contract rather than in a
document beside it: a second editable representation is the drift this product exists to detect.

Against Celonis: it mines a model from logs of software it does not control, so it infers what
should have happened. Here the model is declared and the emission controlled.

Against APM: it answers "is the system healthy". A process that never starts raises no error, so
there is nothing to alert on and every conventional signal reads green while the work does not get
done. Monitoring measures the machine, conformance measures the promise. Complementary.

## 6. Testing

The contract is the transfer function: given this input, this output, within this time. Unit tests
measure it at points in the lab; the event log measures it continuously in production.

What each layer cannot do:

- **Black-box observation cannot localise a fault.** Unit tests and module boundaries do that.
- **Unit tests do not detect drift.** Every test can pass while the share of orders invoiced
  within 24h declines for three weeks. Trend monitoring over the log catches it.
- **Neither catches a wrong rule correctly implemented.** Only contract assertions reviewed with
  the client address intent — and only if there is something in the contract a client could review,
  which is what rule examples are for (ADR §18).

### Which tests come from where

Worth being explicit, because "tests generated from the contract" covers three different things
with three different lifespans:

| Test | Generated from | When | Fully generatable |
| --- | --- | --- | --- |
| Payload conformance | `payload:` types | with the skeleton | yes |
| Structure: handler exists, no orphans, declared events owned | registry plus contract | `mix pns.check` | yes, but it is a check rather than a test |
| Idempotency | handler declaration | with the skeleton | the shape, yes; "no additional effect" reaches only the module's own tables and mock call counts, and that limit belongs in the docs |
| Dispatch mode matches what the handler does | declaration plus lint | with the skeleton | yes |
| **Business rule** | **`example` declarations** | **before the decision function exists** | **yes — the example is the test** |
| Trace assertion | `trace` | last, needs several handlers | partly; examples supply the means of driving the process |
| Conformance | contract plus log | continuously in production | not a test, it is the third layer |

Ordering matters and it fixes the layered generation in §7: **layer 1 is the contract including its
examples**, layer 2 is the skeleton plus tests generated from them, layer 3 is implementation until
the examples pass. Without examples, layer 3 has no acceptance criterion and layer 2 can only assert
shapes.

Payload types are also a free generator specification: where types allow, property tests
(`StreamData`) come out of the same declarations that drive the conformance check.

Worth stealing from control theory: **observability** — can internal state be reconstructed from
the outputs alone? As a design criterion for the event set: if a reader cannot tell what a process
is doing from its event stream, the contract is under-specified. Turns "is this event catalog good
enough" into a checkable property.

Where the analogy breaks: an engine's specification does not change. Here the setpoint is
versioned, which is why contract versioning is load-bearing.

TDD with generated code: the test is the durable artifact of intent and the code is disposable.
Tests are generated from the contract because they must outlive any particular implementation.

## 7. Generation workflows

### A — empty application, large graph

Four layers, each committed before the next. Avoid the fifteen-thousand-line PR.

1. **Contract only, including rules and their examples, human-reviewed.** A few hundred lines for a
   fifty-requirement process. The one mandatory gate; everything downstream inherits its errors.
   Examples belong to this layer, not to layer 3 — they are the acceptance criterion layer 3 is
   written against.
2. **Skeleton, deterministic.** Module structure, boundaries, handler stubs, migrations, test files
   with assertions written and implementations pending. Template, not model.
3. **Implementation, one unit at a time**, leaves of the graph first. Tests exist beforehand by
   construction.
4. **Trace assertions last**, since they need several handlers.

Thin end-to-end slice first. Otherwise: forty half-built handlers and nothing that runs.

### B — change to an existing application

1. **Diff the contract, not the code.** Also the client-facing change description.
2. **Impact analysis first**: subscribers affected (static), production frequency and payload
   shapes (observed), trace assertions covering it, tests touching it. Technical owner approves
   before code is touched.
3. **Classify the delta:**

| Class | Handling |
| --- | --- |
| Additive — new event or subscriber | Safe, existing code untouched |
| Payload widening — new optional field | Safe, version bump |
| Narrowing or semantic change | Breaking; coexisting versions and a migration window |
| Removal | Requires proof nothing uses it — not fired in 90 days, no registered subscriber |

4. **Regenerate narrowly.** Only handlers touched. Tests automatic, code human-gated.

Metric worth reporting: a change requiring edits to existing handlers is a warning sign; a change
that adds a module is healthy. "Modifies 4, adds 1" versus "adds 2, modifies 0" is a computable
signal about the domain model.

## 8. Skills

Task-scoped instructions for the coding agent, shipped and versioned with the package. Each
covers one recurring task and points at the check and the exemplar module rather than restating
rules that are already enforced.

| Skill | Covers | The part a check cannot express |
| --- | --- | --- |
| Add an event | Contract entry, naming, ownership, payload schema | Past tense means a fact; if it has one handler and the publisher wants a result, it is a command |
| **Declare a rule and its examples** | `rule` with its MFA reference, `given` / `command` / `then` / `never`, one positive and one negative case | Why the rule itself must not move into the contract; what makes an example readable aloud to the process owner rather than only to a developer; that a case which went wrong in real life is worth more than an invented edge case |
| Write a handler | `use PNS.Handler`, sync or async, idempotency | Which side of the transaction boundary this belongs on, and why the sync restriction exists |
| Write a decision function | `command -> {:error, reason} \| [events]` | Keeping it pure when the obvious implementation reaches for the repo |
| Declare a process | Events, terminal states, cadence, deadline, trace assertion | What makes an assertion useful rather than tautological, and why cadence is not the same question as deadline |
| Add an adapter | Port or subscription, adapter state, three test levels | Naming after the business fact, not the vendor; not collapsing legally distinct states |
| **Change a contract** | Diff, impact analysis, delta classification, narrow regeneration | Running the impact analysis *before* touching code — no lint can enforce an ordering after the fact |
| Add a projection | Read model in the owning module's tables | When duplication is a cache and when it is a second source of truth |

The change-a-contract skill is the one that matters most, because it is the only one requiring the
agent to do something before writing code, and nothing checked after the fact can enforce that.

Skills rot the way all prose does. The mitigation is to keep them short and make them point at
code and checks, which the compiler and CI keep honest.

*Corrected 30 September 2026, plan E11e.* What exists, in `.claude/skills/`, is not the table above.
The decision function is `write-decider`: an aggregate's or a boundary's callback per command, with
`emit/1`, `reject/1` and `evolve/2`. "Write a handler" and "Add a projection" are one skill,
`write-reaction` — policy, effect, process manager, read model and query — because the question
they share is where a failure leaves the log, not what the code looks like. "Declare a rule and its
examples" has no skill of its own: a rule is an invariant or a constraint with its `rejected`
scenario, and a domain service's rule carries its examples, so `add-event`, `write-decider` and
`contract-distillation` cover it. "Declare a process" and "Add an adapter" are not written. Two were
added that the table does not name: `module-boundary-check`, which decides whether a feature goes
through a contract at all, and `review-pr`, for the reviewer rather than the writer. The skills
point at the refusal codes in `packages/eh_os_contract/docs/contract.md` and the rule names in
`packages/eh_os_contract/docs/rules.md`, which do not change between versions, rather than at lines of source.

## 9. Dashboard

### The overlay

Not a union of two graphs. Each edge has a state and two independent dimensions.

| Edge state | Meaning |
| --- | --- |
| Declared and observed | Confirmed |
| Declared, never observed | Dead path, or untested |
| **Declared, work queued** | **In flight — not yet, rather than never** |
| Observed, not declared | Drift |

**The fourth state is not optional and the prototype found out the hard way.** A queued Oban job looks
exactly like a path that never runs, so the overlay reported a discrepancy notification as a dead path while
its job sat in the queue. Read the queue for the states that mean *not yet* — `available`, `scheduled`,
`executing`, `retryable` — and the same rule has to reach the *declared, never observed* list, or the list
and the edge state say different things about one event.

Volume and health are separate from state. An edge fired 50,000 times and one fired twice look
identical in a three-state rendering, hence thickness. An edge that fires and always fails is
"observed" and broken, hence colour.

**Volume is itself two numbers, and one of them is the interesting one.** An edge traversed 49 times by one
client and once by 49 clients had an identical count before run identity existed — and those are opposite
situations, the first being 48 silent clients. So an edge carries occurrences *and* distinct runs, against a
denominator of how many runs there were at all. Thickness should follow runs rather than occurrences, since
that is the number that separates silence from low traffic. Deliberately a **count and not a list**: which
particular run is silent is a question about one client, which belongs to the client's own application (§1).

Two things make the overlay wrong if ignored:

**Windowing.** "Never observed" needs a time range, and one range does not fit every process. A
month-end closing fires monthly; flagging it dead after a week is noise. The window therefore comes
from the `cadence:` declared per process (§1) — an instance is missing once a cycle passes without
one, not once an arbitrary window does. Where no cadence is declared the window falls back to
observed intervals, which is weaker in the case that matters: with no history, a process that never
ran is indistinguishable from one that has not been reached yet.

**That fallback is the normal state for event-driven processes, not an edge case, and this paragraph
used to imply otherwise.** The universality gate contract (§1) has no cadence and cannot be given one:
a treatment episode is not due on a schedule, it starts when a referral arrives. So "never observed"
needs a second source of window length for that whole class. The candidate already in the contract is
the `within:` on the trace assertion, which states how long the run is allowed to take.

**Resolved 6 August, in conversation — rejected, not built.** The open question above was "where does the
window come from"; the deeper problem, found only by asking why this was still unbuilt, is that "an
instance is missing" cannot be answered from the log at all, windowed or not. Most events will be raised
manually through the API by a frontend that already shows clients, periods and invoices directly — so it
already answers "which client has no July" by reading its own tables, without needing this. Building the
same answer here would need to know which instances *should* exist in order to notice which ones do not,
and that is company knowledge this engine deliberately does not have (§1: `claims: %{}`, no `company_id`
anywhere in a `PNS` structure). The "count, not a list" framing above does not save this — a count still
needs a denominator, and an entity that emitted nothing is invisible to a system built on nothing but the
log. This is a structural gap, not a missing feature: giving PNS that denominator would mean giving it the
company knowledge the rest of this record argues it should not have.

What is *not* rejected: the overlay's own "declared, never observed" edge state, at the top of this
section, which asks a different question answerable from the log alone — has this **edge** ever been
taken by any run — and is already built (`PNS.Conformance.untraversed_paths/1`, stage 1.4). What is
rejected is only the per-instance cadence window this paragraph describes. `deadline` is unaffected by
this and is being built on a narrower reading: a retrospective count, over runs that already have a
`from` event, of how many exceeded it — the same shape as `PNS.Trace`'s `violated` count, and computable
from the log alone because it never needs to know about instances that do not appear in it.

**Version skew.** Handled by `contract_version` on the event (§3). Without it, comparing today's
code against ninety days of log reports every removed event as drift.

**That covers a removed event and not a removed handler, and the difference produced real false drift.**
The example works because deleting an event changes the contract's declarations, so the version moves. Paths
do not come from declarations — they come from handlers' publication lists, and a handler is deliberately not
part of the contract, since making it one would turn every domain change into a full recompile. So deleting a
handler removes an edge from the graph while **every version stamped anywhere stays identical**. The overlay
then sees an edge that is observed and no longer declared, checks that the contract version is still current,
and reports drift for a path that was legitimately declared when it ran.

A deployment therefore has **two identities**: the contract version is the agreement, a wiring version is the
code. A refactor moves one and not the other, which is exactly the distinction the client cares about. One row
per distinct wiring, written at boot — nothing per event, so the cost is one insert per deploy rather than a
column on every event, and the log stays the artifact it was. The drift question is then asked of the edge
directly ("was this ever declared") instead of inferred from the target event's version.

The price is named rather than hidden: a log older than that table has nothing to identify itself with and
falls back to the `contract_version` heuristic above. Said out loud in the report, because one that guesses
without admitting it is worse than one that admits the gap. Two details worth keeping: both identities are
hashed through one canonical form (§1), so neither depends on term encoding, module load order or OTP release —
the wiring hash was canonical by construction from the start, and the contract version was brought to the same
footing rather than hardened separately. And `since` is the first event seen
under the deployed wiring, not a deploy timestamp: the engine is not told about deploys, it observes them, so a
deployment that has emitted nothing reads as deployed and unproven rather than carrying a date we do not have.

### Live, not a report

If this is a test rather than a picture, each process carries a current state — green, amber, red
— rather than only a rendering. That makes it a monitor, and monitors eventually want alerts.
Store the last computed state per process rather than recomputing on page load.

### Constraints

- **Default view is a sorted list of discrepancies, not a graph.** Empty state reads "3
  discrepancies", not a topology. A graph of a correct system is decoration.
- **Navigation is per-process, never global.** Graphs become unreadable past fifteen to twenty
  nodes. Data-model consequence: `process` must be first-class in the contract or there is no
  navigation unit. *Unimplemented as of 5 August, and it took a second contract to notice:* the graph module
  has no narrowing to a process or a contract, because it was written while only one contract existed and the
  assumption "there is only one" was invisible. A gap against this line, not a preference against it.
  *Amended 15 October 2026:* navigation is global, and readability is kept another way. One canvas moves
  between the context map, a contract, a unit and a process, and shows one of them at a time; structure and
  processes are two viewpoints of it, linked both ways (`docs/adr/graph-renderer.md`, the amendment of that
  day; [#297](https://github.com/EmpoweredHouse/eh-os-contract/issues/297)).
  > **28 September 2026, plan EG2 and after:** the graph screen now also draws two pictures per *domain* —
  > its context map and its system, contracts and what flows between them — above the per-process panels.
  > They stay readable because their nodes are contexts and contracts, not events: a domain has a handful of
  > each where a process has dozens of steps. Navigation inside a contract is still per process.
  > **6 October 2026, plan DD, P1b ([#186](https://github.com/EmpoweredHouse/eh-os-contract/issues/186)):**
  > the unit of navigation is the contract, not the process. A contract may have no process, and one picked by
  > process could not be reached at all. The graph page selects a contract by its id; its process's declared
  > shape shows when it has one. The readability argument holds: a contract's graph is one context's.
- **Business labels beside technical names.** `invoice_issued` means nothing to an accountant. Satisfied for
  every declaration except the trace assertion, which has an identifier and no label — deliberately, since a
  label there would restate what the assertion already says in full and could then drift from it. The report
  composes the sentence from the event labels instead, so it is derived and cannot disagree with the mechanics.
  See ADR §16–17 and the note under *Decided, and still open*.
- **A period without runs is not a green period.** The report says there was nothing to judge. The same rule
  covers untraversed paths, where the natural bug is to list every declared path for a process that never
  started and turn "no data" into findings, and trace evaluation, where a run that never reached the antecedent
  is neither satisfied nor violated. Three places, one rule: absence of basis is not a verdict.
  > **6 October 2026, plan DD, P1a ([#183](https://github.com/EmpoweredHouse/eh-os-contract/issues/183)):** for
  > untraversed paths the basis is no longer a run but an event the contract recorded in the period: a step is
  > the contract's, which may have no process. Promises and durations keep runs as their basis.

| View | Audience | Question | Form |
| --- | --- | --- | --- |
| Process funnel over a period | Client, process owner | Does my process work as agreed? | Sankey |
| Dependencies, width by volume, colour by errors | Developer | What does my change affect? | Directed graph |
| One process instance | Debugging | What happened to invoice 4712? | Trace / waterfall |

Sankey only for the funnel. A general event flow is not a conserved quantity — one event can
produce three or zero — so a Sankey of the whole system misleads.

## 10. External adapters

The tax authority's e-invoicing registry as the worked example. *Caveat: session mechanics and schema version
need checking against current documentation; none of this was verified against live docs.*

**Adapter state.** Submission reference, poll schedule, session token and expiry, rate-limit
budget, service windows. A state machine with its own table. Oban retries a job; it does not know
a session expired.

**Three states, three events.** *Submitted*, *accepted*, *receipt held*. The official receipt is evidence, not
an acknowledgement. One event with a status field loses the distinction that matters in an audit.

| Test level | Runs against | When |
| --- | --- | --- |
| Domain | Nothing; the domain does not know the adapter exists | Every run |
| Integration | Fake adapter implementing the behaviour | Every CI run |
| Adapter contract | Real external test environment | Scheduled, not per commit |

The third earns its keep: it is how you learn the authority changed its API before the client
does. The e-invoicing registry has a test environment, which makes it a good first integration. One
accounting package reportedly has none.

Recorded responses (`exvcr`) help determinism but age badly. They supplement the scheduled live
test, not replace it.

**No sandbox at all → shadow mode.** Compute what would be sent, write it to the event log, compare
against what a human did, send nothing. The log already does declared-versus-observed comparison,
so this is cheap, and it produces the evidence needed to decide whether to switch the integration
on.

**Dependency declared in the contract** (ADR §11): which events cross the boundary, expected
latency, what unavailable looks like. A missed deadline is then classified *violated*, *satisfied*
or *suspended*. The suspension window comes from observed adapter failures in the same log.

## 11. Configuration

| | Implementation | Configuration |
| --- | --- | --- |
| What varies | Real adapter or fake | Environment, credentials, timeouts, limits |
| Mechanism | Behaviour plus selection in config | Declared parameters per module |
| CI | Fake | — |
| Scheduled contract test | **Real** | **Sandbox** |
| Production | Real | Production |

The middle row is what a single "test mode" switch cannot express.

Selection, in order of preference: pass the dependency as an argument; otherwise a behaviour
selected in config, read with `compile_env` where the choice is fixed per environment; `Mox` where
per-test expectations and concurrency safety are needed.

Configuration is declared, not scavenged. Each module states its parameters and constraints
(`NimbleOptions`), and the app refuses to boot if something required is missing. Ad-hoc
`Application.get_env` in function bodies is forbidden and lintable.

## 12. Prior art

**[`oban-events`](https://github.com/allocator-one/oban-events)** — independently arrived at almost
the same emission design: `emit/2` and `emit/3`, handler behaviour, correlation and causation in
metadata, transactional emission, one job per handler, UUIDv7, idempotency key. Take the API shape
and metadata model.

**Settled: reference, not dependency.** It dispatches exclusively through Oban — `emit/2` returns
`{:ok, [Oban.Job.t()]}`, so it creates jobs rather than running handlers, and every handler runs
after the transaction commits. That covers one of the two dispatch modes §4 requires, and the
missing one is not an absent option that could be added around it: an in-transaction handler has to
be invoked at the emission site, before the transaction closes, which is a different entry point.
Two further divergences stand — no persisted event log (Oban jobs and metadata only), and a
hand-maintained `@events` map where we need the registry derived from the contract.

What it gets right is the property that decided Oban in the first place: the job is inserted in the
state change's transaction, which is an outbox for free. The objection is not to Oban. It is that
Oban alone is half a dispatch model.

*Verified against the README, not the source. Before this is final, read `lib/` — emission may be
separable enough that part of it can be lifted rather than rewritten.*

**[`carbonite`](https://github.com/bitcrowd/carbonite)** — audit trails via Postgres triggers.
Capture at the database level cannot be bypassed by application code, which is a real governance
advantage over application-level emission. Wrong granularity on its own — data changes, not
business events. Candidate complement for tamper-evidence.

**Commanded** — not adopted; its correlation/causation model and process-manager implementation are
the most mature references in the ecosystem.

**[AsyncAPI](https://www.asyncapi.com) (spec 3.1.0) and [CloudEvents](https://cloudevents.io)** —
edge formats, not a candidate for the contract. Recorded here because the tempting version of this
idea is wrong in a way worth stating once.

AsyncAPI is to event-driven systems what OpenAPI is to REST: a YAML document describing an
application's interface as **channels** (a Kafka topic, an AMQP queue) and `send`/`receive`
operations over them. It presupposes a broker and a second application on the other side. We have
neither in the core — one app, one Postgres, handlers in the same BEAM node — so filling in
`channels:` would mean inventing one channel per event type and stating something untrue about the
architecture in a standard format. Anyone who knows AsyncAPI notices, which is also what the
"we speak a standard rather than our own DSL" argument is worth here: less than it first appears.

It also has no vocabulary for what makes this a contract rather than an event catalog — no process,
deadline, cadence, trace assertion, approving owner or retention. What survives the mapping is event
names and payload schemas, the layer that is cheapest to render ourselves.

Both become relevant at the **edge**, where a real channel and a real counterparty exist: an event
leaving the system for a client's own consumer, a webhook, a queue the client already runs. AsyncAPI
to describe that interface and CloudEvents as the envelope for one event are then cheap and
conventional — the same position brokers hold, allowed outside and not inside.

[EventCatalog](https://www.eventcatalog.dev) is a documentation tool rather than a standard, from
the same author as the governance critique cited in the ADR. It can consume AsyncAPI, but a
renderer reading the contract directly is the shorter path and keeps ADR §2 intact.

*Corrected 29 September 2026, v2 plan E11* ([contract v2](contract-v2.md) §2, §16, §18). **ESDM joined this
list, and outranks it**: v2 takes [ESDM](https://www.esdm.io)'s modelling vocabulary and its linter's rules,
without integrating ESDM itself. The renderer reading the contract directly is built — the graphs (EG),
`mix eh_os_contract.pages`, the dashboard (E10). AsyncAPI describes what a contract `publish`es, since D11
gives it the real edge this section waited for. Commanded is still not a dependency, but its shape is no
longer rejected: v2 is event-sourced, on the engine's own store and dispatch.

*Corrected 8 October 2026, plan E13* ([contract v2](contract-v2.md) §3, requirement 6). **The renderer no
longer reads the contract.** The engine generates a contract's and a domain's graph as data — a `graph.v1`
document and an overlay from the log — and `eh_os_contract_graph`, a package of its own that does not depend on
the engine, draws it, for the dashboard and for EHOS Console alike. The Mermaid diagrams the engine drew are
gone, and the model pages carry a contract's document beside them in place of their diagrams. EventCatalog's own
renderer, `@eventcatalog/visualiser`, was tried for it and set aside: it is React Flow with EventCatalog's kinds,
none of which is a process manager, a timer, a stage or a promise ([graph renderer](graph-renderer.md)).
([#219](https://github.com/EmpoweredHouse/eh-os-contract/pull/219))

## 13. Library decisions

| Concern | Choice | Note |
| --- | --- | --- |
| Web, persistence | Phoenix, Ecto | Ordinary generated code, readable by any Elixir developer |
| Module boundaries | `boundary` | Compile-time enforcement |
| Durable jobs | Oban | Transactional enqueue decides it |
| Event emission | Own layer; `oban-events` as the API reference | It is Oban-only, so it covers one of two dispatch modes, and persists no log (§12) |
| Tamper-evident capture | `carbonite`, optional | Cannot be bypassed; wrong granularity alone |
| Event schema / docs format | Own DSL; docs rendered from it | AsyncAPI and CloudEvents presuppose a broker and describe no process — edge only (§12) |
| Instrumentation | `:telemetry` | OTel export is an integration, not the foundation |
| Distribution and install | Igniter | Patches existing projects, not only scaffolding |
| Users and sessions | **User profile mirror, no credentials, keyed by the identity subject** | Identity is bought and sits behind a protocol seam; a credential store here gives two answers to whether a person still works at the company |
| Permission engine | Own dependency, Oban-style migrations | Owned end to end, therefore updatable |
| Correlation model | Copied from Commanded | Proven, without the CQRS commitment |

The line that decides whether this is upgradable in three years: **what should be updatable is a
dependency; what the client will edit is generated.** Phoenix is a dependency; the router is yours.

*Corrected 29 September 2026, v2 plan E11* ([contract v2](contract-v2.md) §2, §10, §18). The DSL is on
**Spark**; event emission became the engine's own **store and dispatch**, not a layer modelled on
`oban-events`; `:telemetry` is no longer a direct dependency, since nothing emits it after v1's handler
spans went (E11a); Igniter is not used. Oban stays for what is delivered at least once — effects and timers.

## 14. Known risks

- **N+1 across boundaries.** Forbidding joins raises query counts and generated code will not
  notice five hundred queries. Boundary APIs plural by default; the log makes the cost measurable.
  *Measured on 5 August rather than left as a risk:* two modules resolving the same period cost exactly two
  queries against the owning table per month opening, counted with Ecto telemetry in a test that fails if the
  number moves. Cheap at this shape; the risk is about the shape that fans out per row, which nothing here has
  yet. Worth pairing with the stronger mechanism found alongside it — the owning module exports nothing, so the
  join is inexpressible rather than forbidden, and a generated module cannot write the five hundred queries
  this line worries about because it cannot name the table.
- **Plausible but wrong code at volume.** Syntactically perfect, passes naive tests, encodes the
  wrong rule. Only contract assertions reviewed with the client address it.
- **Duplicated rules.** Duplicated data is intended and cheap. Duplicated logic is a hazard, since
  a model will restate a rule in three places. A rule lives in exactly one pure function named by
  the contract through `rule` (ADR §18), and that is checkable — the mechanism is no longer only a
  mitigation, it is how the contract reaches behaviour at all.
- **Examples under-specify the rule they pin.** Three examples pass under an implementation that
  special-cases three inputs. Partial mitigation: the pure function is reviewed too, and payload
  types drive property tests. This is the standing cost of specification by example and it does not
  go away.
- **Cross-cutting reporting.** The most predictable client complaint. The event log as reporting
  substrate is the intended answer and it is unproven.
- **Emission can be bypassed.** A direct `Repo.update` changes state and emits nothing, so the log
  shows a process that never happened — silence read as compliance. Mitigations: forbid `Repo`
  outside a module's own boundary (lintable), and consider trigger-level capture as a cross-check
  on the tables that matter.
- **Contract rot.** If maintaining the contract costs more than the drift it catches, teams stop.
  Primary product risk; the pilot should measure it.

  Mitigation is a design requirement, not discipline: the contract is never hand-typed. Compiled
  from workshop artifacts, and thereafter drift detection *proposes* changes as a reviewable diff
  rather than reporting them. Never generated from the code — a contract derived from the
  implementation agrees with it by construction and detects nothing. Cost close to zero, not zero.

## 15. Packaging and sequencing

Mechanics behind ADR §16–17.

**The generator is thin because the pieces exist.** `mix pns.new` delegates to `mix phx.new`, then
installs the packages via Igniter, which patches config and the supervision tree; then docker-compose,
CI, migrations, seed. A few hundred lines of orchestration. Since each package ships its own Igniter
installer, `mix pns.new` is not privileged — an existing Phoenix application runs
`mix igniter.install pns_core` and arrives at the same place.

**Two capabilities that sound alike and are not.** Three minutes to a *running* project is
docker-compose plus seeds, and can exist on day one with no generator at all. Three minutes to a *new*
project needs the generator, and is required only for demos, open-source adoption, or the second
client.

Sequence, triggered by events rather than dates:

1. *First client* — packages as path deps in a monorepo beside the client app. No `mix pns.new`.
   docker-compose from the start. The only discipline: anything not client-specific goes in the
   package.
2. *Second client starts* — packages to hex, `mix pns.new` written. By then its output is known,
   because it has been done by hand once.
3. *Open-source adoption* — Igniter installers per package, so the generator stops being the only
   entry point.

Building the generator now would be a distraction; building it when something copies between two
applications for the second time is not. The trigger is that copy, not the calendar.

**The deploy command** has to handle database provisioning and migrations, secrets, the first admin
user, a domain, and `--env`. It must be parameterised by target from the start — a command that only
works against our cloud account is a demo. One opinionated target ships open source; client-specific
infrastructure stays with that client until a pattern repeats.

**Deployment shape** is four applications — identity bought, engine, dashboard inside the engine in v1,
frontends separate. Stated with its diagram in [ADR §16–17](architecture.md#d-what-ships),
and argued in [design rationale](design-rationale.md#1617--almost-nothing-is-generated-and-what-ships-is-hex-packages).

## 16. Where to look for what

Three documents, three questions. This one answers **how it is built and what it looks like** — code
shapes, schemas, tables, library choices, implementation traps.

| Question | Document |
| --- | --- |
| Why does the engine work this way? What was assumed? | [architecture](architecture.md) — problem, `§1`–`§18`, the bets, falsification |
| Why is it like this? What did each decision beat? | [design rationale](design-rationale.md) — the argument, decision by decision, plus vocabulary and alternatives in full |
| How is it built? | this file |
| What is done and what is next | [`PLAN.md`](../../PLAN.md) — the only place state is updated |

Mapping from a decision to the section here that shows its shape:

| Decision | Here |
| --- | --- |
| §2 contract is code | [§1](#1-the-contract-and-the-code-it-governs) — the DSL, splitting, lifecycle, ownership |
| §4 generated/hand-written split | [§1](#1-the-contract-and-the-code-it-governs), [§7](#7-generation-workflows) |
| §5–6 modules and ownership | [§2](#2-compile-time-enforcement) |
| §7–8 events and the log | [§3](#3-event-log) — schema and the correlation trap |
| §9–10 dispatch and idempotency | [§4](#4-delivery) — the split table, residual cost |
| §11–12 adapters and configuration | [§10](#10-external-adapters), [§11](#11-configuration) |
| §13 three layers | [§6](#6-testing) — which tests come from where |
| §14 harness and the ladder | [§2](#2-compile-time-enforcement), [§8](#8-skills) |
| §15 processes | [§9](#9-dashboard) — the overlay and its constraints |
| §16–17 packaging | [§15](#15-packaging-and-sequencing) |
| §18 rules and examples | [§5](#5-conformance) — the coverage join and the two weaknesses |
| Libraries and prior art | [§12](#12-prior-art), [§13](#13-library-decisions) |
