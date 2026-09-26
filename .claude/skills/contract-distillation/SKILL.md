---
name: contract-distillation
description: DRAFT, not yet reviewed, and describes the v1 DSL only. Distill process-mapping workshop material (raw transcripts, or a reviewed process-extraction output) into the categories an EhOsContract contract needs — event candidates, identity, instance, terminal states, stages, trace promises, cadence, retain/PII, external dependencies, examples, and what is confirmed vs. guessed. Produces a document, not code. Use any time after workshop material exists, independent of when the actual Elixir contract gets written — that can be days or months later.
---

# Contract distillation

> **Describes v1** (26 September 2026, v2 plan E6). This skill was written for v1's
> `EhOsContract.Contract` and `EhOsContract.Handler`. From E6 a contract may be written in the v2 DSL
> (`EhOsContract.Next.Contract`, [`docs/adr/contract-v2.md`](../../../docs/adr/contract-v2.md)), and
> `Rehmed.Contracts.VisitSettlement` is. For a v2 contract the keys, gates and runtime described below do
> not apply. The skill is rewritten at the cut (E11).

DRAFT — not yet run against a real engagement. Review its output before trusting it.

## Where this sits, and where it does not

`appunite/process-native-software` owns the actual, validated Process Mapping methodology —
`Service Delivery/Process-Mapping-Playbook.md` and its skill `process-extraction` are the real,
proven tool for turning Day 1 raw material into a business-process map
(`output/01-processes.md`). **This skill does not compete with that and does not replace it.**

That repo predates this one, and this repo's own founding framing (`README.md`) is explicit that
EhOsContract-the-engine is still a validation prototype, not a finished product. If the engine idea holds
up, `process-native-software` is expected to eventually move under this repository as the wider
methodology EhOsContract-the-engine serves — not the other way around. Until then, the two stay separate,
and nothing gets written into `process-native-software` from here without asking first.

**What this skill adds, distinct from `process-extraction`:** `process-extraction` organizes
material toward business understanding and screens — actors, steps, tools, handoffs, pain
points. This skill re-reads the *same class of material* (or `process-extraction`'s own output,
preferred when it exists, since it is already reviewed) through a different, narrower lens: the
categories an EhOsContract contract needs before it can be written. It produces neither a business process
map nor Elixir code — it produces an intermediate distillation so that whoever eventually sits
down to write the contract (possibly weeks later, possibly a different session) is not starting
from eight hours of raw transcript.

## Why this is domain-neutral by construction

The categories below come from `EhOsContract.Contract`'s DSL vocabulary, not from any client's domain —
that vocabulary is deliberately closed and domain-neutral (see `packages/eh_os_contract/docs/contract.md`,
`docs/adr/technology-notes.md` §1). Projecting workshop material onto a fixed, neutral vocabulary
is what makes this skill reusable across clients without modification. If a category ever needs a
client-specific word to make sense, that is a signal the word does not belong here — flag it, do
not add it silently.

**Before reading `packages/eh_os_contract/docs/contract.md`, verify it is actually current — do not assume it.** The file
is generated from `EhOsContract.Contract.schema/0`, but that guarantee only holds when the compile gate has
run against the commit you're looking at; an uncommitted local change to `packages/eh_os_contract/lib/eh_os_contract/contract.ex`, or
a stale checkout, can leave the checked-in file behind the real vocabulary. Run:

```bash
cd packages/eh_os_contract && mix eh_os_contract.docs --check
```

This exits 0 and prints `docs/contract.md: reference is current` when it is safe to trust. If it
fails instead, the file is stale — run `mix eh_os_contract.docs` there to regenerate it before reading it, and say
so in the output rather than silently working from an unverified copy. Once verified, that file —
not this skill's memory of past runs — is the vocabulary; if the two ever disagree, the file wins.

## Non-negotiables, carried over from this repo's own rules

- **Never invent stakeholders, system names, integrations, steps, event names, or numbers.** Same
  rule `process-extraction` already enforces — inherited here, not reinvented.
- **Every number or rule carries a source or is marked `unverified`** — a transcript timestamp, a
  speaker, a whiteboard/photo reference, or "not stated." No exceptions. This is the same
  discipline that caught TaxVision's 25-day deadline as unconfirmed.
