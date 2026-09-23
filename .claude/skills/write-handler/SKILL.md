---
name: write-handler
description: DRAFT, not yet reviewed. Before writing a module that does `use EhOsContract.Handler` for an already-declared event, decide sync or async, get the idempotency key right if async, and know exactly what happens to the log on each side of the transaction boundary when the handler fails. Use once an event exists in a contract (see add-event for declaring the event itself) and you are wiring a reaction to it; not for deciding whether the reaction should be an EhOsContract event at all (see module-boundary-check) and not for the pure function the handler body should delegate its decision to (a separate, not-yet-built "write a decision function" skill).
---

# Writing a `EhOsContract.Handler`

DRAFT — not yet run against a real handler. Review before trusting it. Every claim below about
`EhOsContract.Handler`, `EhOsContract.Emitter`, `EhOsContract.Job`, and `EhOsContract.Check` was checked against
`packages/eh_os_contract/lib/eh_os_contract/{handler,emitter,job,check,handler_failure,sync_handler_error}.ex` on
21 August 2026, with file:line citations, not carried over from the ADR row that names this skill.

## Where this sits

`module-boundary-check` already decided that this fact should dispatch as an EhOsContract event, and
whether it needs `process`/`instance` (Criterion A) or a `trace` promise (Criterion B) on top —
this skill starts after that "yes." `add-event`, a parallel sibling skill, declares the event
itself in the contract, with its `payload`, `identity`, `process`/`stage`. This skill wires a
handler module to an event that already exists; it does not create the event and does not decide
whether one should exist. `change-contract` is the workflow for editing a contract that already
has handlers attached to it — reach for it, not this skill, if the change is to the event's
`payload`, `identity`, or `publishes:` edges rather than to a new handler module.

## What `use EhOsContract.Handler` actually accepts and enforces

Verified against `packages/eh_os_contract/lib/eh_os_contract/handler.ex:18-73`. The macro takes:

- `contract:` (required) — the module with the event declaration. Must have `use EhOsContract.Contract`
  (checked via `function_exported?(contract, :__eh_os_contract__, 0)`, handler.ex:29-31).
- `event:` (required) — must already be declared on `contract` (handler.ex:33-39).
- `publishes:` (optional, defaults to `[]`) — every name in the list must be declared on
  `contract` too (handler.ex:41-47). This is the *compile-time* half of the publishing promise —
  it checks the declaration against the contract, not the handler body against the declaration.
- `async:` (optional, defaults to `false`).

All four checks run in the macro body (not inside `quote`), which is deliberate per the
moduledoc (handler.ex:1-13): it makes the contract a compile-time dependency of the handler and
makes `__CALLER__` point at the handler's file:line, not at the library, when something is wrong.

If `async: true` and the event has no `identity:` declared, compilation fails
(handler.ex:49-57) — the message names the actual reason: Oban is at-least-once, so the event
*will* arrive twice, and "what makes two occurrences the same fact" is a process-owner decision,
not something the handler can supply on its own.

The generated module gets `@behaviour EhOsContract.Handler` and a `__eh_os_contract_handler__/0` function returning
`%{module:, contract:, event:, publishes:, async:}` (handler.ex:59-72) — this is the metadata
`EhOsContract.Registry`, `EhOsContract.Job.resolve/1`, and `EhOsContract.Check` all read; there is no separate registration
step.

**The callback**, per `@callback` (handler.ex:15) and both real fixtures
(`sandbox/lib/taxvision/tasks.ex:60-61`, `sandbox/lib/taxvision/notifications.ex:60-61`):

```elixir
@impl EhOsContract.Handler
def handle(payload, ctx) :: :ok | {:ok, list()} | {:error, term()}
```

`payload` is the event's payload, already cast to atom keys with declared `:timestamp` fields
restored to `DateTime` (`EhOsContract.Payload.cast/2`, emitter.ex:56-65) — the same shape on both dispatch
paths (job.ex:64, emitter.ex:323). `ctx` carries `correlation_id`, `causation_id`, `chain`
(the causal ancestor path, root first, as event-name strings — emitter.ex:312-321), and `actor`
on both paths; an async handler additionally gets `attempt` and `idempotency_key`
(job.ex:66-81) — a sync handler's `ctx` has no `idempotency_key` because sync handlers run inside
the emitting transaction and have no queue-arrival problem to key against.

