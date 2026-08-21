---
name: add-event
description: DRAFT, not yet reviewed. After `module-boundary-check` has already decided a fact belongs in the contract as a PNS event — never to decide that question itself — walk the `event` macro's full key set against `PNS.Contract`'s current source, confirm the fact is past tense with more than one interested party (not a command in disguise), pick a payload type from the closed set (including the `_minor` money convention and the "cannot be a nullable field" DEC-05 gap), decide `identity` and whether it is even narrower than the process `instance` it lives under, and check the event name traces to workshop material. Use when about to write a brand-new `event :name, ...` declaration, in a new or an already-existing contract module. Not for deciding whether something should be an event at all (see `module-boundary-check`, which hands off here once the answer is "yes"); not for widening or reinterpreting a field, identity, or trace on an event that already has real historical data (see `change-contract`, whose impact-analysis table this skill does not duplicate); not for writing the handler that reacts to the event (see the sibling skill `write-handler`, being written in parallel and not yet checked into this repository).
---

# Adding a new event to a PNS contract

DRAFT — not yet run against a real event addition. Review before trusting it. Every claim below
about the `event` macro's keys, the payload type set, the compile gates, and what `owner`/`identity`
actually do was checked against this package's source on 21 August 2026 — `packages/pns_core/lib/pns/contract.ex`,
`packages/pns_core/lib/pns/handler.ex`, `packages/pns_core/lib/pns/check.ex`, and
`packages/pns_core/lib/mix/tasks/pns.check.ex` — not assumed from the ADR summary alone. File and
line references are given so the next reader can re-check rather than take it on faith.

## Where this sits

`module-boundary-check` runs first and answers a different question: whether this fact should go
through PNS's event/handler mechanism at all, and if so, whether it additionally needs `process`/
`instance`/`stage` (Criterion A) or a `trace` promise (Criterion B). This skill starts **after** that
is already "yes" — it does not re-run the litmus test, and if the answer is genuinely unclear, that
question belongs there, not here.

`contract-distillation` runs earlier still, before any contract exists, turning workshop material
into candidate events, payload shapes and identity/instance judgments. This skill consumes that
distillation's output (or an already-confirmed process detail) — it does not invent event candidates
of its own.

`change-contract` picks up once the event already exists and has a log behind it: renaming it,
widening or narrowing its payload, changing its `identity`/`instance`, editing a `trace` that names
it. None of that is this skill's job — adding a brand-new event is additive by construction (nothing
historical could disagree with a declaration nothing yet named), which is exactly the row
`change-contract`'s own delta table marks as the safe case. If what's being written is a *change* to
an existing declaration rather than a wholly new one, stop and use that skill instead.

`write-handler` (parallel, not yet in this repository) picks up once the event is declared: the
`use PNS.Handler` module that reacts to it. This skill stops at the contract declaration.

## First: is it actually an event, in the past tense sense, or a command?

`docs/adr/design-rationale.md`'s vocabulary table draws the line this DSL is built around:

> **Event** — A fact that already happened. Past tense, immutable, any number of subscribers.
> **Command** — An intention. Exactly one handler, and it can be rejected.
> (`docs/adr/design-rationale.md:24-25`)

`docs/adr/technology-notes.md`'s skills table names exactly this as the thing no compile check can
catch for this skill: *"Past tense means a fact; if it has one handler and the publisher wants a
result, it is a command"* (`docs/adr/technology-notes.md:696`). The DSL has no way to express "and
tell me whether it was rejected" — `event` has no return value, any number of handlers may react, and
none of them can refuse it. If what's being modelled is "ask the system to do X, and X can fail," that
is a command (a plain function returning `{:error, reason} | [events]`, per the design-rationale's
own architecture), and the events it decides to emit — after it succeeds — are what go through this
skill, not the request itself.

The test: **does anything besides the publisher care that this happened, and can the publisher's own
correctness continue without knowing the outcome?** If only one module reacts and the caller needs to
know whether that reaction succeeded before proceeding, it's a command wearing a past-tense name —
this is the same distinction `module-boundary-check`'s Question 1a draws for the non-event case, applied
here to something that already cleared Question 1.

