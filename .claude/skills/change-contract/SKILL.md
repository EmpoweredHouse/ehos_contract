---
name: change-contract
description: DRAFT, not yet reviewed. Before editing an EhOsContract.Contract module that already has declared events, processes, or trace assertions — adding, renaming, or removing a declaration, or changing identity, instance, retain, a payload type, or a trace's from/eventually/or_else/within — classify what the change actually risks before touching code: a compile gate that catches it for free, a change EhOsContract.Deployment's own diff mechanism cannot see at all, a retroactive reinterpretation of history, or a redaction that quietly stops applying. Produces a written impact analysis and the smallest edit that satisfies it, not a full regeneration of the file. Use when modifying a contract that already has declarations; not when writing the first version of a contract (see contract-distillation) or deciding whether something belongs in EhOsContract at all (see module-boundary-check, which explicitly hands off here for that case).
---

# Changing a contract that already exists

DRAFT — not yet run against a real contract change. Review before trusting it. Every claim below
about what compiles, what `EhOsContract.Deployment.diff/2` tracks, and what `retain`/`identity`/`instance`
actually do at runtime was checked against this package's source on 21 August 2026, not assumed —
file and line references are given so the next reader can re-check rather than take it on faith.

## Where this sits, and why it is the one skill that runs before the code

`module-boundary-check` decides whether a new thing should be an EhOsContract event at all, and says outright
that editing an already-declared contract "has its own workflow" — this is that workflow.
`contract-distillation` produces the input for a contract that does not exist yet. Both stop before
the one question this skill exists to answer: **an existing contract already has a log behind it,
and a log cannot be edited — only added to.**

`mix check` enforces a real list of compile-time refusals (below), and enforcing them after the
edit is exactly what a linter is for. What no lint can enforce is *doing the impact analysis before
the edit*, because by the time the compiler runs, the file already says whatever it says. That
ordering — think, then write — is the entire reason this skill exists rather than a paragraph in
`packages/eh_os_contract/docs/contract.md`.

## The compile gate already covers one whole category — do not re-derive it

`packages/eh_os_contract/docs/contract.md`'s ["What refuses to compile"](../../../packages/eh_os_contract/docs/contract.md) table is the complete,
tested list (`test/compile_gates_test.exs`, in the package). An unknown key, a payload type outside
`EhOsContract.Contract.payload_types/0`, a `trace` naming an event that does not exist, a handler on an
undeclared event, an async handler on an event without `identity` — all of these fail loudly at
`mix compile --warnings-as-errors`, before this skill's judgement is even needed. Run the compiler;
do not spend the impact analysis below on anything from that table.

This skill is for what is left once the compiler is satisfied: changes that compile cleanly and are
still not safe.

## Delta classification: what each kind of change actually risks

The compiler is not the only thing that is supposed to know a contract changed — `EhOsContract.Contract.version/0`
hashes every declaration, and `EhOsContract.Deployment` records that hash per deploy. But `EhOsContract.Deployment.diff/2`
(`lib/eh_os_contract/deployment.ex`) only ever computes `events_added`, `events_removed`, `paths_added`,
`paths_removed` from event names and `publishes:` edges — checked directly in the source, not
assumed. **Everything else that changes the hash — a trace's own timing, `retain`, `identity`,
`instance`, a payload type, `owner`, a label — bumps `contract_version` with zero diff support.**
That gap is what this table exists to cover by hand.