Returning `{:ok, list()}` means a list of `EhOsContract.Emission.t()` (`EhOsContract.event/2`, `packages/eh_os_contract/lib/eh_os_contract.ex:40`) —
further facts this handler is choosing to publish. Every name in that list must be in this
handler's own `publishes:`; `EhOsContract.Handler.verify_publications!/2` is called on the result, on
**both** dispatch paths (`emitter.ex:460`, `job.ex:134`), before those emissions reach the log.

## The transaction boundary — the one thing a check cannot express

This is the actual decision the "sync or async" choice reduces to, and it is worth stating in
full because the two failure paths leave genuinely different marks on the log.

**Synchronous** (`async` omitted or `false`): the handler runs inside the same database
transaction that inserted the triggering event (`EhOsContract.Emitter.dispatch_sync/6`, emitter.ex:396-472,
called from inside `do_emit/5` which itself runs inside `in_own_transaction/2`, emitter.ex:178-248).
If the handler raises, the exception is wrapped in `EhOsContract.SyncHandlerError`
(emitter.ex:434-443) and propagates up through the transaction, which rolls back. **The row for the
triggering event is gone along with everything the handler did** — the log ends up as if
`EhOsContract.emit` was never called at all. What survives the rollback is a `EhOsContract.HandlerFailure` row,
written by `in_own_transaction/2` in the frame that opened the transaction, strictly *after* the
rollback commits and the connection is free again (emitter.ex:219-247,
`handler_failure.ex:31-43`) — carrying `contract`, `event_type`, `handler`, `correlation_id`,
`instance_id`, and the error message, but **no reference to the event itself**, because there is
no event to reference (`handler_failure.ex:13-16`). `EhOsContract.Conformance` reads this table specifically
to tell "never attempted" apart from "attempted and failed," which a bare absence in the event log
cannot distinguish (`handler_failure.ex:26-29`).

The one caveat: if the *caller* already had its own transaction open before calling `EhOsContract.emit`,
`in_own_transaction/2` never gets to write the failure row — `own?` is false, the exception
propagates into the caller's transaction, and the caller's rollback is what happens
(emitter.ex:230-247, `handler_failure.ex:38-43`, `sync_handler_error.ex:11-21`). Writing a
synchronous handler for an event that might be emitted from inside someone else's transaction
means that recording burden is now theirs, not the engine's.

**Asynchronous** (`async: true`): the job insert goes into the *same* transaction as the
triggering event (emitter.ex:477-497, comment: "that is an outbox for free") — so the event row
and the fact that a job was queued for it always commit together. But `EhOsContract.Job.perform/1` then
runs later, in a different BEAM process, deliberately **not** wrapped in a transaction
(`job.ex:9-13`): "an asynchronous handler exists precisely to do I/O against the outside world,
and a transaction around I/O holds a pooled connection for the duration of the call." If the
handler fails, `EhOsContract.Job.run/3` catches it (job.ex:105-117) and writes an `EventHandling` row with
`status: "error"` (job.ex:119-129) — **the triggering event's row is untouched**, because it was
already committed, in a transaction that closed before the job ever ran. The log now shows the
fact happened and a failed attempt to react to it, which Oban will retry up to `max_attempts: 3`
(job.ex:16).

So: same failure, opposite mark on the log. Sync failure erases the fact and everything downstream
of it, leaving only a `EhOsContract.HandlerFailure` row with no event to point at. Async failure keeps the
fact and records the failed reaction against it, retryable. **This is the actual criterion**,
stated as the moduledoc states it (job.ex:9-13) rather than as folklore: if the effect must be
atomic with the state change — same database, same transaction, "if this didn't happen the fact
didn't happen either" — it is sync. If the effect is I/O against something outside this
transaction's reach (email, an external API, a slow call) — a different failure domain that must
not hold a pooled connection open — it is async, and it must tolerate being retried and arriving
more than once.

