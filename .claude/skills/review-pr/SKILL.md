---
name: review-pr
description: Before approving or sending back a pull request to this repository — a new declaration, a decider or a reaction, a contract edit, or anything under packages/eh_os_contract/lib/, sandbox/lib/taxvision/ or sandbox/lib/rehmed/ — separate what `mix check` already guarantees (the compile refusals with their codes, the scenarios as tests) from what only a person can catch: a new `mix eh_os_contract.check` warning left unexplained, a decision or a scenario that reads invented, an edit to a contract with history that `change-contract`'s table flags, a fix without a reverse check, Polish outside the allowed strings, a change a host sees without a CHANGELOG line or with one that says too little, a verdict-moving change not marked as one, a diff larger than its stated scope. Use for any review here, by a person or by an agent on a person's behalf. Not for your own change before its pull request — that is `ehos-dev:pre-pr-review`.
---

# Reviewing a pull request

Checked on 30 September 2026 (plan E11e) against `CLAUDE.md`, `packages/eh_os_contract/docs/contract.md`,
`packages/eh_os_contract/docs/rules.md` and the gate's aliases in `sandbox/mix.exs`. Not yet run on a real pull request in
this form.

## Where this sits

`module-boundary-check`, `contract-distillation`, `add-event`, `change-contract`, `write-decider` and
`write-reaction` are for whoever writes. `ehos-dev:pre-pr-review`, with this repository's part in
`.claude/review.md`, is the author reviewing their own change
before the pull request. This skill is for the person who receives it and has to approve it or send
it back — the gate `CLAUDE.md` names ("Człowiek jest bramą"). When the change edits a contract that
may have history, it does not re-derive the risk: it opens `change-contract`'s table and holds the
change to it, row by row.

## 1 — What not to re-check, because the gate did

`docker compose up -d && cd sandbox && mix ecto.setup && mix check` runs formatting,
`compile --force --warnings-as-errors`, `eh_os_contract.check`, the sandbox's tests, and each
package's own `mix check` — the engine's with `eh_os_contract.docs --check` and
`eh_os_contract.rules --check`. **If it is not green, there is nothing to review yet.** Ask for the
exit code itself; `mix check | tail -4` reports `tail`'s, which is always zero (`CLAUDE.md`, 6
August: 24 failures committed behind it). The safe form ends in `echo "EXIT=$rc"`.

Given a green gate, three things are closed:

- **Every compile refusal** — `packages/eh_os_contract/docs/contract.md`, "What will not compile": `N`, `F`, `A`, `C`, `P`,
  `R`, `K`, `S`, `D`, `X` and `I` codes, layers L1–L4. Among them: an event outside a command's
  `emits:`, a refusal outside its `rejects:` (`I4`, `I5`), an invariant with no `rejected` scenario
  (`S8`), a sibling's field used and removed (`X6`), an `:at_least_once` reaction without
  `idempotency` (`P3`).
- **The scenarios, as tests.** `EhOsContract.ScenarioCase` makes each one a test against the
  implementation, so "the code does what the scenario says" is closed. Whether the scenario says the
  right thing is not (below).
- **The generated documentation is current**: `packages/eh_os_contract/docs/dsl/` and `packages/eh_os_contract/docs/rules.md` against the code,
  `packages/eh_os_contract/docs/contract.md`'s examples and refusal table against the code (`test/docs_test.exs`).
- **The docs are complete and most of their references resolve**: every public function of each package's
  `lib/` has a `@doc` or `@doc false`, and every documented one a `@spec` (`test/doc_coverage_test.exs`;
  a `@doc false` function is not held to a `@spec`, though `CLAUDE.md` still asks for one); and no doc
  references a missing or hidden function of an existing module, a hidden module, a module outside `lib/`
  or a missing page (`docs --warnings-as-errors`). Two things stay open (below): whether a doc is *true*,
  and a reference to a module that does not exist at all, which ExDoc renders as plain code without a
  word.

## 2 — Where attention earns its cost