## The `event` macro, key by key — verified against `packages/pns_core/lib/pns/contract.ex`

The full key set, from `@schema.event` (`contract.ex:18-22`):

| Key | Required? | Omitted means | What reads it |
| --- | --- | --- | --- |
| `label` | **yes** | — (raises `ArgumentError` if missing, `contract.ex:203`) | the client-facing report — written in the client's language, the one place that's true |
| `owner` | no | `nil` | `mix pns.check`'s `check_owners_exist/1` — an `info` line, **grouped by module**, only when the module doesn't exist (`pns.check.ex:143-158`) |
| `payload` | no | `%{}` | `PNS.Payload`, four compile gates, the retention check |
| `retain` | no | `%{}` | `PNS.Emitter`, applied once before anything else reaches the log/handlers/job args |
| `depends_on` | no | `nil` | compile gate (must name a declared `external`) plus `PNS.Trace`'s `:suspended` verdict |
| `identity` | no | `nil` | `PNS.Job`'s idempotency key; compile-refused on an async handler without it |
| `process` | no | `nil` | `PNS.Instance`, `PNS.Graph`, `PNS.Check` — one key, so an event belongs to at most one process, by construction, not by check |
| `stage` | no | `nil` | backward-edge detection in `PNS.Check` |
| `terminal` | no | `false` | `mix pns.check`, `PNS.Graph` — a run that ended badly still ended |

This is the complete, current set — confirmed against the source, not the earlier version of this
list that seeded this task (which was correct in this case, but treat that as luck, not a guarantee,
next time the schema changes). An unknown key raises at compile time (`validate_keys!/3`,
`contract.ex:369-374`): `docs/contract.md`'s "What refuses to compile" table lists this as "the
vocabulary is fixed; a new word is a design decision, not a convenience." If a fact genuinely needs a
concept none of the above cover, that is exactly the situation `module-boundary-check`'s and
`contract-distillation`'s non-negotiables both name: flag it, do not invent DSL vocabulary to paper
over it.

## Payload: pick from the closed type set, deliberately

`PNS.Contract.payload_types/0` is `[:id, :string, :integer, :timestamp, :enum]` (`contract.ex:71`).
Closed on purpose — "a type that names a thing an accountant recognises is this library knowing one
client's domain" (`docs/contract.md:165-167`) — and an out-of-set type is compile-refused
(`validate_payload_types!/2`, `contract.ex:727-742`).

Two working conventions to know before writing a field, neither of which the compiler enforces:

- **Money has no dedicated type.** `PLAN.md:381-401` records the working convention directly: minor
  units (grosze/cents) as `:integer`, every such field's name ending in `_minor`. This is a **naming
  convention, not a guarantee** — `PLAN.md:392-394` says so explicitly, and nothing stops a second
  contract writing whole units into a field that looks the same shape. If a decimal type is ever
  added, `PLAN.md:396-401` is emphatic it must be `:decimal` (a shape — an exact decimal, not a float),
  never `:money` (a thing an accountant recognises, repeating the exact mistake that got `:period`
  removed from this same set on 6 August). Do not add either on your own judgment inside this skill —
  that's a DSL-vocabulary decision, out of scope here.
- **An attribute that only sometimes applies cannot be a nullable field.** `PLAN.md:409-413` — the
  "DEC-05" finding — states this as a recorded gap, not a workaround: a declared payload field must be
  present on every emission (a missing declared field refuses the emission, `docs/contract.md:177-179`),
  so "sometimes present" needs its own event, not `field: :type` plus hoping callers omit it
  gracefully. If the material describes a fact that applies to some occurrences and not others, that's
  two events, or an open gap to flag — not one event with an optional-feeling field.

When a field's type doesn't fit any of the five cleanly, `contract-distillation`'s own instruction is
the right move: mark it "does not fit the set cleanly" and flag it, rather than forcing `:id` or
`:string` onto it silently.

