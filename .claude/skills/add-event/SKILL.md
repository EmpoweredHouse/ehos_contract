---
name: add-event
description: After `module-boundary-check` has decided a fact belongs in a contract — never to decide that question itself — declare a brand-new `event` in its unit: confirm it is a fact a command decides or an actor records (A2), name it from the workshop material, pick field types from the built-in set or the domain's values, keep correlation fields required and non-personal, mark personal data with `personal:` and `subject:`, place it in a stage, and give it the scenario and the reader that stop it being noise. Use when about to write a new `event :name, "label"` in a new or an existing contract. Not for changing an event that already has history in the log (see `change-contract`), and not for the code that emits it or reacts to it (see `write-decider` and `write-reaction`).
---

# Adding an event to a contract

Checked on 30 September 2026 (plan E11e) against
`packages/eh_os_contract/docs/contract.md`, `packages/eh_os_contract/docs/dsl/contract-dsl.md` (every key of `event` and
`field`, generated from the code) and `packages/eh_os_contract/docs/rules.md`. Not yet run on a real change: read what it
says against those before trusting it.

## Where this sits

`contract-distillation` turned workshop material into candidates, and `module-boundary-check`
decided this one is a fact the contract holds. This skill writes the declaration. A brand-new event
is additive: no row of the log has its type yet, so nothing historical can disagree with it. The
moment the event has rows — any change to its name, fields, types or `personal:` — it is
`change-contract`'s, because every row is decoded again by today's declaration whenever its
stream is folded.

## First: decided or recorded

Every event of a unit is emitted by at least one of its commands **or** declares `recorded_by:`
(`A2`). There is no third way in: in an event-sourced log, an event nothing can produce never
occurs.

- **Decided** — a command of the same unit lists it in `emits:` (`A1`), and the unit's code chooses
  it with `emit/1`. Ask who issues the command (`by:`) and on which invariant it may refuse. If the
  answer is "nobody asks, it just happens", it is not decided.
- **Recorded** — an observation, or an external system's answer: `recorded_by: :specialist`, or a
  `:system` actor `backed_by:` the external. It enters through `EhOsContract.record/3`, with no
  decision, and `depends_on:` names the external it hangs on.

A request that can be refused is a command, not an event. "Payment requested" that somebody may
turn down is `command :request_payment` with `rejects:`; the event is what it decides.

## Where it goes

Inside the unit that decides or records it, `aggregate` or `dcb`. When the process declares stages,
inside the unit's `stage :name do … end` group (`R3`); the order of stages is the order of `stage`
entries in `process`. An event born in a sibling process is not declared again: it is consumed
(`consumes Sibling, [:event]`) and placed in this run with `include` inside `process` (`R4`).

## The name, and the label

- **From the material, never invented.** `CLAUDE.md` names TaxVision's source,
  `~/Projects/ai/taxvision-process-native/workshop_output/02-event-storming.md`; cite yours in
  `source:` ("03 §4.2", "AG:694"), as the sandbox contracts do — an identifier of the material,
  never a person's name, since it goes into the exported model and the pages. With no material behind it, go back
  to `contract-distillation` rather than keep a plausible `snake_case`.
- **Past tense** — no check reads the tense; **snake_case and unique** among the contract's
  commands, events, timers and consumed events together (`N1`); not a reserved word or a clash
  (`N2`); a literal atom.
- **`event-name-with-aggregate-prefix`** warns when an event's name starts with its unit's:
  `accounting_month_opened` in the unit `accounting_month`. The event keeps the workshop's name; either
  the unit takes another name from the material, or the warning stays, and is true (`PLAN.md`, EL1).
- **The name lasts.** The log stores the type as `"<contract id>.<event>"`, and renaming it later leaves
  every old row of a type the contract no longer declares.
- **The label is the business's sentence**, in the domain's `language:`, written as the process owner
  says it. A word the context's glossary says to `avoid` is a warning (`label-with-avoided-term`).

## Fields

Each field names a shape, never a thing (`packages/eh_os_contract/docs/dsl/contract-aggregate.md`, `aggregate.event.field`):

