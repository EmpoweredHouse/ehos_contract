---
name: contract-distillation
description: Distill process-mapping workshop material (raw transcripts, board exports, or a reviewed process-extraction output) into what a domain and its contracts need — contexts and their glossary, actors, subjects of personal data, values, external systems; and per process the facts that something depends on (with the rejected candidates), who decides or records each, the invariants and their refused cases, the run and its stages, terminal states, reactions, what people read, promises, deadline, cadence and scenarios — each with its source or marked unverified. Produces a document, not code. Use any time after workshop material exists, independent of when the contract is written, which can be weeks later and by someone else.
---

# Contract distillation

Checked on 30 September 2026 (plan E11e).
The categories are the two DSLs' (`packages/eh_os_contract/docs/dsl/domain-dsl.md` and
`contract-dsl.md`, generated from the code and kept current by the gate). Not yet run on a real
engagement in this form: review its output before trusting it.

## Where this sits, and where it does not

`appunite/process-native-software` owns the validated Process Mapping methodology — its
`Service Delivery/Process-Mapping-Playbook.md` and the `process-extraction` skill, which turn
workshop material into a business-process map. **This skill does not compete with that.** It
re-reads the same material, or preferably `process-extraction`'s reviewed output, through a narrower
lens: what a domain and its contracts need before anyone can write them. It produces neither a process map nor Elixir, but a
document whoever writes the contract later starts from instead of eight hours of transcript.
Nothing is written into `process-native-software` from here without asking first.

## The domain comes first

Contexts, actors, invariants, read models and the relations between contexts are all in workshop
material — the mapping of 25 September found almost all of them in both clients'
(`PLAN.md`, "Dopisek 25 września") — and the domain and the contract have a word for each. A
distillation that skips them leaves the contract's author to mine the transcript again. So distill
the domain once per client, then each process against it.

The vocabulary is closed and domain-neutral. Projecting material onto it is what makes the skill
reusable across clients. If a category needs a client's word to make sense, that word does not
belong in the vocabulary: flag it, do not add it.

## Non-negotiables

- **Never invent** stakeholders, systems, integrations, steps, event names or numbers.
- **Every number and rule carries a source or is marked `unverified`**: a transcript timestamp, a
  speaker, a board reference, or "not stated". The contract will carry the same as `source:` and
  `unverified: true`. A `source:` is an identifier of the material — "W2 00:14:10", "P-07", "03
  §4.2" — never a person's name: it goes into the model sent to EHOS and onto the published pages,
  and nothing checks it for personal data (EP1 review). The same holds for a scenario's description,
  which a generated callback's doc now carries too (EP3 review): it names a case, never a real person.
- **The client's words for names and labels**, with a proposed technical name beside them, so the
  contract's `label` and `source:` trace back to what was said.
- **Contradictions are kept**, tagged by speaker, never resolved silently.
- **This is an input, not a source of truth.** Nothing goes to a client or into a contract without a
  person reviewing it.
- **Never write into `~/Projects/ai/empowered-house-context` or `appunite/process-native-software`**
  without being asked.

## Inputs

In order of preference: a reviewed `process-extraction` output (already deduplicated and checked by
a person); raw material — transcripts (usually several files; check their order, do not assume it),
board and whiteboard photos, an event-storming export, notes. State which the run used: the
confidence of everything downstream depends on it.

## The domain, once per client

1. **Subdomains and contexts.** The parts of the business (`:core`, `:supporting`, `:generic`) and
   the contexts they split into, in the client's words. For each context, its **glossary**: terms
   with the definition people gave, words they said to avoid, translations if the team works in two
   languages.
2. **Relations between contexts.** Who depends on whom, and how: one conforming to another, one
   translating, two going separate ways. Only where the material says so.
3. **Actors.** The roles that act (`:human`) and the systems that act on their own (`:system`,
   backed by an external). Which context each belongs to.
4. **Subjects of personal data.** The kinds of person whose data may have to be erased — a patient,
   an employee — and which identifier names one.
5. **Values.** Business quantities and codes that are not plain shapes: money and its unit, a
   period and its format, a tax number. For each, what makes a value invalid, with an example that
   is and one that is not.
6. **External systems**, named as a business fact ("the payer's eligibility system"), never by
   vendor: whether the application only sends to it, only receives, or both; what "unavailable"
   looks like, as a full sentence in the client's words; and whether "no answer" is the same as
   "answered no" (it almost never is). And what the application asks of it, where the material
   names it — "accept a medical event report", "give the company's VAT status" — one operation
   each, with its source (plan EP5a): once a system has operations, every effect that calls it
   says which one.

## Each process