## Idempotency (async only)

`ctx.idempotency_key` is built by `EhOsContract.Job.idempotency_key/3` (job.ex:156-166) from the *event's*
`identity:` fields in the contract, not from anything the handler declares — "a fact has one
identity, while one event can have many handlers" (job.ex:139-142). If `identity` is `nil`, the
key is just the event's row id (job.ex:157); otherwise it is `name` plus every identity field's
value, joined and **escaped** (job.ex:151-174). That escaping is not incidental: on 21 August 2026
this exact mechanism had a real defect closed in this session — `%` was not escaped before the
separator, so a value literally containing the escaped separator text collided with a value
containing the real separator (PLAN.md, "Dopisek 21 sierpnia (4)"). The worked lesson for a
handler author: the identity fields declared on the event are what your idempotency check keys
on, so they must actually distinguish two real occurrences of the fact — if they don't, a second,
genuinely different occurrence silently reads as a repeat and your handler never runs a second
time, with nothing in the log flagging it as skipped.

The house pattern for the idempotency check itself is a query against the handler's own table,
not a separate mechanism (`sandbox/lib/taxvision/notifications.ex:61-68`): `if <table>.exists?(idempotency_key
== ^ctx.idempotency_key), do: :ok, else: <do the effect>`. Named limit, from that fixture's own
comment: this only reaches the handler's own tables and mocked call counters — it cannot make an
actual outbound side effect (a sent email, a third-party call) idempotent on the far end.

## Ordering of multiple synchronous handlers on one event

