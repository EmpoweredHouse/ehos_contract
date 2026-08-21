---
name: review-pr
description: DRAFT, not yet reviewed. Before approving or sending back a PR generated for this repository — a new event, a new handler, a contract edit, or anything touching lib/pns/, lib/taxvision/, or lib/rehmed/ — separate what `mix check` already guarantees (so review attention does not waste itself re-deriving a compile refusal) from what only a human judgment call can catch: an unexplained `mix pns.check` warning, an invented-looking `rule`/`example`, a silent edit to an existing contract's `identity`/`instance`/`retain`/`trace`, a missing "verified in reverse" claim, Polish text outside the narrow allowed surface, or a diff too large for its stated scope. Use for any PR review in this repo, whether by a human or an agent reviewing on a human's behalf. Does not replace the compiler, `mix check`, or `docs/contract.md`'s compile-gate table — it tells you which parts of those you never need to re-check by hand.
---

# Reviewing a generated PR

DRAFT — not yet run against a real PR review. Review before trusting it. Every claim below about
what `mix check` refuses, what `mix pns.check` only warns or informs about, and what
`PNS.Deployment.diff/2` / `PNS.Trace.evaluate/3` do or do not track was checked against this
package's source (`packages/pns_core/lib/mix/tasks/pns.check.ex`, `docs/contract.md`) on 21 August
2026, not assumed — file and line references are given so the next reader can re-check rather than
take it on faith.

## Where this sits

The other skills in this repository write something: `module-boundary-check` decides whether a new
action needs PNS at all, `contract-distillation` turns workshop material into the categories a
contract needs, `change-contract` classifies the risk of editing a contract that already exists,
and `add-event`/`write-handler` (the two `PLAN.md` Etap 3 names alongside `change-contract`, under
`.claude/skills/add-event/` and `.claude/skills/write-handler/`) produce the actual event
declaration and handler module. All five are for the agent about to write code.

This skill is for the other side of that exchange: the human — or an agent standing in for one —
who receives the PR those skills produced and has to approve it or send it back. `PLAN.md` names it
plainly: *"Notatki §8 wymieniają osiem skilli i wszystkie są dla agenta, który pisze — a bramą jest
recenzent"* (`PLAN.md:1343`) — the eight skills in `docs/adr/technology-notes.md` §8 are all for the
writer; the reviewer is the gate, and had nothing written for it until now. When the PR under review
is a contract edit specifically, this skill does not re-derive risk — it points at
`change-contract`'s delta-classification table (`.claude/skills/change-contract/SKILL.md`, the
`## Delta classification` section) and expects the reviewer to open that table, not re-think it from
scratch.

## Part 1 — what NOT to re-check, because the gate already did