- **Use the client's language for event names**, technical name as a secondary label — the same
  rule `docs/warsztat-rehmed.md` states for a reason: it lets you trace back to what was actually
  said.
- **Do not resolve contradictions silently.** If two speakers described the same thing
  differently, keep both, tagged by speaker.
- **This is an input, not a source of truth.** Nothing here goes to a client or gets copied
  directly into a contract file without a human reviewing it first.
- **Never write into `~/Projects/ai/empowered-house-context` or `appunite/process-native-software`
  without being asked.**

## Inputs

In order of preference:

1. A reviewed `process-extraction` output (`output/01-processes.md` or equivalent), if it exists —
   preferred, because it is already deduplicated and human-checked.
2. Raw workshop material directly: transcript file(s) (a series of files is normal, not one big
   file — do not assume chronological order without checking), whiteboard/Post-it photos, an
   event-storming board export (e.g. from Figma/FigJam), extra notes.

State plainly which of these the run actually used — the confidence of everything downstream
depends on it.

## What to extract, per candidate process

Walk every DSL category below for every process/business object the material describes. Prefer
plain-language distillation using the client's exact wording, tightening into DSL terms only in
the "closest DSL fit" line — do not skip straight to Elixir-shaped nouns before you know they hold up.

1. **Event candidates** — named in the client's words, past tense (a fact that happened), with a
   proposed technical name (`snake_case`) as a secondary label, and which process they belong to.

   **Then reject most of them, and record what each one failed on.** Every candidate must answer:

   > **Does anything outside this document depend on it having happened?**

   A policy reacts to it, another actor waits for it, a deadline runs from it, it ends the process,
   or it is the fallback of a promise. If none of those — it is a **field being filled in**, not a
   fact, and it does not belong in the contract however clearly somebody said it.

   The trap is that the test *sounds* like "is it stored in a field", and that reading is wrong: ICD
   codes are a field and so is a settlement total, yet the codes may still matter as a precondition
   somebody enforces. Ask about the dependency, not about the storage.

   **This exists because a real run got it wrong by a factor of three.** The Rehmed distillation
   produced 22 event candidates; the contract needed 7. Six of the fifteen removed were edits to one
   document — the interview, the note copied from a previous visit, the note left for reception, the
   treatment performed, the ICD codes, the free-text supplement — and each of them survived into a
   compiled contract, a diagram and a client-facing PDF before somebody who knew the domain said
   *that is not an action, it is a field the specialist fills in*.

   The cause is structural and will recur: **Big Picture Event Storming produces a sticky for
   everything that happens**, and its board is the main input here. A contract needs the subset that
   something depends on. Carrying the board across without this filter is the default failure of
   this skill, not an unlucky one.
2. **Payload shape** — for each event, what a person would need to know for this fact to make
   sense a year from now (not "what's in the database"). Classify each field toward the closed
   type set (`packages/eh_os_contract/docs/contract.md`) — identifier, human-typed text, whole number, point in time, one
   of a fixed set — or mark "does not fit the set cleanly" (e.g. money/decimal amounts) rather
   than forcing a bad fit.
3. **Identity** — is there language distinguishing "the same fact reported twice" from "two
   different facts"? If unclear, say so; do not guess a key.
4. **Instance** — what is "one case" from start to end for this process? Could two run in
   parallel for the same actor, and if so, what tells them apart?
5. **Repeated events within one instance** — does the same event type happen more than once per
   case (visits, retries, attempts)? If so, what distinguishes occurrence two from occurrence one?
6. **Terminal states** — every way this process ends, explicitly including bad endings
   (abandonment, rejection, cancellation) — not just the happy one.