### New `check` lines

`mix eh_os_contract.check` prints warnings and notices on every run, and **the gate does not fail on
them**: the sandbox runs it without `--warnings-as-errors`, and the counts are recorded in
`PLAN.md`'s handoff (30 September: sandbox 0 errors, 29 warnings, 9 notices; engine 0 / 66 / 5).
Compare the pull request's counts with those. Every new line needs a sentence from its author —
"expected, because…" or a fix. `packages/eh_os_contract/docs/rules.md` says what each rule means; the ones that most often
hide a mistake:

| Rule | Ask |
| --- | --- |
| `no-contracts` | Always a blocker on a change that touches a contract: `config :eh_os_contract, applications:` is wrong. |
| `emits-never-produced` | Is the declaration wider than the decision, or does the code return an event around `emit/1`? |
| `competing-in-transaction-consumers` | Does one reaction depend on the other's order? Then it should react to what the other decides. |
| `in-transaction-policy-fan-out` | Every other append waits for the whole list. Should it be `:at_least_once`? |
| `free-text-not-personal` | Is the `:string` really free text that may stay after erasure, or personal data, or a code with a type of its own? |
| `unverified-declaration` | Is the change relying on an `unverified: true` number as if it were confirmed? |
| `consults-without-match` | A boundary reading every event of a type conflicts under load. |
| `backward-edge` | A new one on a real process module is an ordering mistake in its stages or an undeclared loop. |
| `declaration-without-implementation` | Declared, not built — intended in this pull request, or forgotten? |

### Where the randomness is

`CLAUDE.md`: review attention goes to what decides; skeleton, migrations and boundaries are reviewed
once per pattern. In a pull request here that is:

- **A decider's clauses** — the branch that chooses, not the binding around it. A clause that
  encodes an assumption nobody stated should say so in the moduledoc (`write-decider`, step 8).
- **A reaction's `delivery`** and what a failure then leaves in the log (`write-reaction`).
- **Scenario data, invariant labels, `source:`** — does it read like a case from the material, with
  real numbers and a citation, or invented? A scenario that compiles can still be a number nobody
  said, and it is the specification the code was written against.
- **Any edit to a declaration that may have history** — a field, a type, an enum, `personal:`, a
  unit's identity, `correlate`, a promise, a deadline, a command's name or `by:`. Open
  `change-contract`'s table and match each change to its row. A required field added to an event
  with rows, a renamed event or unit, a flipped `personal:` — each compiles, passes the gate and
  breaks the stream it touches. The author should have counted the rows of the type; ask for the
  count.
- **A host-visible shape** — a capability (a command's or query's name), a command's fields, a
  query's parameters, a publication, configuration, a status. These go to the user before they
  change (`PLAN.md`, stage 6 strategy).

### Verified in reverse

For a fix, the author reverted it and watched the one test meant to catch it go red, and no other
(`ehos-dev:pre-pr-review`, step 5). The pull request says which test and how many failed, in the shape "with
the fix reverted, N of M tests in `<file>` fail, all of them about <the case>". Its absence is
not a rejection by itself, but it is a question to ask before trusting that the fix is the thing
that was broken.

### The language boundary

Code is English, without exceptions, in everything under `packages/` and `sandbox/` and in `docs/`.
Polish is allowed only inside the strings `CLAUDE.md` lists ("Po polsku jest wyłącznie…"): labels
and `source:` in a domain and a contract, a term's text, its definition, `avoid` and translation,
`where` prose at `consults`, scenario descriptions, task names, a notification subject. Everywhere
else — identifiers, moduledocs, `@doc`, comments, test names, error messages — it is a defect.
**Grepping for `[ąćęłńóśźż]` is not enough**: much of Polish has no diacritics, and a word such as
`rejestry` once survived a full file-by-file rewrite that way. Read the strings.

### Dated corrections, not silent rewrites

