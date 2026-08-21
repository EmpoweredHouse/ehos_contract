---
name: module-boundary-check
description: DRAFT, not yet reviewed. Before adding a new business entity, action, or CRUD screen to this application, decide (1) whether the action should dispatch through PNS's event/handler mechanism at all, (1a) if not, whether it should still use an internal untracked event/handler shape for decoupling versus a direct function call, and (2) if it does go through PNS, separately whether it needs structural tracking (process, instance, stages — for drift/untraversed-path detection, no timing required) and/or a timed promise (trace, cadence, deadline) — then check what already exists before generating anything. Use when about to add a new module, table, or action to lib/taxvision/ (or a future client tree) — not when editing an already-declared contract, which has its own workflow (see change-contract).
---

# Deciding where a new feature lives, before writing it

DRAFT — not yet run against a real feature addition. Review before trusting it on real code. A
revision below corrected an earlier version that conflated two separate decisions; see
"Revision" for why that distinction matters.

## The decision this closes

The engine's contract machinery and the application's ordinary CRUD code live in the **same
app**, and that is fine — `boundary` is what makes mixing them safe, because a module that
reaches somewhere it should not is a compile error, not a discovery made later in a join.
What `boundary` does not do is tell you, before you write anything, *which kind of code you are
about to write*. Guessing wrong is expensive in both directions — wrapping a database write in
contract ceremony it does not need, or leaving an automated reaction unverified because it
looked like "just a field update."

## Revision: this is two questions, not one