`docker compose up -d && mix ecto.setup && mix check` runs, in this order: `compile --force
--warnings-as-errors`, `pns.check`, `pns.docs --check`, `test`, and — since 21 August —
`mix test` inside `packages/pns_core` as its own separate invocation (`CLAUDE.md`). **If this did
not run green, there is nothing to review yet.** Ask for the real exit code, not a description of
one. Never accept `mix check | tail -4` as evidence: piping to `tail` reports `tail`'s exit code,
which is always zero, and this repository has already committed 24 real failures behind exactly that
green-looking terminal on 6 August (`CLAUDE.md`'s own warning, and the concrete incident it names).
The safe form, if the output has to be shortened, is `out=$(mix check 2>&1); rc=$?; echo "$out" |
tail -4; echo "EXIT=$rc"` — insist on the `EXIT=` line if a shortened log is all that's offered.

Given a genuinely green gate, two categories are already closed and do not deserve review attention:

**1a. Compile-time refusals** — `docs/contract.md`'s ["What refuses to
compile"](../../../docs/contract.md) table, pinned by `test/compile_gates_test.exs`. If the PR
compiled, none of these apply:

| Refused | Why |
| --- | --- |
| An unknown key in any declaration | the vocabulary is fixed |
| A `payload` field with a type outside the closed set (`:id`, `:string`, `:integer`, `:timestamp`, `:enum`) | a type naming a thing rather than a shape is the library knowing one client's domain |
| `rule` without an `example` | a rule without a case is prose |
| `rule` with a capture instead of an MFA tuple | would make the contract depend on the domain at compile time |
| `trace` naming an event that does not exist, or missing `from`/`eventually` | half an assertion has nothing an observed run could satisfy |
| `trace` with a calendar unit in `within`, or spanning two processes | the evaluator cannot compute it / each process has its own run identity |
| `process` without `instance` | nothing about the run could be counted |
| A staged event without `stage`, a `stage` naming an undeclared phase, `stage`/`terminal` without `process`, a `process:` naming a process that does not exist | structural nonsense the compiler already refuses |
| `identity`/`instance`/`retain` naming a field absent from `payload`, or `identity`/`instance` on a `retain: :drop` field | the key could not be computed, or would vanish with the field |
| `depends_on` naming an undeclared `external` | — |
| The same event declared twice, a handler on an undeclared event, a handler publishing an undeclared event, an async handler on an event without `identity` | — |

**1b. `mix pns.check`'s own `:error` findings** — not a macro-time refusal, but a whole-program check
that fails the same run (`report/1`, `pns.check.ex:368`: any `:error` count above zero exits
`{:shutdown, 1}`, which fails `mix check`). If the gate is green, none of these are present either:
an event or process name declared by two contracts (`pns.check.ex:81-100`), a `rule` naming an MFA
that does not exist or export the given arity (`pns.check.ex:161-177`), a `trace` naming an event
that does not resolve (`pns.check.ex:179-195` — a second-layer check behind the compile gate, since a
contract can only see its own module at compile time), or an identity-vendor name leaking into the
engine's config (`pns.check.ex:334-347`). All four are enforced automatically; spending review time
re-deriving them is exactly the waste this skill exists to prevent.

## Part 2 — where review attention actually earns its cost

### 2. `mix pns.check`'s `:warn`/`:info` findings — visible in CI, not gate-enforced, need your judgment

These print in every `mix check` run but never fail it (`pns.check.ex:349-368` only counts `:error`
toward the exit code). Each one needs a human to decide "expected here" vs. "regression":

| Finding | Level | Source | What to decide |
| --- | --- | --- | --- |
| No contracts found in the configured applications | `:warn` | `pns.check.ex:57-72` | Should never appear on a PR that touches a contract. If it does, `config :pns, applications: [...]` is wrong — this is close to a hard blocker, not a judgment call |
| A declared event has no handler and is not `terminal` | `:info` | `pns.check.ex:103-129` | "Declared, never observed" is this repo's normal, deliberate mid-rollout state (every Rehmed event is in this state on purpose — `PLAN.md`). Ask: did the PR mean to leave this unhandled, or did it forget a handler it clearly intended to write? |
| An `owner:` module does not exist | `:info` | `pns.check.ex:143-158` | Same "mid-rollout is normal" reasoning — but check the named module is a real, planned owner, not a typo nobody will ever fill in |
| Backward edge between stages | `:warn` | `pns.check.ex:200-209` | This repo keeps two of these deliberately as acceptance-criteria fixtures (`PLAN.md`, "Stan na 6 sierpnia"). A **new** backward edge on a real contract or handler is a genuine ordering mistake — check which case this is before waving it through |
| N synchronous handlers on one event, ordered alphabetically | `:warn` | `pns.check.ex:211-224` | Alphabetical order "reproduces but says nothing about the process." If the PR's own logic depends on which handler runs first, that dependency is invisible to the engine — ask whether it should be, or whether one handler should instead publish an event the other subscribes to |
| `:string` payload field with no `retain` policy | `:info` | `pns.check.ex:237-251` | Reaches the log verbatim. Sometimes correct on purpose (Rehmed's exclusion-reason string, kept readable deliberately, per `PLAN.md`'s payer-settlement notes) — but check it isn't PII or free text that should have been `:hash`/`:drop` |
| Assertion finer than its run | `:warn` | `pns.check.ex:261-274` | Since 21 August this is quantified per item, not a false-satisfied bug — but it still needs `eventually`/`or_else` to carry the same `identity` field values as `from`, or a hit cannot resolve any item and the run stays open. Check the PR's `eventually`/`or_else` payloads actually carry those fields |
| Fact not keyed by its own run (`identity` missing a field `instance` requires) | `:warn` | `pns.check.ex:282-295` | Two facts in two different runs then share one idempotency key, and the second's handler silently never runs. Confirm this is either impossible for this event or genuinely intended |
| `trace` with no `within` | `:info` | `pns.check.ex:302-313` | No failing case exists; a run with nothing satisfying it stays `:pending` forever. Ask whether a number was simply never agreed, or whether one exists and was dropped |
| `process.unverified` names a field | `:warn` | `pns.check.ex:318-331` | The declaration exists but does not count toward the evidence report. Check the PR is not quietly relying on an `unverified:` number as if it were confirmed — and note separately that `unverified` never covers `trace` itself (`PLAN.md`'s open item, "`unverified` nie obejmuje `trace`") |

### 3. Where the randomness in the diff actually lives

`CLAUDE.md`'s own rule: review attention goes to decision functions, once per pattern for skeleton
and migrations, but every occurrence for anything that decides something. In a generated PR that is
concretely:

- A `rule`'s `given`/`example` pair — does the example read like a case the workshop actually
  produced (real numbers, a `source:` or a dated confirmation), or does it read invented? A rule
  without an example does not compile, but an example that compiles can still be a number nobody
  said.
- A handler's decision logic — the branch that actually chooses, not the dispatch boilerplate around
  it.
- Any edit to an **existing** contract's `identity:`, `instance:`, `retain:`, or a `trace`'s
  `from`/`eventually`/`or_else`/`within`. These are exactly the rows in `change-contract`'s delta
  table with **zero `PNS.Deployment.diff/2` support** — the diff tool cannot flag them, so the review
  is the only check left. Open `.claude/skills/change-contract/SKILL.md`'s delta-classification table
  and match the PR's change against it row by row rather than reasoning about the risk from scratch;
  in particular, a changed `trace` timing parameter silently reinterprets **every past run** the
  moment it deploys (`PNS.Trace.evaluate/3` always reads the contract as compiled now, with no
  versioned history), so a PR bumping one of these without a `since:` note for future reports is
  incomplete even if it compiles and passes.

### 4. "Verified in reverse," not just green

This repository's own convention, used repeatedly in `PLAN.md`: for a correctness-sensitive fix, the
author disables the fix and confirms the *specific* test meant to catch it goes red — not merely that
the suite is green with the fix in. Four worked examples, for calibration on what this looks like in
a PR description:

- *"Zweryfikowane odwrotnie — po zneutralizowaniu reguły pada cztery z ośmiu testów"* (`PLAN.md:983`)
- *"Zweryfikowane odwrotnie: po zneutralizowaniu walidacji pada siedem z piętnastu testów tego pliku"*
  (`PLAN.md:1062`)
- *"Zweryfikowane odwrotnie: po wyłączeniu zapisu padają trzy z dwudziestu trzech testów"*
  (`PLAN.md:1159`)
- *"wyłączenie kwantyfikacji, przestawienie priorytetu `:violated`/`:pending` i zepsucie gałęzi ...
  każde osobno wywaliło dokładnie ten test, który miało wywalić — nie sąsiedni, nie żaden"*
  (`PLAN.md:65-68`, the trace-granularity fix)

For any PR claiming to fix a bug or close a `known_defect`, check the description for this shape —
a named test, a named failure count, before-and-after. Its absence is not automatically a rejection,
but it is a question to ask before trusting the fix is actually the thing that was broken.

### 5. The language boundary, exactly as stated, not loosened

`CLAUDE.md` is specific: code is English, no exceptions, and the scope is not just `lib/pns/` but
also `lib/taxvision/`, `lib/rehmed/`, `test/`, `packages/pns_core/test/` fixtures, `config/`,
`priv/repo/migrations/`, `docs/`, and `mix.exs`. The only Polish allowed anywhere in that scope is
inside a string a client actually reads: `label`, `example` prose, `source:`, `unavailable_looks_like`
in a contract, task names, a notification subject. Everywhere else — identifiers, moduledocs, `@doc`,
comments, test names, compiler error strings — a Polish string is a defect, however small.

**Grepping for `[ąćęłńóśźż]` is not sufficient**, and this repository has the concrete counter-example
already checked into it: `rejestry` in `lib/taxvision/registry_check.ex:66` carries zero diacritics
and survived a full file-by-file rewrite meant to close exactly this class of finding — confirmed
present in the tree today. Reviewing for the language boundary means reading the diff's strings for
Polish words, not running a diacritics grep and calling it done.

### 6. Dated corrections, not silent rewrites

When an assumption in `docs/adr/` or a decision in `PLAN.md` turns out wrong, this repository's
convention is a dated correction — a new "Dopisek" entry, or a dated note inside the ADR file itself
— never a quiet edit that erases what was believed before. Two closed examples for calibration:

- The `%7C`/`%3A` escaping defect, closed 21 August with a `psql` count proving the migration cost
  was zero today (`PLAN.md`, "Dopisek 21 sierpnia (4)").
- The trace-quantification fix, closed the same day, with its own moduledoc and warning-message
  rewrite recorded as a correction rather than a silent behavior change (`PLAN.md`, "Dopisek 21
  sierpnia (5)").

For any PR that changes contract semantics, a check's meaning, or something `docs/adr/` already
describes, expect a matching dated note somewhere in the same PR. Its absence is a flag to ask about
— "where's the correction for this?" — not proof the PR silently rewrote history, but not something
to let pass unasked either.

### 7. Diff size as its own signal

`change-contract`'s non-negotiables state the rule for the writer: work from an actual diff, never
regenerate a whole module, because a full regeneration risks silently dropping an existing
`unverified:`, `source:`, or dated comment. The reviewer's job is the mirror check: if the PR's
stated change is "one field, one value" but the diff touches the whole file, that mismatch is the
signal to ask why — not a large diff to review line by line hoping nothing was lost, but a question
to send back before reviewing it at all.

## Non-negotiables

- **Never approve a PR that writes to `~/Projects/ai/empowered-house-context`** — a commit, a branch,
  or an edited file there, no exceptions, regardless of how the PR frames the reason (`CLAUDE.md`,
  `PLAN.md`'s "Rekord" section).
- **Never approve a PR that silently rewrites an existing dated `docs/adr/` or `PLAN.md` correction**
  instead of adding a new one — a rewritten "Dopisek" or ADR paragraph with no new date is the thing
  this convention exists to prevent.
- **Never approve on a gate that is not verifiably green**, and never accept a `tail`-piped result as
  that verification.
- **Never wave through Polish text outside `label`/`example` prose/`source:`/
  `unavailable_looks_like`/task names/notification subjects** on the strength of a diacritics grep
  alone.

## Procedure

1. Confirm the gate: get the real exit code of `mix check`, not a tail'd log. If it is not green,
   stop — there is nothing to review yet.
2. Read every `mix pns.check` finding in the CI output. Anything at `:error` is already
   gate-enforced — skip it. For every `:warn`/`:info` touched or newly introduced by this diff, use
   the table in Part 2.2 to decide expected vs. regression.
3. Read the diff itself for where the randomness is: `rule`/`example` pairs, handler decision
   branches, and any edit to an existing contract's `identity`/`instance`/`retain`/`trace` fields —
   for the last group, open `change-contract`'s delta table and check the PR's own stated reasoning
   against it, row by row.
4. For anything claiming to fix a bug, check the PR description for a "verified in reverse" claim —
   a named test, a named failure count with the fix reverted.
5. Grep the diff's strings for Polish outside the allowed surface — read for words, not only for
   diacritics.
6. If the PR changes contract semantics or something `docs/adr/`/`PLAN.md` already describes, look
   for the matching dated correction. Ask if it's missing.
7. Compare the diff's size against the PR's stated scope. A one-field change spread across a fully
   rewritten module is a question to send back, not a longer review.
8. Approve, or send back naming the specific finding, row, or line — never a general "looks fine."

## What this does not do

Does not replace `mix check` — a red gate is never something to review past, only something to stop
at. Does not decide contract-semantics correctness by itself: that judgment belongs to
`change-contract`'s delta table and, beyond it, to whoever actually confirmed the process with the
client — this skill only makes sure the reviewer opens that table instead of re-deriving its
reasoning from memory. Is not a substitute for the process owner's confirmation on `unverified:`
declarations — no PR can un-mark something as unverified by asserting it in a commit message; only
the process owner's own word does that, and that word does not show up in a diff.