- Built-in: `:id :string :integer :decimal :boolean :date :timestamp {:enum, [...]} {:list, t}`.
  Anything else is a `value` of the domain (`X3`), and a thing the business recognises — money, a
  period, a NIP — is one: `value :money, :integer, unit: :grosze`, with invariants that dispatch
  holds every value to. Some sandbox fields end in `_minor` instead; a new field uses a value.
- **`:string` is text a person typed.** A code, a number or a choice has a type of its own; a
  `:string` not marked `personal:` gets the `free-text-not-personal` notice, because it stays in the
  log as written after its subject is erased.
- **The unit's identity is injected**: do not declare it again (`F6`).
- **Every `correlate` field of the process is in every local event** (`R2`; the identity counts),
  and is neither `optional:` nor `personal:` (`F4`).
- **Every required, non-personal `:id` field becomes a tag** a boundary can `match:` on — also one
  typed by a domain value whose base type is `:id`. So an `:id` is an opaque identifier; a natural one — a PESEL, a patient's number at a payer — is never an `:id`.
- **Personal data** is `personal: :patient_id`, naming a required, non-personal `:id` field of the
  same event that declares `subject: :patient`, a subject of the domain (`F5`). It is sealed with
  that subject's key and reads back as `%EhOsContract.Erased{}` after erasure.
- **`optional: true` is legal**, except on a field the process correlates on or a boundary matches
  (`F4`); an optional `:id` is simply not a tag. Use it for an
  attribute that is sometimes absent. When the absence is itself a fact something depends on — a
  visit closed without payment — it is a second event, not a `nil`.
- `issued_by: :external` says which system gives the value (`X4`).
- `schema_version` stays 1 on a new event.

## The rest of the declaration

- `terminal: true` when the event ends a run. `deadline-without-terminal-event` notices a process
  with a deadline and no terminal event.
- `depends_on: :external` when the fact waits on a system; an outage then suspends a promise
  instead of breaking it.
- **Someone reads it.** `event-without-consumer` warns of an event nothing takes: no reaction, read
  model, boundary, sibling `consumes` or `publish`, no promise names it, no unit's lifecycle starts or
  moves on it, nor is it `terminal`.
  An event that nothing depends on is usually a field of another event (`contract-distillation`,
  step 1).
- **A scenario shows it.** A decided event: `expect :new_event` in a scenario of the command that
  emits it, with data from a real case (`S5` refuses an `expect` outside the command's `emits:`). A
  recorded event has no command to expect it from: it appears as a `given` in its unit's scenarios,
  or as the `on` trigger of a reaction's scenario, and a test records it with
  `EhOsContract.record/3` as an actor in its `recorded_by:`. `S3` refuses data of undeclared fields
  either way.
- **Leaving the application** is a separate declaration, `publish :name, as: "<domain>.<name>.v1",
  from: :event, fields: [...]` — a versioned name with the fields that cross, and no personal ones
  (`D11`), as `Taxvision.Contracts.AccountingMonth` publishes the opened month. Not every event.

## Procedure

1. Confirm `module-boundary-check` answered yes. If not, go there first.
2. Decide decided or recorded. For decided, find or declare the command; for recorded, the actor.
3. Take the name and label from the material, with `source:`.
4. Write the fields: types from the built-in set or domain values, correlation present, personal
   data marked.
5. Place it: its unit, its stage group, `terminal:` if it ends a run.
6. Decided: add it to the command's `emits:` and to a scenario's `expect`. Recorded: use it as a
   scenario's `given` or `on`, and test `EhOsContract.record/3` with an actor from `recorded_by:`.
7. Compile. Every refusal starts with its code; `packages/eh_os_contract/docs/contract.md`, "What will not compile", says
   what each means.
8. Run the gate from `sandbox/` and read any new `check` line naming the event
   (`event-without-consumer`, `free-text-not-personal`, `emits-never-produced` until the code emits
   it).
9. Then `write-decider` for the `emit/1`, and `write-reaction` for whatever takes it.

## Not this skill

Whether the fact belongs in the contract — `module-boundary-check`. An event that already has rows
in the log — `change-contract`. The code that emits it or reacts to it — `write-decider` and
`write-reaction`.