1. **Facts, and the candidates that are not.** Every candidate is a past-tense fact in the client's
   words. Then reject most of them, recording why:

   > **Does anything outside this document depend on it having happened?**

   A rule refuses something after it, a reaction takes it, an actor waits for it, a promise runs from
   it, it ends the run. If nothing does, it is **a field being filled in**, not a fact. The trap is
   reading this as "is it stored in a field": ICD codes are a field, yet may still be a precondition
   someone enforces. Ask about the dependency, not the storage.

   This exists because a real run got it wrong by a factor of three: the Rehmed distillation
   produced 22 candidates, the contract needed 7, and six of the fifteen removed were edits to one
   document that survived into a compiled contract, a diagram and a client-facing PDF before someone
   who knew the domain said *that is a field the specialist fills in*. Big Picture Event Storming
   produces a sticky for everything that happens; carrying the board across without this filter is
   this skill's default failure.
2. **Decided or recorded.** For each fact: who asks for it (the command, and which actor may issue
   it), and can the asking be refused? Or is it simply observed — noted by a person, answered by a
   system? A fact nobody asks for and nobody observes cannot occur.
3. **What must stay true.** The rules under which the asking is refused (invariants), each in the
   client's sentence, and **a case where it was refused**, with real data. Whether a rule is about
   one thing (a visit, a month) or across several (every visit of a payer in a period) — the second
   is a consistency boundary over many facts. Rules on a command's own data (an amount is positive)
   are constraints of that command.
4. **Fields.** For each fact and each command, what someone would need to know a year from now
   (not what is in a database), and the closest type: identifier, typed text, number, decimal, yes/no,
   date, point in time, one of a set, a list, or a domain value. Mark which fields are personal data,
   and whose. Say "does not fit" rather than force a type.
5. **The run.** What is one case, from start to end (the correlation). Can two run in parallel for
   the same actor, and what tells them apart? Which facts repeat within one case, and what
   distinguishes the second from the first?
6. **Terminal states.** Every way a case ends, bad endings included: abandoned, refused, cancelled.
7. **Stages and gates — the load-bearing category.** What must happen before what is even possible,
   as distinct from what usually comes first. Do not infer a strict sequence the material does not
   support. A process whose facts are fired by people at screens, in an order that matters, with no
   promise about how fast, is the **normal** case, and fully verifiable through its stages, terminal
   states and declared paths: the report shows paths never taken and facts that happened outside the
   declared ones, with no clock. For each process record which orderings are claimed, which are
   merely typical, and which a reader would expect to see taken.
8. **Reactions.** Every "whenever X, then Y" (an automatic step), every "tell / send / ask system
   S", every "if Y has not happened N after X, chase it". Say whether the reaction must happen
   together with X or may follow it — it decides what a failure leaves behind.
9. **What people read.** The lists and totals someone looks at, who looks, and narrowed to what
   (their clinic, their clients).
10. **Promises — the timed ones, where they exist.** *After fact A, within N, fact B follows, or else
    fact C.* This needs a commitment to someone (a patient, a payer, a regulator) **and** a number
    somebody stated. N in real units, never "quickly". Does the time bind the fallback too? Usually
    unstated: flag it. **Zero promises is a finding about the domain, not a verdict on the process.**
    A promise anchored backwards from a scheduled moment (a reminder before an appointment) is not a
    promise, which runs forward from an observed fact; it is a timer, or the client's own scheduling.
11. **Deadline and cadence.** A bound on the whole case, and whether the process recurs on a
    schedule or starts only when triggered. Do not force a cadence onto an event-driven process.
12. **Who answers for it.** The role accountable when a promise breaks or a path is never taken.
13. **Scenarios.** For each rule and each reaction, a case from the material: given what had
    happened, when this was asked (or this fact arrived), then what followed — or which rule refused
    it. Real numbers, a case that went wrong in real life before an invented edge case. These become
    the contract's scenarios, and every invariant needs its refused case.

    *Worth not losing, not yet acted on:* classic Event Storming has a sticky colour for a business
    rule. If a live session used it, rules would arrive as artifacts instead of being mined from
    prose. That is a change to the live methodology (`process-extraction`'s), not to this skill —
    flag it to whoever facilitates the next session.
14. **Source and unverified**, restated per process: which claims have a citation, which are the
    team's placeholders.

## Output

A Markdown document following [output-template.md](output-template.md): the domain first, then one
section per process. Save it under this repository's `docs/`, named for the client and date
as `docs/rehmed-2026-08-18-distillation.md` is, and say where; not in `process-native-software`'s
`output/`, which is that repository's pipeline.

## Quality check before finishing

- every category has an entry or an explicit "not addressed in this material" — silence is not "no"
- no invented names, fields, systems or numbers
- the rejected candidates are listed, with what they failed on
- every rule has a refused case, every promise says what it binds and whether the fallback shares
  its time
- every number has a source or is marked unverified
- contradictions between speakers are preserved
- the input used is stated at the top

## Not this skill

Writing the domain or the contract — a later, person-led step, from this document and the client's
confirmation of everything marked unverified (then `module-boundary-check`, `add-event`,
`write-decider`, `write-reaction`). Replacing `process-extraction`'s map, or
`docs/warsztat-rehmed.md`'s prepared questions for a live session: this runs afterwards, on material
that exists.