The first version of this skill asked a single litmus test and treated its "yes" branch as one
thing: "contract territory." That conflated **using the event/handler mechanism** with
**attaching verification machinery** (`process`, `instance`, `trace`, `cadence`, `deadline`) —
and they are independently decidable, confirmed against a coupling analysis of event-driven
design (["Events and different kinds of coupling"](https://mkaszubowski.com/2019/06/28/events-and-different-kinds-of-coupling.html)):
decoupling modules with an event can be done **synchronously and transactionally**, inside one
ACID transaction, which is exactly PNS's sync dispatch path — it costs no queue, no eventual
consistency, and (confirmed against `PNS.Contract`) no `instance`/`identity` either, because
those are only required once an event joins a `process:`. A bare event with a handler, and
nothing else declared, is cheap. What is *not* free is `trace`/`cadence`/`deadline` — that
machinery answers a different question (is a *promise* being kept), and earns its cost only
when a promise actually exists.

So: ask both questions below, separately, and answer the second even when the first is "no
event needed" is the wrong reflex just because nothing looked "process-shaped."

## Question 1 — does this go through the event/handler mechanism at all?

> **Does another module need to react to this without the calling code knowing or depending on
> it?**

Yes → dispatch it as an event, sync (same transaction) by default; async only if the reaction
genuinely needs to be decoupled operationally (a slow call, a different failure domain). This
is the actual claim of that analysis: events reduce *logical* coupling between modules, and that
reduction does not require a queue. `dodano_klienta` triggering a welcome notification from a
different module is exactly this case, with **no** `instance`, no `identity`, no `process` —
just an event, a payload, a handler.

No (the calling code itself performs the whole effect, nothing else needs to react) → a plain
function call. No event. Stop — Question 1a and Question 2 below do not apply.

## Question 1a — only if Question 1 was "no": direct call, or an internal decoupling signal?

A "no" to Question 1 does not always mean "call the other module's function directly." There is
a middle option: an **internal, untracked signal** — same event/handler *shape* for code
organization, dispatched entirely outside PNS (no contract, no registry, no graph, no drift
check). This is not a PNS feature and does not belong in `lib/pns/` — it earns nothing from the
library, because the whole value of PNS is the tracking this deliberately skips. It is plain
Elixir: a module holding a list of subscriber callbacks, invoked in the same function, same
transaction, by default. Reach for `Phoenix.PubSub` or a queue only if there is a concrete reason
to decouple operationally — that reason is itself a sign this might actually belong back in
Question 1 as a real PNS event.

Decide with that same distinction, not taste:

> **Does the calling module's own correctness depend on what the other side does with this fact?**

Yes (real functional coupling — the caller needs the result, an error, or a specific ordering to
proceed correctly) → **direct function call.** An event would not remove this coupling, only hide
it — the canonical example is a shipping deadline that is equally hard to satisfy whether it is
wired as a function call or an event.

No (the caller only announces a fact; who reacts, how many react, and whether anyone reacts yet
are none of its business — and that list is expected to grow without editing the caller) →
**internal signal.** Keep it boring: a plain module, a plain list of callbacks, called
synchronously. Name it so nobody mistakes it for a governed PNS event — a suffix or namespace
distinct from anything with a `payload:`/`label:` declaration, and a one-line moduledoc note:
*"internal only, not tracked by PNS, see `module-boundary-check`."*

**Semantic coupling still applies even though nothing is tracked.** The same analysis's warning
that events increase semantic coupling is not conditional on a formal contract — the moment a second
module depends on a signal's name and payload shape, changing that shape is a breaking change
whether or not `PNS.Contract` knows about it. Treat the signal's shape as deliberate from the
first version, the same discipline as a public function signature.

**Graduation path.** If a real promise later shows up for this fact ("after this, within N, that
must follow, or else..."), that is the signal to move it into Question 1's "yes" branch — add the
contract declaration, switch the dispatch call from the internal signal to `PNS.emit`, and keep
the handler function itself unchanged as far as possible so the move is cheap.

## Question 2 — only if Question 1 was "yes": does this event need verification machinery?

**This is two separate criteria, not one — an earlier version of this section conflated them.**
Getting this wrong reads as "does it need a `trace`", which skips right past the cheaper,
independently useful criterion below.

**Criterion A — structural (`process` + `instance` + `stages`, no `trace` needed):**

> **Is this one step in a multi-step run, where it matters whether the declared step actually
> gets exercised across every run, and whether anything happens that was never declared?**

Yes → give it `process:`/`stage:`, and give the process `instance`. This alone buys
`PNS.Conformance.untraversed_paths` (a declared step that silently never fires for anyone) and
drift detection (something happening that was never declared) — **no timing relationship between
events is required for either.** `lib/taxvision/contracts/accounting_month.ex` has three events
declared exactly this way today — `bank_statement_received`, `turnover_matched_with_invoice`,
`month_closed` — deliberately with handlers, on purpose, as a live demonstration of "declared,
never observed."

**Criterion B — a promise (`trace`, layered on top of Criterion A):**

> **Is there additionally a specific commitment — "after A, within N, B follows, or else C" —
> that someone confirmed and that matters if it breaks?**

Yes → `trace` assertion, same shape as `data_completeness_confirmed → accounting_month_opened
within 2 days`. No → the process stands on Criterion A alone; that is a complete, legitimate
answer, not a placeholder for a `trace` someone forgot to write. There is effectively no such
thing as B without A — `trace` is evaluated within `instance`, so a promise needs a process to
live in; the reverse is common and fine.

If Question 1 was "yes" but neither A nor B applies at all, that is a bare event — see the
procedure below.

**The mistake to watch for is now the opposite of the first version's warning**: not "avoid
events for CRUD," but "don't skip Criterion A because there's no obvious `trace`" — a lot of real
verification value (silent step failure, undeclared drift) lives in A alone, and reaching straight
for "is there a timing promise" undercounts it.

## Non-negotiables, carried over from this repo's own rules

- **PNS knows nothing about companies or business entities, no exceptions.** A CRUD context
  does not get engine-level awareness just because it is declared next to a contract. If a
  litmus-test answer implies PNS needs to know "which client this is" as a structured field,
  that is a sign the action is not contract territory after all — see `claims: %{}` in `PNS.Auth.Actor`.
- **Every new module declares `use Boundary` explicitly**, deps and exports named — even
  `deps: [], exports: []`. No module rides along under an existing boundary by omission; that is
  how a join or a hidden dependency gets in.
- **Never invent event or contract vocabulary to make a CRUD action feel more rigorous.** If the
  litmus test is genuinely unclear, say so and ask, rather than adding a word to the DSL that
  nobody from the workshop said.
- **Never write into `~/Projects/ai/empowered-house-context`.**

## Procedure

1. **Name the concrete action**, not the entity — "edit a client's VAT status" and "list clients"
   are two different questions even though both touch `clients`, and can land on different
   answers to both questions above.

2. **Answer Question 1 first, then Question 1a (if "no") or Question 2 (if "yes"), and commit
   before checking anything else** — otherwise the discovery step below gets read selectively to
   justify whichever answer feels like less work. "No event," "direct call," and "no promise" are
   real, common outcomes, not a failure to find a contract angle.

3. **If Question 1 is "no", answer Question 1a before writing anything:**
   - Direct call → `grep` for an existing owner before creating a new one — exports lists in
     `lib/pns.ex` and every `lib/taxvision/*.ex`, and existing migrations for the table.
     Duplicating an existing context is the same mistake the no-join rule exists to prevent, one
     layer up. Scaffold with an explicit `use Boundary, deps: [...], exports: [...]`, following
     the shape of an existing sibling context (e.g. `Taxvision.Periods`) rather than a generic
     Phoenix tutorial pattern — this codebase's convention for a private table is `exports: []`
     plus a narrow public function, not an exported schema. No event, no payload type, nothing in
     the contract.
   - Internal signal → same `boundary` discipline for whichever module owns the subscriber list;
     name and moduledoc it as explicitly untracked (see Question 1a); treat its shape as a
     deliberate, stable contract even though PNS never sees it.

4. **If Question 1 is "yes" but neither Criterion A nor B applies (bare event):**
   - Declare the event with `payload`, `label`, `owner`, and `identity` only if retries need
     deduplication — no `process:`, no `instance`, no `trace`.
   - Still check `docs/contract.md`/`mix pns.check` for an existing owner of this fact before
     adding a new one, same as any other declaration.
   - Watch the payload type dictionary here specifically: `[:id, :string, :integer, :timestamp,
     :enum]` has no decimal/float type, so a monetary field (an invoice amount, for instance)
     does not fit cleanly and needs a deliberate convention (e.g. integer cents), not a silent
     choice made once and forgotten.

5. **If Criterion A applies (structural, whether or not Criterion B also does):**
   - Check whether the event, process, or assertion already exists: `docs/contract.md`,
     `mix pns.check` (an `info` line naming an event with no handler, or an owner module that
     does not exist yet, both mean "declared but not built" rather than "does not exist").
   - Give the event `process:` and `stage:`, and give the process `instance` — this alone is
     enough to get untraversed-path and drift signal; a `trace` (Criterion B) is an addition on
     top, not a requirement to unlock A.
   - Do not invent the trigger condition, the timing, the stage boundaries, or the label — those
     come from whoever confirmed the process, the same rule `contract-distillation` applies before
     a contract gets written. Mark a guessed number `unverified` rather than asserting it.
   - For the event declaration itself, use `add-event` (`.claude/skills/add-event/`); for the
     handler that reacts to it, use `write-handler` (`.claude/skills/write-handler/`) — both built
     21 August 2026. Neither one re-decides what this skill already settled; they pick up from
     here.

6. **Record the decision where the next reader will see it** — a one-line moduledoc note on
   *the answers to every question that applied and why* — so the next person or agent does not
   re-run this triage from scratch on the same action.

## What this does not do

Does not generate the CRUD code or the contract code — it is the triage step before either, not
a replacement for `mix pns.check`'s compile-time gates or for a human reviewing the result.
Does not resolve genuinely ambiguous cases on its own: if either question's answer is unclear
after step 2, that is a real open question, not a bug in this skill, and it should be asked
rather than guessed past.
