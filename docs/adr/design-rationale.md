# Design rationale

Why [the architecture](architecture.md) is the way it is. That file states each decision and what it beat in
one line; this one carries the argument behind it, decision by decision, plus the vocabulary, the alternatives
in full, and the reasoning behind the open questions.

**Not reviewed since it was moved here.** The content is from the design sessions of 31 July and 1 August and
has not been checked against what the prototype has since built — unlike
[architecture](architecture.md) and [technology notes](technology-notes.md), which carry dated corrections.
Treat a claim here as an assumption from before the code existed.

## Vocabulary

One word does most of the damage in a document like this, so it is fixed here and used only this way.
Partners and the client's technical owner read this material; a term that means two things costs more than
a term that is unfamiliar.

| Term | Meaning here |
| --- | --- |
| **Process** | A business process — month-end closing, invoice correction. First-class in the contract, a row at runtime, the unit of contract splitting, and the dashboard's navigation unit. It never means an OTP or operating-system process. Where one of those is meant, the text says *BEAM process*. |
| **Contract** | The Elixir module declaring events, payloads, processes, ownership, cadence, retention, trace assertions, rules and examples. The artifact the client authorised. |
| **Rule** | A business rule, named in the contract and implemented as exactly one pure function. The contract names it and pins it; it never contains it. |
| **Example** | A concrete case for a rule — this state, this command, these events or this rejection. Readable aloud to the process owner and executable as a test. Not a scenario, a script, or a user story. |
| **Event** | A fact that already happened. Past tense, immutable, any number of subscribers. |
| **Command** | An intention. Exactly one handler, and it can be rejected. |
| **Handler** | Code reacting to an event, running either inside the state change's transaction or as an Oban job. |
| **Registry** | The event graph recovered at boot from the compiled modules. The source of the static graph, and the reason event edges are visible at all. |
| **Trace assertion** | A declared claim about a process: from this event, eventually that one, within this time, or else that one. |
| **Harness** | The generators, checks and skills that enforce the structure and teach it. |
| **Adapter** | The only code permitted to talk to an external system. |
| **Declared / observed** | Declared is what the contract says. Observed is what the event log recorded. Their difference is the product. |

## Why it holds up against the alternatives that exist

Ash and Open Mercato give you a framework, but do not know what was supposed to be built. Celonis infers a
model from logs of software it does not control. APM watches the machine, not the promise. A
client-authorised contract plus a system that controls its own emission makes conformance exact rather than
inferred.

**Neither method underneath is a moat.** DDD is twenty years old and event-driven architecture older; both
are taught, documented and available to every competitor and every commodity model. What is not in any book
is the contract as an authorised, versioned, checkable artifact and the conformance join built on it.
Arguing this leg commercially on "we do DDD" or "we do events" concedes the ground where we are ordinary —
which is a separate question from the argument made to *contributors*, where the code shape does the work.

Code is open source. The workshop and the evidence are what we charge for.