| Change | Compiles? | `EhOsContract.Deployment.diff/2` sees it? | The actual risk |
| --- | --- | --- | --- |
| `label`, `example`'s prose, `source:` | yes | no | None functional — these are read by a person, not a mechanism. A bumped `contract_version` from a pure wording edit is not a red flag by itself. |
| `owner:` | yes | no | None functional today — only an `info` line in `mix eh_os_contract.check`, grouped by module. |
| Adding a new event, process, or trace | yes | events_added, yes | Additive and safe by construction — nothing historical referenced it, so nothing historical can disagree with it. |
| Removing an event still named by a handler or a `trace` | **refused** | n/a | Caught for you — "handler on an event the contract does not declare" / "trace naming an event that does not exist." |
| Removing an event nothing else names | yes | events_removed, yes | The one removal case the diff tooling actually tracks well. Old rows stay in the log under their old `contract_version`, read defensively (nothing re-validates on read). |
| **Renaming an event** (remove old name, add new, same commit) | yes, once every handler's `event:` and every `trace` reference is updated to match — compile-refused otherwise | shows as one `events_removed` + one unrelated `events_added`, never "renamed" | A queued job resolves its handler module fine, then reads `meta.event` **fresh from the handler's current compiled metadata**, not from what was true when the job was enqueued (`lib/eh_os_contract/job.ex:63`, `meta.event`). A job enqueued before the rename but run after it casts its old payload against the **new** event's schema, silently, if the handler was already recompiled to point at the new name. Deploy the handler-side rename and let every already-queued job for it drain first, or accept the mismatch window. |
| Adding a **required** field to an existing event's `payload` | yes — a call site is a function call, not statically checked against the schema | no | Breaks **every existing `EhOsContract.emit!`/`emit`** call site for that event **at runtime**, the first time it runs, because `EhOsContract.Payload.validate!/4` refuses a declared field that is missing. `mix check`'s test suite catches it only if a test actually exercises that call site. `grep -rn ":event_name" lib/` for every emit call before relying on this. |
| Removing a `payload` field | yes, and a call site still supplying that key keeps working — an undeclared extra key is accepted, not refused (confirmed: `EhOsContract.Payload.validate!/4`, and pinned by `test/payload_test.exs`) | no | **If the removed field had `retain: :hash` or `retain: :drop`, removing its declaration does not stop it reaching the log unredacted.** `apply_retain/2` only ever walks `event_def.retain` (`lib/eh_os_contract/emitter.ex:504-513`) — a field no longer named there is not touched, however sensitive the value, as long as some call site still passes it. Grep call sites *before* removing a retained field's declaration, not after. |
| Changing a `payload` field's type | yes, if the new type is still in the closed set | no | Changes what `validate!/4` accepts on **new** emissions only; old rows keep their old encoding and are never re-validated on read. Re-check any `rule`'s `given`/`example` written against the old type — nothing forces them to still make sense. |
| Changing `identity:` on an event | yes, as long as the fields still exist in `payload` | no | Changes the **future** shape of the async idempotency key (`EhOsContract.Job.idempotency_key/3`) and of anything else keyed by identity going forward. Never touches history. Before assuming this is free, check whether the affected table actually holds data that would collide under the old *or* the new key — a `psql` count, not a guess. `PLAN.md`'s 21 August closure of the `%7C`/`%3A` escaping defect is the worked example of that check, including what "the database turned out to be empty" is worth as evidence. |
| Changing `instance:` on a process | yes | no | **The highest blast radius in this table.** `instance_id` is computed once, at emit time, and stored on the row (`EhOsContract.Instance.key/3`) — it is never recomputed. Changing `instance:` only affects events emitted *after* the change; every existing row keeps the run identity it was given under the old definition. A `trace` evaluation or a report spanning the change is silently reading two different keying schemes as if they were one. Same "check the real data first" discipline as `identity:`, and for the same reason — this is a run-identity change, not a cosmetic one. |
| Changing a `trace`'s `from`, `eventually`, `or_else`, or `within` | yes, as long as the named events still exist | **no — not even partially.** `diff/2` has no field for it | `EhOsContract.Trace.evaluate/3` (`lib/eh_os_contract/trace.ex`) always reads `contract.traces()` **as compiled right now** — there is no versioned, historical snapshot of what a trace promised at any earlier date. The moment this deploys, every past run matching that trace name is reinterpreted under the new definition, and nothing in the log or the deployment table distinguishes a verdict computed under the old promise from one computed under the new one. A report spanning the change is not wrong exactly — it is answering a question that changed meaning partway through the period it covers. Bound it with `since:` at or after the deploy, or say plainly that the comparison does not hold. |
| Adding or removing `external:` / `depends_on:` | yes, unless `depends_on` names an undeclared `external` (refused) | no | Changes which outage can produce `:suspended` for which assertion. Low risk on its own; re-read whether the dependency choice still matches "the ones declared by the events that did not arrive" (`EhOsContract.Trace` moduledoc) if it is being narrowed or widened. |

## Non-negotiables

- **Work from an actual diff, not from memory or a full rewrite.** State the change as "this
  declaration, this key, old value → new value." Regenerating the whole module risks silently
  dropping an existing `unverified:`, a `source:`, or a comment recording a dated decision — this
  repository has several, and losing one is how a resolved question quietly reopens.
- **Never fold "there's no key for this" into an existing key's meaning.** A category the DSL has
  no word for is a vocabulary decision, not a formatting choice — same rule `module-boundary-check`
  and `contract-distillation` already carry.
- **Grep every emit call site for the event before touching its `payload`, `identity`, or a
  required field** — the compile gate does not check a call site against the schema, only the
  declaration against itself.
- **For `identity:` or `instance:` changes, check real data before assuming the change is free.**
  A row count against the actual table, not an assumption either way.
- **Never write into `~/Projects/ai/empowered-house-context`.**

## Procedure

1. State the change as a diff against the currently committed declaration — not a description of
   the desired end state, the actual before/after of the specific key.
2. Run `mix compile --warnings-as-errors` first. Anything the compile gate refuses is answered;
   stop reading this skill for that part of the change.
3. For everything that compiled, classify each changed key against the table above.
4. For anything in the "no" column of `EhOsContract.Deployment.diff/2`: write the consequence down,
   explicitly, in the commit message — this repository's own convention for a decision that would
   otherwise only live in someone's head (see any "Dopisek" entry in `PLAN.md` for the shape of
   that note: what changed, why, what it costs).
5. For `identity:` or `instance:` specifically: run the real-data check before writing a word about
   cost — `docker compose exec -T postgres psql -U eh_os -d eh_os_contract_host_dev -c "select count(*) from
   eh_os_contract_events;"` (and the `_test` database too) is cheaper than the conversation about whether a
   migration is needed, and is exactly what closed the `%7C`/`%3A` defect on 21 August.
6. For a new required `payload` field, a removed field with a `retain` policy, or a changed type:
   grep every call site (`EhOsContract.emit!`, `emit`) for that event across `lib/`, and update them in the
   same change — do not leave this for the test suite to discover by accident.
7. For a `trace` timing/routing change: note the deploy boundary in the same commit message, so
   whoever later runs a report across it knows to bound it with `since:`.
8. Make the smallest edit that satisfies steps 3–7 — the existing file, in place, not a
   regenerated module. A diff a reviewer can read with attention is the functional requirement
   `CLAUDE.md` names for anything a human has to review.
9. Run the full gate (`mix check`) last, as confirmation — not as a substitute for steps 3–7, since
   everything in the "no" column above will pass it silently by construction.

## What this does not do

Does not replace `mix eh_os_contract.check`'s compile-time gates for what they already catch — read those
messages, do not re-derive them here. Does not decide whether a change is the *right* modelling
call — whether `instance` should really be keyed differently, whether a promise is actually owed —
that belongs to whoever confirmed the process, the same authority `contract-distillation` defers
to. Does not build a versioned history for `trace` semantics, which the table above shows does not
exist; recording that gap accurately is this skill's job, closing it is a `PLAN.md` item if it ever
becomes one.