A change to what `docs/adr/` assumes or `PLAN.md` decided comes as a dated note, never a quiet edit
that erases what was believed before (`CLAUDE.md`, "Zanim cokolwiek zmienisz"). For a change to
contract semantics or to a check's meaning, look for the note in the same pull request.

### A changelog line that is missing, says too little, or misses a marker

Every change a host can see has a line under `## [Unreleased]` in its package's `CHANGELOG.md`, or a
line `No changelog: <why>` in the description (`CONTRIBUTING.md`, "Changelogs and releases"). The
Changelog check (`.github/workflows/changelog.yml`) fails a pull request with neither, but judges
neither: read the line as a host would. Does it say what changed for them, in their words? Does a
change a host has to act on when it upgrades start with `**Breaking:**`? Is the `No changelog:`
reason true — a change to `lib/` that a host cannot see, not one nobody wanted to describe?

`packages/eh_os_contract/CHANGELOG.md`: a change that can move a verdict raises the minor version and
gets a line starting with `**Moves a verdict:**`. A verdict is anything the conformance report prints
as a number or a state. Nothing mechanical enforces that part, and this list of files that trigger
the question lives here and only here:

`packages/eh_os_contract/lib/eh_os_contract/` — `conformance.ex`, `conformance/`, `trace.ex`,
`run.ex`, `stage_order.ex`, `paths.ex`, `coverage.ex`, `event_run.ex`, `deployment.ex`,
`dependency.ex`, `digest.ex`, `contract/build.ex` (the contract's version and its declarations' digests), `duration.ex`,
`report.ex`, `report/`, `graph.ex`, `graph/` — and, where the change touches runs, keys or failure
labels, `store/postgres.ex`, `key.ex` and `dispatcher.ex`.

A diff touching one of these without a `**Moves a verdict:**` line goes back, or its author writes in
the pull request why it cannot move a verdict. That answer is often right; it should be written, not
assumed.

### A doc that no longer describes its function

The gate holds that every documented public function has a `@spec` and that a doc's references to
existing modules resolve; it cannot hold that the doc is still true. When a pull request changes what a
public function returns, refuses or writes, read its `@doc` (and the generated page it feeds,
`docs/cli.md`, `docs/behaviours.md`, `docs/dsl/`) against the new code, and send back a doc that
describes the old behaviour or carries a stage or `§` code a host cannot read
(`.claude/skills/write-docs/SKILL.md`). A new reference to a module is followed on the built page
(`MIX_ENV=dev mix docs`): a misspelt module name passes the gate as plain code.

### Diff size

A stated change of "one field" in a diff that rewrites the whole module is a question to send back
before reviewing it: a regenerated module drops a `source:`, an `unverified: true` or a dated
comment, and nobody sees it go. `CLAUDE.md`: a pull request that cannot be read with attention is
not reviewed, only stamped.

## Non-negotiables

- **Never approve a rewritten dated correction** in `docs/adr/` or `PLAN.md` in place of a new one.
- **Never approve on a gate that is not verifiably green**, and never on a `tail`-piped log.
- **Never let Polish outside the allowed strings through** on the strength of a diacritics grep.

## Procedure

1. Get the gate's exit code. Not green → stop.
2. Compare the `check` counts with `PLAN.md`'s last recorded ones; for each new line, find the
   author's sentence or ask for one.
3. Read the deciders' clauses, the reactions' `delivery`, the scenarios' data.
4. For each edited declaration, find its row in `change-contract`'s table and the author's row count.
5. For each fix, find the reverse check.
6. Read the strings for Polish.
7. Look for the dated note, for each package's CHANGELOG line or the `No changelog:` reason, and for
   `**Breaking:**` and `**Moves a verdict:**` where they belong.
8. Compare the diff's size with its stated scope.
9. Approve, or send back naming the finding, the row or the line — never "looks fine".

## Not this skill

Replacing the gate: a red gate is where review stops, not something to review past. Deciding
whether the modelled process is right — that is whoever confirmed it with the client, and
`unverified: true` goes away only on their word, which no diff carries.