## `identity`: when it's required, when it's optional-but-consequential

**Required, compile-enforced, but only for one specific case:** an asynchronous handler on an event
with no `identity` does not compile. The exact message, from `packages/pns_core/lib/pns/handler.ex:49-56`:

> "an asynchronous handler requires event `:name` to declare `identity:` in the contract. Oban gives
> at-least-once, so this event will arrive a second time, and the question 'what makes two occurrences
> the same fact' is one for the process owner, not for the handler."

If nothing async ever handles this event, `identity` stays optional and the common case — an event
with no `identity` at all — is correct, not incomplete (`check.ex:103-107`). Do not add `identity`
reflexively; add it when either an async handler needs it, or the process owner has actually
distinguished "the same fact reported twice" from "two different facts" (the question
`contract-distillation` asks explicitly).

**When you do give it one, get the fields right relative to the process's `instance` — this is a
modelling decision `mix pns.check` only warns about, never refuses:**

- `identity` narrower than or unrelated to `instance` (missing run fields) is flagged by
  `PNS.Check.facts_not_keyed_by_their_run/1` (`check.ex:172-214`): the async idempotency key then
  collides across *different* runs, and a real fact silently never gets its handler run a second time
  — "the log still shows both events" but "the second... never runs." Usually fixed by adding the
  run's own fields into `identity`, since they're already required in `payload` by another gate.
- `identity` **strictly finer** than `instance` (a fact repeats per run — settlement line items within
  a month, visits within a case) is a genuine, sometimes-correct modelling choice, but it changes how
  any `trace` anchored on this event is evaluated: since 21 August 2026, `PNS.Trace.evaluate/3`
  quantifies per distinct `identity` value within the run rather than producing one verdict for the
  whole run (`packages/pns_core/lib/pns/check.ex:67-99`, and `PLAN.md`'s 21 August dopisek on
  `PNS.Check.assertions_finer_than_their_run/1`). One sentence is enough here — the mechanics belong to
  that check's moduledoc and to `PLAN.md`, not to a re-explanation in this skill. If a `trace` will
  ever anchor on this event, know before writing `identity` that it decides whether the promise is
  "once per run" or "once per item."

## `owner`: informational only

`owner:` is read in exactly one place, `mix pns.check`'s `check_owners_exist/1`
(`packages/pns_core/lib/mix/tasks/pns.check.ex:143-158`), and only produces a finding — an `info` line,
grouped by module — when the named module *doesn't exist yet*. That's a normal mid-rollout state, the
same as a declared event with no handler. Nothing enforces that the owner module is correct, actually
handles the event, or has any relationship to it beyond the name. Set it to the module that will (or
does) own this fact; don't skip it, but don't over-invest in it either.

## Event names: literal atoms, from the workshop, never invented

**Names are literal atoms, never constructed dynamically.** `CLAUDE.md`'s rule: *"Nazwy zdarzeń to
literały. Publikacja dynamiczna jest nielegalna, bo od tego zależy, czy graf statyczny jest faktem,
czy heurystyką"* — dynamic publication is illegal because the static graph's entire value is being a
fact recoverable from the compiled code, not a heuristic inferred from what happened to run. `event
name, opts` takes `name` as an atom literal in every existing contract; do not build one with
interpolation, `String.to_atom/1`, or a variable sourced from payload data.

**Names come from the workshop, not imagination.** `CLAUDE.md:142-143` names the concrete source used
for TaxVision: `~/Projects/ai/taxvision-process-native/workshop_output/02-event-storming.md`. The
existing exemplar states this as a moduledoc convention worth copying —
`lib/taxvision/contracts/accounting_month.ex:3-5`: *"Every event name comes from the workshop; none is
invented. Source: `workshop_output/02-event-storming.md`, section 3.1..."* If no workshop material
exists yet for the fact being added, that's `contract-distillation`'s territory — it distills raw
material into named event candidates before this skill has anything to write from. Do not invent a
plausible-sounding name to keep moving; an unconfirmed name is exactly the kind of guess
`contract-distillation`'s non-negotiables forbid without a citation or an explicit `unverified` mark.

