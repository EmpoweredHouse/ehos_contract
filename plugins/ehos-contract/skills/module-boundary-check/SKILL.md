---
name: module-boundary-check
description: Before adding a new business entity, action, screen or table to an application (its `lib/<app>/`, or, in ehos-contract's own repository, a case study under `sandbox/lib/`), decide (1) whether it goes through a contract at all or is plain application code, (1a) if not, whether a plain function call or an internal, untracked signal, and (2) if it does, which declaration it is — a command to a unit, an event recorded without a decision, a reaction, a read model with its query — and separately whether the process owes a promise about it; then check what already exists before generating anything. Use when about to add a module, a table or an action; not when editing a contract that already has declarations (see `change-contract`).
---

# Deciding where a new feature lives, before writing it

Checked on 30 September 2026 (plan E11e) against `packages/ehos_contract/docs/contract.md`,
`packages/ehos_contract/docs/rules.md` and `CLAUDE.md`, "What the library is, and is not". Not yet run on a real feature:
read what it says against those before trusting it.

**In an application.** This skill is also the `ehos-contract` Claude Code plugin's, which an
application built on EHOS enables. There, the engine's paths below are under `deps/ehos_contract/`,
at the version the application pins: `packages/ehos_contract/docs/contract.md` is
`deps/ehos_contract/packages/ehos_contract/docs/contract.md`. `CLAUDE.md`, `docs/` and `sandbox/`
are ehos-contract's, on [GitHub](https://github.com/EmpoweredHouse/ehos_contract): where
a step names `sandbox/lib/…`, read the application's own `lib/<app>/`, and where it runs the gate
from `sandbox/`, run the application's `mix precommit`.

## The decision this closes

The client's ordinary code and the code a contract governs live in the same application, and that
is fine: where the project compiles with `boundary`, a module that reaches where it should not is a
compile error, and where it does not, the contexts' public modules and the domain's relations keep
them apart. Neither says *which kind of code you are about to write*. Guessing wrong costs in both
directions: contract ceremony around a plain write, or a rule, a reaction or a promise the
conformance report never sees because it looked like "just a field update".

## Question 1 — does it go through a contract at all?

> **Does anything outside the calling code depend on it having happened, or on it being refused?**

A rule the business states about when it may happen (an invariant), another actor or module that
reacts to it, a promise that runs from it, a run it ends. Any of these → contract. None of them →
plain application code: a function, a table, a screen. That is a real and common answer, not a
failure to find a contract angle. `contract-distillation`'s first step asks the same thing of a
workshop sticky, and on a clinic's workshop it rejected 15 of 22 candidates: most "actions" were fields somebody
fills in.

A contract is also not where the client's state is answered from. A read model and its query may
hold that state, but the dashboard shows conformance, never "which company has no open July"
(`CLAUDE.md`).

## Question 1a — only if 1 was "no": a direct call, or an internal signal?

> **Does the caller's own correctness depend on what the other side does?**

- **Yes** → a direct function call. An event would hide that coupling, not remove it.
- **No** — the caller only announces something, and who reacts is none of its business → an
  internal signal: a plain module with a list of callbacks, called synchronously in the same
  function. It is not an EhosContract feature and does not belong in `packages/`: it earns nothing
  from the library, whose value is the tracking this skips. Name it so nobody mistakes it for a
  contract's event, and say in its moduledoc: *internal only, not tracked by a contract, see
  `module-boundary-check`*. Its shape is still a public interface: treat a change to it as one.

**Graduation.** When a rule, a reaction someone must be able to see, or a promise appears for it,
move it to Question 2: declare it in the contract and keep the callback's body as far as possible.

## Question 2 — only if 1 was "yes": which declaration?

Pick by what the business says, not by what the code will look like:

| The business says | Declaration | Next skill |
| --- | --- | --- |
| "X may only happen if…", someone asks and can be refused | a `command` to a unit, its `invariant`s, and the event it decides | `add-event`, `write-decider` |
| the rule spans events of several units ("every visit of the payer in the period is invoiced or excluded") | a `dcb` that `consults` them | `add-event`, `write-decider` |
| "it is noted that…", an observation, an external system's answer | an event with `recorded_by:`, entered with `EhosContract.record/3` | `add-event` |
| "whenever X, then Y" | a `policy` issuing a command | `write-reaction` |
| "tell / send / ask system S" | an `effect` that `calls:` S | `write-reaction` |
| "if Y has not happened a day after X, chase it" | a `process_manager` with a timer | `write-reaction` |
| "reception sees the day's totals" | a `read_model` and the `query` that reads it | `write-reaction` |

- A contract belongs to one context and describes what it decides; it has no run of its own. An event goes into the
  contract of the context it is born in, and is never declared twice: a sibling contract that
  reacts to it `consumes` it. The run it belongs to — a loan from lending to return, a visit from
  booking to its report — is a process module (`use EhosContract.Process`), which includes the
  events of one contract or of several (`stage …, include: [{Contract, [:event]}]`) and says what
  tells one run from another (`correlate`). A register whose units only decide and record has no
  process, and needs none.
- A sibling of **another context** is reached only the way the domain's `relation` between the two
  contexts allows. Upstream into downstream, or across `separate_ways`, does not compile (`X11`), and
  that holds for a field naming its unit or using a value it declares too. Across an
  `anticorruption_layer` only a policy takes the event (`X12`). Across an `open_host_service` or a
  `published_language`, only what the upstream contract `publish`es (`X13`). When the code needs
  more, the relation is the first thing to question, and changing it is a decision about the business.
- A new context, actor, value or external goes into the **domain** first (`use EhosContract.Domain`);
  the contract names them (`X1`–`X4`). An actor with nothing to do is `orphan-actor`; a context no
  contract uses is `bounded-context-without-content`.

## Question 3 — does the process owe a promise about it?

> **Did someone confirm "after A, within N, B follows, or else C", and does it matter if it breaks?**

- **Yes** → a `promise` in the process module, with the number that was stated, and
  `unverified: true` until the process owner confirms it (`unverified-declaration`). Its `from`,
  `eventually` and `or_else` are events the module includes (`R5`). When the awaited events follow
  a step that calls an external system, and neither calls it itself, the promise says
  `waits_on [:external]`, so an outage of it excuses the promise rather than breaking it (`X4`).
- **No** → the structure stands on its own, and that is a complete answer. The contracts' declared
  paths give the report untraversed paths and drift, and a process module's stages and `ends_on`
  its runs and the runs that went out of order, without any clock
  (`contract-distillation`, step 7). A promise with no agreed number is written without `within`,
  and `promise-without-within` says so rather than letting it read as kept.
- A reminder *before* a scheduled moment is not a promise — a promise runs forward from an observed
  event. It is a process manager's timer at a `:timestamp` of its state, or the client's own
  scheduling.

## Non-negotiables

- **The library knows nothing about companies or business entities.** If the answer implies the
  engine needs to know "which client this is" as a structured field, it is not contract territory.
- **Contexts are siblings, not a hierarchy.** A context is reached through its public module's
  functions, never through another context's schemas or tables, and a context of a contract only
  the way the domain's `relation` allows, which the engine holds (`X11`–`X13`).
- **Where the project's `compilers` in `mix.exs` include `:boundary`, every new context module
  declares `use Boundary`**, with `deps` and `exports` named, even empty ones, and a module under it
  joins that boundary, named in its `exports` only if code outside the boundary calls it
  (`sandbox/lib/lending/circulation.ex`): ehos-contract's own repository and its `sandbox/` do
  (`CLAUDE.md`), as does an application that set it up. Where they do not, as in an application
  `ehos_app` generates, no module declares one: without the compiler it checks nothing and reads as
  if it did. Its absence there is not a finding.
- **No new DSL word to make an action feel more rigorous.** If none fits, say so and ask; a new word
  goes to the user with an example.

## Procedure

1. **Name the concrete action**, not the entity: "change a client's VAT status" and "list clients"
   are two questions even though both touch `clients`.
2. **Answer Question 1, then 1a or 2 and 3, and write the answers down before searching** — otherwise
   the search below gets read to justify the answer that is less work.
3. **Look for what exists.** For plain code: the exports of the context modules
   (`sandbox/lib/<case>/*.ex`, such as `sandbox/lib/lending/circulation.ex`) and existing migrations. For a
   declaration: the contract of the context (`sandbox/lib/*/contracts/`), the domain, and
   `mix ehos_contract.check` — a `declaration-without-implementation` or
   `contract-without-implementation` line means "declared, not built", not "missing".
4. **Plain code** → scaffold it after an existing sibling context, with a narrow public function,
   not an exported schema (and `exports: []` where the project compiles with `boundary`).
   **Internal signal** → the same, named and documented as untracked. **A declaration** → the
   skill in the table.
5. **Record the answers** in the new module's moduledoc, one line per question that applied, so the
   next reader does not run this triage again.

## Not this skill

Writing the declaration or the code — the skills in the table. Editing a declaration that exists —
`change-contract`. A case that stays unclear after step 2 is an open question for the user, not
something to guess past.