*Superseded 21 September 2026.* Two editions instead: Community open, Enterprise a fork of it, and the
line between them runs through consistency **between** applications rather than through code against
service. What is inside one application — contract, log, conformance — is free; reasoning across
applications is paid. The argument made to contributors, two paragraphs up, is unaffected: the code shape
still does that work. What changes is the sentence about what we charge for. Full statement in
[architecture.md](architecture.md#d-what-ships) and in [PLAN.md](../../PLAN.md), "Dopisek 21 września (12)".

## Context, and what changed since the July sessions

Two implementations are contracted; one running, one starting now. No spare capacity, and a runway that
makes every month of platform work expensive.

Decision 005 (`empowered-house-context/decisions/005-adopt-empoweredhouse-strategy.md`) fixed the product boundary as
architecture-neutral. Decision 006 (`empowered-house-context/decisions/006-end-rafal-slosarz-collaboration.md`) vacated the
architecture seat and narrowed the direction to *model the domain, generate the code, watch it run*. This
proposal sits inside those boundaries.

Three things changed.

**Isolation as a security boundary is settled, negatively.**
`output/drafts/RUNTIME-VARIANTS-ADR.md` §3.1 shows a shared BEAM node is not a security boundary and no
mitigation preserves both properties. The event bus is a modularity mechanism, not a control mechanism.
That closes one axis and not the other — whether cross-module data access should be checked at runtime
rather than only linted is a different question, raised on 3 August and answered as a deferral.

**Modular design got cheaper.** Its cost was boilerplate and duplicated data. Generation removes most of
that, so split more aggressively than the doctrine could justify in 2019.

**The constraint moved from writing to verifying.** Comprehension can no longer come from reading the code.
It has to come from a model derived from the code and from observed behaviour.

One caveat on event-driven design: an event converts an explicit dependency into an implicit one. A
function call shows up in `mix xref`; an event edge does not show up anywhere. Without a registry and a
derived model, event-driven design *reduces* comprehensibility rather than increasing it. That is what
makes the registry load-bearing here rather than optional.

The promise remains the one in the charter (`empowered-house-context/wiki/pns/charter.md`):

> Turn business-readable intent into governed software the company owns and can safely change,
> independent of which tool, model, team, or stack produced the code.

"Can safely change" is about the customer's process, not our architecture.

Not an argument for any of this: that the team already knows Elixir. It matters for delivery risk and may
be decisive, but it is not a reason the architecture fits, and it is never the external argument.

## Relationship to Domain-Driven Design

Nothing here replaces DDD. The two are not alternatives — they are a stack. DDD does the strategic work of
deciding where the seams run and what the words are; event-driven design is the code shape we generate
into; the contract is the only novel part. Long form, with each claim's provenance separated, in
modular design (`empowered-house-context/wiki/pns/modular-design.md`) and
event-driven doctrine (`empowered-house-context/wiki/pns/event-driven-doctrine.md`).

| Question | Answered by |
| --- | --- |
| What are the modules, what are they called, where do the seams run | DDD strategic design — bounded contexts, context mapping |
| Which parts deserve bespoke software at all | DDD subdomains — core, supporting, generic |
| What must be consistent inside one transaction | DDD aggregate invariants, which is what feeds the dispatch split |
| What words does everyone use | DDD ubiquitous language — the event names and their `label:` fields are exactly this |
| How do modules communicate while running | EDA — published facts, subscribing handlers |
| What evidence exists that any of it ran | EDA — the log. DDD produces none. |
| What was agreed, and is it still true | Neither. That is the contract, and it is the only part of this that is not commodity. |

DDD is already load-bearing here, only unnamed: EventStorming (§1), ubiquitous language (§9), bounded
contexts with `boundary` enforcing the lines (§2, §5), aggregate invariants (§6), an anti-corruption layer
(§11). **Strategic DDD wholesale, tactical DDD selectively** — aggregates as invariant boundaries yes;
repositories over Ecto, factories, domain services and a value object per field no, because a model
generates those enthusiastically and the result is Java in Elixir.

**Rejecting event sourcing is not rejecting DDD.** We need event *history*, not event *sourcing*. Anyone
who treats those as the same thing will read the record as more heterodox than it is.

*Corrected 26 September 2026, v2 plan E6, in the code that confirms it* ([contract v2](contract-v2.md) §2,
§10–11, §18). v2 sources. A unit of a v2 contract is an aggregate whose state is folded from its own stream
through `evolve/2`, and `EhOsContract.dispatch/3` appends under the version of the stream it read. History was
enough while the log recorded what the application's own state change had decided. It stopped being enough
once the decision became a pure function over events, the shape the next paragraph argues for: to decide, it
has to read them. The distinction the paragraph draws still stands. The log is still the history the
conformance half reads, and it is now also what a unit is built from. What the rejection of Commanded still
holds is under "Alternatives considered".

**Why event-driven, then, if DDD could express the same system?** Because of what it does to *generated*
code, which is the only axis where the two differ for us: `command -> {:error, reason} | [events]` is a
pure function with an enumerable output, so a model's work can be checked against an example without
running the rest of the system. Capability-on-domain-object code mutates state through a service, and
judging it needs context the checker does not have. That is the argument, and it is about verifiability
rather than doctrine.

**The second leg comes from inside the tradition.** The doctrine's own source names two problems it leaves
unsolved: what happens when an event changes shape while history holds the old one, and the fact that
nobody can see the event graph, so nobody knows what subscribes to what. Contract-as-code plus a derived
registry answers both. That is a stronger defence than any competitor comparison, because the gap is
admitted by the people who built the practice rather than asserted by us. Honest half: event versioning is
still open here too; the contract version on every event bounds the damage without fixing it.

Recorded because it matters: this choice was originally made on instinct, not research. The reading since
supports the code shape and the modularity, and supports neither a security claim nor a competitive one.

---

# Why each decision

## A. Workshop to running software

### §1 — the contract originates in a facilitated workshop

EventStorming produces the same concepts the contract declares — events, commands, actors, policies — so
there is no translation step between discovery and the artifact. Its real output is the rules nobody wrote
down. It is also where authorisation happens: the client agreed to *this*, which is what the charter's
Authority property needs.

The output is discovery-grade, not generation-grade, which is why §3 keeps a human review gate after
compilation. And the workshop must leave with **examples**, not only policies — a policy without examples
is a sentence everyone nods at and nobody can check.

*Instead of* generating from the workshop graph, or from an analyst's write-up: discovery-grade output
carries no invariants, error paths, idempotency or types, so a generator invents them differently each run.

*Risk:* this lengthens the workshop, and facilitation capacity is already a recorded gap
(decision 007 (`empowered-house-context/decisions/007-filip-kozlowski-joins-pns-team.md`)).

### §2 — the contract is code, in the client's repository

One artifact is the compile-time registry, the generation input, the source of tests, and the reference for
observed behaviour. `git diff` is the change description.

The workshop output is upstream exactly once: compiled into the contract, reviewed by a human, and from
that point the contract is the source. Documentation — Event Catalog, diagrams, anything client-facing — is
rendered *from* it rather than maintained alongside it. Two editable representations of the same thing
diverge, which is precisely the drift this product exists to detect, reproduced inside our own toolchain.
The generator therefore reads the contract and never a third-party documentation format whose schema and
release cycle we do not control.

Events, processes and traces declare topology and timing. Rules and examples are what let the contract
reach *behaviour*, which is what makes "tests generated from the contract" true rather than aspirational.

**Developers edit it, the process owner approves its content, enforced with `CODEOWNERS`.** The reason is
not procedural: the contract is the artifact the client authorised, and if a developer can change it
quietly, the charter's Authority property stops holding.

Contracts split per process and self-register rather than being aggregated by a parent module, so adding
one recompiles nothing else.

### §3 — generation is layered; only small parts are stochastic

Contract from workshop artifacts, reviewed by a human — the one mandatory gate. Structure deterministic.
Only decision functions go to a model, one at a time, each with its test already present.

"Its test already present" is the load-bearing phrase. Without the examples from §18, a decision function
goes to a model with a prose task description and no acceptance criterion, which is ordinary code
generation with extra steps — and the extra steps are the part we would be charging for.

### §4 — generated and hand-written code are physically separated

Generated code is a fork the moment someone edits it, and a generator that cannot be re-run is a one-time
scaffold. So decision functions live where the generator does not reach, and regeneration stays safe and
narrow. Migrations are append-only: the generator proposes new ones and never rewrites old ones.

## B. Runtime

### §5–6 — one engine, one Postgres, one module per process owning its tables

One monolith and one Postgres rather than services, because getting the module boundaries right first is
what makes the later move outward cheap, and the reverse move is not.

*Instead of* umbrellas, which separate at build time without enforcing anything, or separate services,
which make transactional enqueue impossible. And instead of one schema shared across modules, which grows
with every feature and forces edits to functions that already worked. **Database coupling is the coupling
nobody counts.**

Cross-module joins are forbidden and linted, **and database views over another module's tables with
them** — a view looks like encapsulation and is a join with extra steps. Duplicated data is permitted only
where one copy is named as the source of truth and the other is a cache; without that clause, copying
produces two masters, which is worse than the join it replaced.

How to decide where the boundaries run — verbs over nouns, outcome versus entity, the four design
questions — is modular design and data ownership (`empowered-house-context/wiki/pns/modular-design.md`). That doctrine is
what a generated codebase gets wrong, and §14 deliberately does not enforce it, which is why it is a skill.

**This says one *engine*, not one deployed thing.** Identity, the frontends and eventually the dashboard
are separate applications, and none of them weakens this decision, because what it protects is a single
transaction: the state change and its event committed together. That requirement only ever concerned the
engine. Authentication happens before a command is issued, and a frontend never writes.

**Ownership is enforced in CI, not at runtime — deliberately, for now.** The 3 August review asked for the
stronger version: a check at the repo seam rejecting any query that reaches outside the calling module's
own schemas. There is nothing to design for it — the access levels already exist as the module boundaries,
and `boundary` plus the Ecto schemas already know which module owns which table, so no declaration and
nothing in the contract is required.

It is deferred on evidence rather than on principle. No such violation has been observed; the demand for it
is an unverified claim about what technical buyers ask; at pilot scale one person reads every diff; and the
lint already covers the ordinary case, since models generate idiomatic Ecto rather than string SQL. The
strongest reason came last: **a check enforces a boundary, so it can only be as right as the boundary is.**
Enforcing a wrong split turns a design problem into a production incident, and the real risk with generated
code is the boundary being drawn wrongly rather than crossed. Decomposition first is forced, not preferred.

### §7–8 — events are facts, commands are intentions, and the log is append-only

*Instead of* CRUD-shaped mutations on shared entities, which leave nothing to subscribe to, nothing to log
and nothing for the contract to assert on. And instead of the Oban job table as the record: a queue is
operational state — pruned, retried, and holding what was scheduled rather than what occurred.

**Why the contract version is on every event.** Not bookkeeping. The static graph describes the deployed
code; the log spans many versions. Without it, every deploy that removes an event turns legitimate history
into apparent drift, and the dashboard is distrusted within two releases. Cheap now, impossible to backfill
later — the same argument as correlation ids.

**Why the payload is declared and stored as JSON.** An event has a fixed core: name, timestamp, actor,
correlation and causation ids, contract version. Everything else is a payload whose shape the contract
declares and which persists as JSON, read defensively — interpret the fields you understand, show the raw
value where you cannot. Declared shape at write time, tolerant reading at read time. The declaration is not
decoration: per-field retention cannot apply to an opaque blob, and the generated payload-conformance tests
have nothing to assert against without it. But the storage stays JSON, so adding a field is a contract
change rather than a migration across years of rows.

**Why retention persists by default.** A field nobody marked is stored; `:hash` and `:drop` are explicit,
and nothing forces a decision on personal-looking fields. Missing evidence is a silent product failure,
while excess data is visible and fixable. Volume is handled by an Oban job purging by age, which **bounds
the conformance window** — the client-facing promise cannot outrun what is still on disk.

*Accepted risk, recorded rather than mitigated:* with personal data the exposure is a function of **kind,
not volume**. One unmarked name field is an exposure whatever the row count, and purging by age does not
address it, because it deletes by date rather than by class. A compile-time gate on personal-looking fields
was proposed and declined.

**Why the log lives with the client.** Their application, their database, their infrastructure; we read it
to produce the evidence artifact. That keeps the data-processing obligations on their side, at the cost of
hosted conformance history not being a product in version one. The schema therefore assumes nothing about
where it lives — a requirement rather than a remark, since it is the single condition keeping hosting
available later as a product instead of a rewrite.

*Corrected 26 September 2026, v2 plan E6* ([contract v2](contract-v2.md) §10–11, §18). For a v2 contract the
log is not written in the state change's transaction, because **the append is the state change**: there is no
separate state row to write beside it. A unit's state is what `evolve/2` folds from its stream, and read
models are projections written in the append's transaction or after it. The contract version, correlation
and causation stay on every event, and the payload stays declared and stored as JSON, written by
`EhOsContract.Codec`. Retention by `:hash` and `:drop` becomes crypto-shredding, and that correction comes
with the stage that builds it, E8.

### §9–10 — dispatch split by the transaction boundary, and idempotency

**Why the restriction makes failure semantics coherent.** An in-transaction handler that raises rolls the
whole transaction back and the caller gets the error. That is correct: derived state which cannot be
written must not diverge from its source, and there is nothing to retry because nothing happened. The same
answer would be absurd for a handler sending mail, which is exactly why such handlers are not permitted to
be synchronous. The alternative — swallowing the error — reintroduces silent failure, the exact thing this
product exists to detect.

*Instead of* everything through Oban, which is conceptually cleaner and breaks read-after-write: a user
issues an invoice, returns to the list, and does not see it. In back-office software that is a support cost
rather than a theoretical concern. Or everything synchronous, where a handler sending mail can roll back a
business transaction.

Every async handler eventually runs twice, so idempotency is either declared and tested or discovered in
production. `Phoenix.PubSub` and `GenStage` are rejected for anything the contract asserts on because both
lose events silently — fine for live UI, never for evidence. Broadway sits at the edge if a client brings a
broker.

### §11–12 — adapters, declared dependencies, and two configuration axes

**Why the declared dependency changes what a check can say.** Because the contract records which events
depend on an outside system, a conformance check has three answers rather than two: we broke the rule, the
rule held, or the clock was stopped because a declared dependency was unavailable. For an accounting client
that is the whole question — were we late, or was the ministry down.

*Instead of* calling vendors from domain code, after which that distinction is unavailable. Events are
named after the business fact, never the vendor, and states with legal weight stay separate — for KSeF,
*submitted*, *accepted* and *UPO held* are three events. Adapters are also the first reusable capability:
KSeF, JPK, Comarch and bank feeds are not client-specific.

Keeping implementation-swapping and environment configuration apart is what lets you express
real-adapter-against-sandbox, which is the scheduled test that catches an external API change. Collapsed
into one switch, that test is unavailable.

## C. Verification and method

### §13 — three layers, each answering a different question

What each layer cannot do:

- **Black-box observation cannot localise a fault.** Unit tests and module boundaries do that.
- **Unit tests do not detect drift.** Every test can pass while the share of orders invoiced within 24
  hours declines for three weeks.
- **Neither catches a wrong rule correctly implemented.** Only contract assertions reviewed with the
  client address intent — and only if the contract carries something a client could actually review, which
  is what rule examples are for.

A unit test cannot see an invoice that was never filed, because nothing failed.

### §14 — the harness enforces structure, teaches the method, stays out of modelling

Enforced: boundaries, data ownership, no cross-module joins, no dynamic event publication, every event
declared and owned and tested, every rule carrying at least one example, idempotency tests, diff coverage,
pure functions, one handler per command.

Not enforced: whether something should be an event, whether a module should split. Those are workshop
judgements, and *a linter with opinions about them gets disabled within a month.* The rule for what goes
in: enforce what is mechanically decidable, teach the rest — a check that is sometimes wrong about a
judgement call costs more than the judgement call.

**Knowledge is pushed as far up this ladder as it will go.** If something can be a compiler error it should
not be a skill.

| | Strength |
| --- | --- |
| Compiler error | Cannot be ignored |
| CI check | Skipped only deliberately |
| Generator default | The right thing is the easy thing |
| Skill | Loaded when the task matches; guides judgement |
| `AGENTS.md` | Always loaded, so the budget is scarce |
| Documentation | Read only when someone goes looking |

Half the harness's value is communication. A generator teaches by producing; a failing check explains the
rule rather than reporting a violation. It serves four audiences — the coding agent, a new hire, an
implementation partner, and the client's technical owner — and the last two are why this is product work
rather than hygiene. SOLID needs translating or generated code becomes Java in Elixir; dependency inversion
in particular stays confined to I/O seams.

Task-scoped **skills** carry the prose layer, ship with the package and are versioned with it, so a
partner's repository gets the current standard through `mix deps.update` rather than through tribal
knowledge. What belongs in a skill is what a check cannot express: why the rule exists, what the tempting
wrong approach looks like, which of several valid options is preferred.

**Decomposition is the first skill, and the refusal above is why it is needed.** Whether a module should
split is a judgement a check cannot make, and until now that meant nobody made it — tolerable when a person
is designing, not when a model is. The doctrine is
modular design (`empowered-house-context/wiki/pns/modular-design.md`); the skill built from it is what stops generated code
producing a `Job` context with a slug column, every time.

## D. What ships

### §15 — processes are first-class; version one watches, it does not steer

**Why cadence and not only a deadline.** The deadline says when one instance is late; the cadence says how
often an instance is due at all, which is the only thing that makes "this never happened" answerable. A
month-end closing flagged dead after a week of silence is noise, and a dashboard that starts with noise is
not opened twice.

**When a process derails, a person decides.** The system detects it and puts it on a human's work queue; it
does not choose the recovery. So no recovery paths in the contract, and no workflow language. The condition
that makes this generative rather than merely cheap: **the human's decision is issued as a command and
emits events.** A row edited by hand leaves no trace, and the log then has a hole exactly where the
interesting thing happened. Issued as commands, every exception becomes a recorded case, so the recovery
rules worth automating later are ones that were observed instead of guessed.

The cost is named rather than argued away: a human on every exception caps throughput at human speed, which
is in tension with the throughput case for an accounting client. That tension is what the pilot measures.

*Instead of* sequence, branching and compensation declared in the contract — that is a workflow language,
maintained before we know whether two clients need the same one. And instead of code choosing the recovery
in version one: a wrong recovery rule acts on money and filings by itself, which is worse than no recovery
at all.

- *Commits to:* the process row, which the dashboard needs anyway.
- *Leaves open:* whether the contract describes sequence, branching and undo-on-failure.
- *Weakness:* compensation logic keeps living in individual modules, so the VAT module learns about the
  filing stage — the coupling events were meant to remove.
- *Cost if wrong:* reconciling several hand-written steering modules. The expensive failure is the process
  row being the wrong idea — processes that nest, or one event in two processes — which invalidates the
  pilot's contract.

*Corrected 26 September 2026, v2 plan E7b* ([contract v2](contract-v2.md) §12). Code now chooses some
recoveries: a process manager's timer or reaction issues a command by itself. What the argument above feared
— "a wrong recovery rule acts on money and filings by itself" — is bounded rather than removed. The contract
lists every command a process manager may issue, dispatch refuses any other, a scenario pins what each
reaction issues, and the command goes through the unit's invariants like a person's. The weakness named
above is answered too: steering lives in one declared place per process instead of in the modules it
coordinates. What still holds is the refusal of a workflow language: no sequence, branching or compensation
is declared, only reactions to one event or one timer.

### §16–17 — almost nothing is generated, and what ships is hex packages

Generated code is a fork the moment it lands, so this split decides whether any of this is upgradable in
three years.

| Generated — the client edits it, or it is inherently project-specific | A dependency — we want to update it |
| --- | --- |
| `mix.exs`, `config/*`, `application.ex`, `router.ex` | `PNS.Handler`, `publish`, registry macros |
| User schema and its migration (clients always add fields) | Event log schema and migrations |
| docker-compose, CI, deploy target config | Permission engine |
| The exemplar process, which is meant to be edited or deleted | Dashboard, mounted with one line in the router |
| | Checks, generators, adapters, skills |

Everything valuable is on the dependency side. What remains generated is Phoenix boilerplate, a user schema
and deployment config. Migrations are the case in between and the pattern is Oban's — they live in the
dependency, the client's file calls `PNS.Migrations.up(version: n)`.

**The generator is built when something gets copied twice, not on a date.** Building it now would be a
distraction; building it when something copies between two applications for the second time is not.

*Instead of* extracting a template up front, or a metadata-driven configurable product as Twenty and Open
Mercato do — which means competing on volume of pre-poured concrete against projects that have more of it.
And instead of a library that only works inside an app we generated, which rules out every existing Phoenix
codebase, including the ones a partner already maintains.

**Why the deployment shape is several applications.** Identity is bought rather than written because SSO,
the Google and Microsoft integrations, user lifecycle and audit are commodity infrastructure and not what
this leg is differentiated on; writing it would be a quarter spent on the part every competitor also has.
The dashboard stays inside the engine in version one, because split out it would need either direct access
to the engine's database — breaking the ownership doctrine one level up — or its own read surface on the
API, and neither is worth buying before there is a reason.

**Why the API is generated from the contract.** Once a third party may write a frontend against it, the API
needs stability, versioning and documentation, and a hand-maintained API beside the contract is two
editable representations of the same thing. The event and command declarations already say what the system
can do.

**Why we build the first frontend ourselves even though it can be outsourced.** The pilot has to close the
loop between a process owner approving examples and the diff being judged useful; a third party lengthens
that loop and makes the pilot's date depend on someone with no stake in the answer. Outsource from the
second client, on the same trigger as the generator.

## E. Rules and examples

### §18 — the contract states rules by example, not in a rule language

Events, processes and traces declare topology and timing. They say nothing about the condition under which
a command is rejected, or which event results from it. That gap is not cosmetic: a contract that cannot
reach the rule cannot generate a test for it, cannot give a model an acceptance criterion, and cannot be
reviewed by the client on the one point where being wrong is expensive. But a contract that expresses rules
*declaratively* turns into a programming language nobody can check or read aloud.

The answer is neither. A rule names one pure function; examples pin it. Four properties, and nothing else
has all four at once:

- **Readable aloud to the process owner.** "If we have them as a VAT payer and the register says struck
  off, the month does not open and a notification goes out" is a sentence an accountant confirms or
  corrects. A rule written as declarative logic is one they sign without reading.
- **It is the test**, not a description of one, so nothing has to invent the assertion from prose — which
  is the objection that rules out generating from the workshop graph.
- **It is a specification a model can be held to:** make these pass.
- **It cannot express the general rule.** That is the feature. The rule stays in code; the contract stays
  out of language territory.

*Instead of* a declarative rule language, EARS-style When/Then. Prose is not executable, so something has
to translate each constraint into a test — the same invention problem as generating from the workshop
graph, performed once per rule instead of once per run. And a notation expressive enough for VAT
thresholds, correction windows and deduplication precedence is a programming language with worse tooling.
The `wiki/pns/ears-requirements-format.md` draft is the version of this idea we did explore; it is
superseded.

**Enforced: a rule with no example does not compile.** A rule without examples is a declaration of intent —
nothing can be generated from it and nobody can approve it.

Where examples come from: the workshop already produces the raw material — policies of the form "when X,
then Y", and the cases that currently go wrong. The facilitation change is one extra question per policy.
Authorship follows events: developers write them because they must compile, the process owner approves the
content because it is business meaning, same `CODEOWNERS` gate.

This also sorts out which tests are durable:

| Test | From | Approves the content | Lives as long as |
| --- | --- | --- | --- |
| Structural — payload conformance, idempotency, dispatch mode | declarations | nobody, generated | the declaration |
| **Rule examples** | workshop, per rule | **process owner** | **the business rule** |
| Implementation unit tests | developer or model while writing the code | developer | this implementation |

Only the middle row survives regeneration. "The test is the durable artifact and the code is disposable"
holds for examples; implementation tests are exactly as disposable as the code they cover.

**Not enforced: how much state an example may set up.** A limit invented before the first workshop would be
wrong, and a check that is sometimes wrong about a judgement call gets disabled within a month. What is
measured instead is the thing actually at stake: **whether the process owner corrects anything.** Thirty
examples and zero corrections means nobody read them, which turns a falsification condition into an
observation. The size of `given:` is only a proxy for it.

Two weaknesses, named rather than mitigated away: examples **under-specify**, since three of them pass
under an implementation that special-cases three inputs; and they are a **maintenance surface** that rots
the way all tests rot, tolerable only because an example *is* a test and fails loudly. Both are expanded,
with the coverage join against the log, in [technology notes §5](technology-notes.md#5-conformance).

*Corrected 25 September 2026, v2 plan E5* ([contract v2](contract-v2.md) §6, §18). The four properties
survive the move to v2 and the shape does not. A rule is an invariant of a unit, and an example is a
Given-When-Then scenario whose `given` is a list of events: the decision reads a state folded from history,
so an example states history, not inputs. "A rule with no example does not compile" is now "an invariant
with no scenario rejected on it does not compile" (S8), kept an error where ESDM makes it a warning. The
contract no longer names a function: an implementation names the contract, and the scenario runs against it.
The table's middle row still holds, and so does "not enforced: how much state an example may set up" —
a scenario may give as many events as it needs.

---

## Alternatives considered

Each decision above carries its *instead of*. These are the rejections that need more than a line.

| Rejected | Because | Kept from it |
| --- | --- | --- |
| Commanded and full CQRS/event sourcing | Commits the whole application to aggregates, eventual consistency and permanent upcasting; most of a back-office app is not shaped that way, and event-sourced models are harder for a model to generate correctly | The correlation model. Viable for one bounded context later |
| Kafka, RabbitMQ or Broadway in the core | Transactional enqueue is impossible against an external broker, so an outbox gets built anyway — on infrastructure someone must operate | Retained as edge adapters |
| Everything through Oban | Read-after-write stops being reliable, which in back-office software is a support cost rather than a theoretical concern | — |
| Umbrella applications | Build-time separation without boundary enforcement, plus config and release friction | — |
| Generating directly from the EventStorming graph | Discovery-grade output carries no invariants, error paths, idempotency or types | — |

*Corrected 26 September 2026, v2 plan E6* ([contract v2](contract-v2.md) §2, §10.6, §12, §16). The Commanded
row, reason by reason, as v2 stands. *Commits the whole application to aggregates*: v2 takes aggregates per
contract, not for the whole application; a contract without an implementation stays legal (D3), and v1
contracts run beside v2 until the cut. *Eventual consistency*: still rejected. A v2 command's read models and
policies may run in the append's transaction, so read-after-write holds for them. *Permanent upcasting*:
accepted, with `schema_version` and an upcaster per type (§10.6), built when real data first needs one.
*Harder for a model to generate correctly*: answered by the contract instead of by avoiding sourcing.
`emit/1` takes struct literals checked at compile time (I4), and dispatch holds every decision to its
declaration at run time. Commanded itself is still not used: v2 keeps its own store in Postgres, chosen after
comparing it with Commanded's EventStore (§2). Kept from it: the correlation model, still.

**Ash Framework as the foundation.** Ash interprets declarative resources at runtime; the premise here is
that code is cheap, so declarations should generate ordinary Phoenix and Ecto. Generated ordinary code is
readable by any Elixir developer, including the client's team and a partner. Worth borrowing the
declarative-resource idea for the contract DSL. Closest competitor to this leg.

*Corrected 25 September 2026, v2 plan stage E3.* The borrowing went further than "the idea". v2's DSL is
built on **Spark**, the DSL engine Ash itself is built on (`docs/adr/contract-v2.md` §2): sections,
entities, schemas, transformers and the generated formatter list are Spark's. The first half of this
paragraph still stands. Ash's *runtime* is not adopted, no resource is interpreted at run time, and what a
declaration compiles to is plain data plus ordinary modules. What changed is that "worth borrowing" became
a dependency on the engine under Ash. E3 checked the properties v2 relies on before any contract was built
on it: an error points at the file and line of the declaration, reordering declarations does not move a
version, a domain module compiles under a consumer's strict `boundary`, and the formatter export reaches a
consumer. One caveat surfaced that the ADR did not foresee. An entity's options cannot be given both as a
trailing keyword list and alongside a `do` block, so a declaration with a block takes its options inside
the block.

**Taking [`oban-events`](https://github.com/allocator-one/oban-events) as the emission layer.** It
independently arrived at almost the same design — `emit/2`, handler behaviour, correlation and causation,
transactional emission, retries, idempotency key — so the API shape and metadata model are worth copying.
But it dispatches exclusively through Oban: `emit/2` returns created jobs, and every handler runs after the
transaction commits. That is one of the two modes §9 requires, and the other cannot be added around it,
because an in-transaction handler has to run at the emission site before the transaction closes. It also
keeps no event log, and maintains its event list by hand where we need it derived from the contract.
Emission is therefore ours; the reference is not. That it stops exactly where this product starts is market
evidence.

**A metadata-driven configurable product, as Twenty and Open Mercato do.** Dynamic objects, JSONB fields,
runtime interpretation. That investment is what makes them configurable platforms rather than bootstraps,
and adopting it means competing on volume of pre-poured concrete against projects that have more. A
prospect piloted Open Mercato, found architecture problems, and built in-house. Copy Twenty's onboarding
experience, not its metadata layer. Both are viable generation targets.

## The open questions, and why they are open

**Why event-driven, argued for an outside technical audience.** The verifiability argument above is the
answer in outline; what is missing is the research Michał asked for. The distinction that matters: this is
the argument for contributor adoption, not for the moat, where the position remains that neither method is
a differentiator.

**REST or GraphQL for the API.** Opened by the screens decision, and not a detail once a third party may
build the frontend. Michał argued against GraphQL on adoption grounds — with REST any developer can
maintain it, with GraphQL the pool is smaller, and an outsourced frontend makes the size of that pool
matter more. The counter is equally real: GraphQL lets an external team fetch what it needs without asking
us for an endpoint each time. REST widens *who* can build it; GraphQL reduces *how often they need us*.

**What the evidence report says about a period whose definitions changed.** Narrowed from the broader
question about event shape, which overstated the reach: the dashboard joins on names, order, timing and
process membership and never reads a payload, and a frontend always runs against the current API version.
Old payloads are read only where a claim is made about the *past* — the evidence report, reporting from the
log, and the `given:` state in a durable example. Declining to answer is consistent with a product about
knowing what you know.

Two things bear on it. The contract version is only trustworthy if changing a payload declaration without
bumping it fails CI, which is cheap now and unavailable later. And purge-by-age is an **accidental** answer,
since it deletes the oldest and therefore old-shaped events — accidental answers should be made deliberate
before a client asks about a period we quietly purged.

Genuinely unsolved, here and in the literature: a change of *meaning* with no change of shape. `deadline`
moving from calendar day to business day touches no declaration, so no lint, schema or JSON fallback
catches it.

**Prior art on constraining and verifying generated code against a specification.** A task rather than a
question — five named directions, an owner and a timebox are in
review-2026-08-03 (`empowered-house-context/output/20260803-adr-008-review.md`). Conformance checking is
the one that could change the design: declared-versus-observed is an established academic field with
algorithms and thirty years of literature, and this record does not engage it.