Legal, not forbidden. `EhOsContract.Check.competing_sync_handlers/0` (check.ex:364-392) reports every event
with more than one sync handler and the order they run in — alphabetical by module name
(`EhOsContract.Registry`'s sort), "a fact about spelling rather than about the process." Two handlers
writing disjoint derived state are fine regardless of order. What is not fine is a handler that
*depends* on running before or after a sibling handler on the same event — if that dependency
exists, it is not really two independent reactions, and the fix named in the check's own
moduledoc is to express the sequence in the contract instead: one handler publishes an event the
other subscribes to, turning an alphabetical accident into a declared, visible path. Renaming
either module silently changes execution order today; that is the risk the warning exists to
surface, not a defect to route around locally.

## What happens if a queued job's handler module is later removed or renamed

`EhOsContract.Job.resolve/1` (job.ex:183-198) treats "module doesn't exist," "exists but won't load," and
"loads but isn't a handler anymore" as the same case: gone. `perform/1` then calls `abandon/2`
(job.ex:40-58), which **cancels** the job (`{:cancel, reason}`, not a retry) and records an
`EventHandling` row with `status: "cancelled"` and a reason naming the actual cause: "handler ...
no longer exists, so this job belongs to a wiring that is no longer deployed." This used to retry
and fail identically three times before landing in `discarded` with an opaque atom error — the
current behavior exists so a rename or removal with jobs already queued produces one clear,
searchable row instead of three noisy failures that say nothing about why.

## Telemetry — do not duplicate it

Both dispatch paths wrap the handler call in `EhOsContract.Telemetry.handler_span/2`
(`emitter.ex:417`, `job.ex:107`, `telemetry.ex:86-89`), which is a `:telemetry.span/3` around
`[:eh_os_contract, :handler]` — emitting `:start`, then `:stop` or `:exception` in the standard shape. A
handler body should not wrap its own `handle/2` in try/rescue for the purpose of observability or
instrument its own timing — that is already done, on both paths, by the caller.

## Non-negotiables

- **No invented DSL vocabulary.** `contract:`, `event:`, `publishes:`, `async:` are the only
  options the macro accepts (handler.ex:20-23) — do not add a keyword to a `use EhOsContract.Handler` call
  that the macro does not already read; that is a library change, not a handler-writing decision.
- **Every new handler module still declares `use Boundary`** with explicit `deps:`/`exports:` —
  the handler is a regular module in the same boundary discipline as any other
  (`CLAUDE.md`; `sandbox/lib/taxvision/notifications.ex:8-14`, `sandbox/lib/taxvision/tasks.ex:11-13` for the shape).
- **Reach through `EhOsContract`/a contract's own MFA, never `capture`**, and never publish a dynamic event
  name — `CLAUDE.md`'s "reguła wskazuje MFA, nigdy capture" and "nazwy zdarzeń to literały" apply
  here exactly as everywhere else; `publishes:` is a literal list checked at compile time, and a
  handler computing an event name at runtime defeats that check by construction.
- **Code, identifiers, moduledocs, comments, and error text are in English.** `label:`/`subject:`
  strings the client reads (as in `sandbox/lib/taxvision/notifications.ex:86`) are the one carved-out
  exception, not a precedent for anything else in the handler.
- **Never write into `~/Projects/ai/empowered-house-context`.**

## Procedure

1. Confirm the event already exists and is what you think it is: `mix eh_os_contract.check` / `packages/eh_os_contract/docs/contract.md`
   for its `payload`, `identity`, and `process`/`stage`. If it does not exist yet, stop — that is
   `add-event`, not this skill.
2. Decide sync vs. async using the transaction-boundary criterion above, not habit: does the
   effect have to be atomic with the state change (same database, derived state) — sync; does it
   reach outside this transaction's connection (I/O, a slow call, a different failure domain) —
   async.
3. If async, confirm the event has `identity:` declared. If it does not, this is a contract change
   (`change-contract`'s territory: adding `identity:` to an existing event), not something this
   skill can work around — the compiler will refuse `async: true` regardless.
4. Write `use EhOsContract.Handler, contract: ..., event: ..., publishes: [...], async: ...` (omit `async`
   for sync). List every event the handler's `handle/2` might return in `publishes:` — nothing
   else is checked against the handler body at compile time, and an undeclared emission is a
   runtime `ArgumentError` from `verify_publications!/2` on the first test that exercises it.
5. Write `handle/2` thin: it should read as "check idempotency if async, delegate the actual
   decision to a pure function, translate the result into `:ok`/`{:ok, emissions}`/`{:error, _}`."
   The pure decision function itself is the separate "write a decision function" skill
   (`docs/adr/technology-notes.md` §8) — not yet built; follow `sandbox/lib/taxvision/tasks.ex` and
   `sandbox/lib/taxvision/notifications.ex` for the shape meanwhile, not a freelanced structure.
6. If async, write the idempotency check against the handler's own table using
   `ctx.idempotency_key`, following `sandbox/lib/taxvision/notifications.ex:61-68`. Confirm the event's
   `identity:` fields actually distinguish the occurrences you need distinguished — the 21 August
   escaping defect is the standing reminder that "some field is declared" is not the same claim as
   "these fields are collision-free for this fact."
7. Give the new module its own `use Boundary, deps: [...], exports: [...]` following an existing
   sibling handler's module, not a generic pattern.
8. Run `mix compile --warnings-as-errors` from `packages/eh_os_contract/` (or the umbrella root) to
   confirm every compile gate above; then the relevant test suite, read-only, to exercise the
   handler on both success and failure.
9. Record, in the handler's moduledoc, which side of the boundary it is on and why — the same
   one-line convention `sandbox/lib/taxvision/tasks.ex` and `sandbox/lib/taxvision/notifications.ex` already use —
   so the next reader does not have to re-derive it from the dispatch code.

## What this does not do

Does not decide whether the underlying fact should be an EhOsContract event at all, or whether it needs
`process`/`instance`/`trace` — that is `module-boundary-check`, already answered by the time this
skill starts. Does not declare the event itself in the contract — that is `add-event`. Does not
write the pure decision function a well-shaped handler delegates to — a separate, not-yet-built
"write a decision function" skill per `docs/adr/technology-notes.md` §8; this skill only covers
the handler module and the `handle/2` shell around that function. Does not replace `mix eh_os_contract.check`'s
compile-time gates or `EhOsContract.Check`'s whole-program warnings — read those messages directly; this
skill explains what they mean, not a substitute for running them.