7. **Stages / gates — the load-bearing category.** What must happen before what is even possible
   (a gate), as distinct from what merely happens in a typical order. Do not infer a strict linear
   sequence the material does not support.

   **This is where most of the value is, and the earlier version of this skill said the opposite.**
   Three of the four questions the product answers — which declared paths were never traversed,
   which transitions are not declared, which contract version is deployed — are computed from the
   contract and the log with **no clock involved** (`EhOsContract.Conformance`, `EhOsContract.Graph`,
   `EhOsContract.Deployment`); `EhOsContract.Check.backward_edges` checks order by `stage` without touching the log
   at all. Only `trace` needs timing. So a process whose events are fired by people interacting
   with screens, in an order that matters, with no promise about how fast — which is the **normal**
   case, not a deficient one — is fully verification-worthy through `process` + `instance` +
   `stages` + `terminal`. `module-boundary-check` already states this split correctly; this skill
   was out of step with it and with the engine.

   So for every process, extract: which orderings are **claimed** (a gate that must hold), which
   are merely typical, and which declared paths a reader would expect to see traversed. An
   ordering nobody enforces today is exactly what the overlay is for.
8. **Trace candidates — the timed promises, where they exist.** Form: *after `event A`, within
   `N`, `event B` follows, or else `event C`.* Valuable and comparatively rare: it needs a promise
   made to someone (a patient, a payer, a regulator) **and** a number somebody actually stated.
   What is `N`, in real units, not "quickly"? Does the timing bind the fallback path too, or only
   the happy path — this is usually unstated and must be flagged, not assumed either way.

   **Zero trace candidates is a finding about the domain, not a verdict on the process.** Record
   it and move on to the structure. And do not manufacture the missing half: if a promise is
   anchored *backwards* from a scheduled future moment (a reminder before an appointment, a
   warning before an expiry), `trace` cannot express it, because the window runs forwards from an
   observed fact. That is a reminder, and reminders belong to whatever task mechanism the client
   application has — **not a reason to grow the contract a scheduler.**
9. **Cadence** — is this process due on a recurring schedule, or does it start only when
   triggered (no cadence applies)? Do not force a cadence onto an event-driven process.
10. **Retain / sensitive data** — which payload fields are personal or sensitive data (health data
    gets its own flag, distinct from generic PII), and whether a handler needs the raw value or
    only proof that a value existed.
11. **External dependencies** — named as a business fact ("the payer's eligibility system"), not a
    vendor product name. What does "unavailable" look like, in the client's own words, as a full
    sentence — and is "no answer" the same thing as "answered no" (almost never is, and systems
    usually conflate them)?
12. **Rules and examples** — for every "when X then Y" statement, is there a concrete example with
    real numbers, both a case that worked and one that went wrong? A rule without an example is
    prose, not something that can compile later.

    **Idea worth not losing, not yet actioned.** Classic Event Storming already has a dedicated
    sticky-note color for exactly this — a business rule/condition, distinct from the event
    stream. If a live session used one, rule candidates would arrive as first-class artifacts
    instead of being mined out of prose after the fact, the way this step does today. That is a
    change to the live-session methodology, though, not to this async, after-the-fact skill — it
    belongs to `process-extraction`/`process-native-software`'s playbook, and per the
    non-negotiables above nothing gets written into that repo without asking first. Flag it to
    whoever facilitates the next live session; do not invent a sticky-note convention here.
13. **Source / unverified** — restated as its own section per process: which numbers/claims above
    have a citation, and which are the team's own placeholder guesses.

## Output

Produce a Markdown document, one section per process, following
[output-template.md](output-template.md). Do not name or save it into `process-native-software`'s
`output/` folders — that namespace belongs to that repo's own pipeline. Save it under this
repo's `docs/`, named for the client and date (e.g. `docs/rehmed-2026-08-10-distillation.md`), and
say so explicitly when done rather than assuming a path.

## Quality check before finishing

- every category above has an entry or an explicit "not addressed in this material" — silence is
  not the same as "no", and the output must not blur the two
- no invented event names, fields, systems, or numbers
- every trace candidate names what it binds and whether the fallback path shares the same timing
- every number has a source or is marked unverified
- contradictions between speakers are preserved, not resolved
- the input used (process-extraction output vs. raw material) is stated up front

## What this does not do

Does not write the Elixir contract — that is a later, separate, human-led step, using this
distillation plus direct client confirmation on anything marked unverified or unclear. Does not
replace `process-extraction`'s business-process map, and does not replace
`docs/warsztat-rehmed.md`'s prepared, read-aloud questions for a live session — this runs on
material that already exists, asynchronously, not in the room.