## Non-negotiables

- **Event names are literal atoms.** No interpolation, no `String.to_atom/1`, no name built from
  payload data (`CLAUDE.md`).
- **Payload types come from the closed five, never a sixth invented for this occasion.** If none fit,
  flag it — do not force a bad fit or add a word to the DSL from inside this skill.
- **Never fold "there's no key for this" into an existing key's meaning** — the same rule
  `change-contract` and `module-boundary-check` already carry. A missing category is a vocabulary
  decision, not a formatting choice.
- **Never write into `~/Projects/ai/empowered-house-context`.**
- **Code identifiers, moduledocs, comments and error text are English; `label` and the other
  client-facing strings stay in the client's language** — `CLAUDE.md`'s scope note, which explicitly
  includes contract files under `lib/taxvision/`, `lib/rehmed/`, and `test/`.

## Procedure

1. **Confirm this clears `module-boundary-check` already** — if that hasn't run, or its answer to
   Question 1 wasn't "yes," stop and go there first.
2. **Apply the past-tense/command test above.** If the answer is "one handler, and the caller needs
   the result," this is not an event — go write a decision function instead, and stop here.
3. **Get the name from confirmed source material** — a workshop transcript, a reviewed
   `contract-distillation` output, or direct process-owner confirmation. Cite the source the way
   `accounting_month.ex`'s moduledoc does. If there is none, stop and get it via `contract-distillation`
   rather than guessing a `snake_case` name that sounds right.
4. **Draft the payload** as field → type from the closed five. Apply the `_minor` convention to any
   money field; if a field only sometimes applies, treat that as a second event, not an optional-feeling
   field (DEC-05).
5. **Decide `identity`:** only if an async handler needs deduplication, or the process owner has stated
   a rule for "same fact twice" vs. "two facts." If given, check it against the process's `instance` —
   missing run fields is a `facts_not_keyed_by_their_run` finding waiting to happen; strictly finer
   fields change how any future `trace` on this event is evaluated (see above).
6. **Decide `process`/`stage`/`terminal`** exactly as `module-boundary-check`'s Criterion A already
   settled — don't re-derive whether this event needs them, just fill in what was already decided
   there.
7. **Set `owner`** to the module that will handle this, even if that module doesn't exist yet.
8. **Write the declaration**, following the shape of an existing sibling event in the same contract
   (or `lib/taxvision/contracts/accounting_month.ex` if there is no sibling yet) rather than a novel
   layout.
9. **Compile it**: `mix compile --warnings-as-errors` (from the repo root, or `cd packages/pns_core`
   for the engine's own suite) surfaces every one of the key/type/membership gates in
   `docs/contract.md`'s "What refuses to compile" table for free — read what it says rather than
   guessing at the cause.
10. **Run `mix pns.check`** and read any new `info`/`warning` line naming this event by name — an owner
    that doesn't exist yet, or a `facts_not_keyed_by_their_run`/`assertions_finer_than_their_run`
    finding if `identity` was set.
11. **Run the full gate (`mix check`)** last, as confirmation for the whole change, not only the
    declaration.

## What this does not do

Does not decide whether the fact belongs in PNS at all, or whether it needs `process`/`instance` or a
`trace` — that triage already happened in `module-boundary-check` before this skill runs. Does not
write the handler that reacts to the event — that is the sibling skill `write-handler`, being written
in parallel and not yet in this repository; this skill stops at a compiling contract declaration. Does
not carry the impact-analysis burden of changing a field, `identity`, `instance`, or a `trace` on an
event that already has real historical data behind it — a brand-new event is additive and safe by
construction (nothing existing could disagree with a name nothing yet used), and the moment the task
becomes "edit a declaration that already has a log behind it," that is `change-contract`'s delta table,
not this one.
