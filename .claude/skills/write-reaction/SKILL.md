---
name: write-reaction
description: Before declaring or implementing what reacts to an event of a contract — a `policy` that issues a command, an `effect` that calls an external system, a `process_manager` that steers a run with state and timers, or a `read_model` with the `query` that reads it — choose the kind, choose `delivery` (`:in_transaction` or `:at_least_once`) by what a failure must leave in the log, name `idempotency` so a second delivery is harmless, and know where a new consumer starts in a log that already has history. Use once the event exists; not for deciding whether the reaction belongs in the contract at all (see `module-boundary-check`) and not for the unit that decides the command a policy issues (see `write-decider`).
---

# Writing what reacts to an event

Checked on 30 September 2026 (plan E11e) against
`packages/eh_os_contract/docs/contract.md`, `packages/eh_os_contract/docs/dsl/contract-dsl.md`, `packages/eh_os_contract/docs/rules.md` and the
engine's source (`EhOsContract.Consumer`, `EhOsContract.Dispatcher`, `EhOsContract.Subscription`,
`EhOsContract.EffectJob`, `EhOsContract.ProcessManager`, `EhOsContract.Testing`). The reasons are in
`docs/adr/contract-v2.md` §12. Not yet run on a real change: read what it says against those before
trusting it.

## Which kind

A reaction is declared in the contract of the process it belongs to, beside the units, and bound
by a module with `use <Contract>, <kind>: :name`. Pick the kind by what the reaction produces:

| It… | Kind | Callback | Example |
| --- | --- | --- | --- |
| issues a command of this contract whenever an event happens | `policy` | per handled event, `(event) :: issued` | `Rehmed.StatutoryReporting.ReportOnClinicalClose` |
| acts outside the log: calls a system, sends a message | `effect` | per handled event, `(event) :: :ok \| {:error, term}` | `Rehmed.StatutoryReporting.SendP1Report` |
| steers one run over time: remembers, waits, gives up | `process_manager` | per reaction or timer that issues, `(event, state)` / `(state)`; `evolve/2` with a state | `Rehmed.ClinicalDocumentation.DocumentationChase` |
| keeps rows for someone to read | `read_model` + `query` | per projected event, `(event) :: :ok`; the query `(params, ctx) :: rows` | `Rehmed.Settlement.DailyTotals`, `…DailyTotalsFor` |

- A policy is stateless: it sees one event and nothing else. When it needs to remember something
  between events, or to act when something does *not* happen in time, it is a process manager.
- An effect is the only kind that may touch the world outside the database. When the world's answer
  matters to the process, the effect records it as an event (`EhOsContract.record/3`, as its
  `:system` actor, whose events declare `recorded_by:`), and the rest of the process reacts to that.
- A read model is the client's state, projected. It holds no decision: a rule about what may happen
  belongs to a unit's invariant, never to a projection someone reads before deciding.
- An event of a sibling contract is taken through `consumes Sibling, [:event]` (K1, X5). An event of
  another application arrives through `consumes "<name>.vN"` with the fields it reads (D11), into an
  inbox and never into this log (`EhOsContract.Inbox`), so **only a policy takes it** (`D12`): a
  read model, an effect or a process manager that needs it takes the event the policy's command
  records. Its `delivery:` changes nothing for that event — the inbox runs it in the transaction that
  writes its row — and the contract then asks for `<name>.subscribe`, the application's capability.

## Delivery: what a failure leaves behind

This is the decision the kind leaves open, and it is about the log, not about speed.

**`:in_transaction`** (the default for a policy and a read model) runs inside the dispatch that
appended the event (`EhOsContract.Dispatcher`, step 7): read models project, then policies react,
then effects act. What a policy issues is dispatched at once, in the same transaction.

- An exception in the reaction, or the `{:error, _}` of an effect delivered `:in_transaction` —
  one without `calls:`, which `P2` requires — **rolls back the command that caused it**: the
  person's command fails for a reason that is not theirs, and dispatch writes a `failed` row naming
  the reaction (`policy:<name>`, `read_model:<name>`, `effect:<name>`). An effect delivered
  `:at_least_once` fails after the commit and is retried, below.
- A rejection of what a policy issues is the unit's answer, not a failure: the first command stands.
- Every reaction runs while the transaction holds the store's global append lock, so every other
  append waits for it.

**`:at_least_once`** (the default for an effect, and the only choice for a process manager, `P4`)
runs after the commit. A policy or a read model delivered so is an ordered subscription — one event
a step for a policy, which dispatches, batches of 500 for a read model; an effect is an Oban job
holding the effect's key and the event's id, and nothing else.

- The triggering event stays in the log whatever the reaction does.
- A failing event is retried, then the subscription is `failing` at that position and **stops
  there**, never skipping: an ordered consumer that skips is a read model that silently lies.
  Getting past it is a person's decision, `mix eh_os_contract.subscriptions --skip` or `--reset`.
- An effect is retried, three attempts in all; what Oban keeps of a failure names the effect and
  the position, never a value.

So: `:in_transaction` when "if this did not happen, the command did not happen either" — a
projection that must be readable the moment the command returns, a policy whose command is part of
the same business step. `:at_least_once` when the reaction is a different failure domain — anything
that calls out, fans out, or may be slow. The compiler and `check` push the same way:

- `P2` refuses an effect that `calls:` an external delivered `:in_transaction`: a call cannot be
  rolled back with the append.
- `in-transaction-policy-fan-out` warns when a scenario shows an in-transaction policy issuing more
  than one command: each holds the append lock for the whole list.
- `competing-in-transaction-consumers` warns when two in-transaction policies or effects take one
  event: they run in an order the contract does not state. If one depends on the other, have it
  react to the event the other decides, so the order is a path the process shows.

## Idempotency: a second delivery must change nothing

`:at_least_once` means the reaction **will** see an event twice. `P3` makes a policy or an effect
delivered so name `idempotency:`, what makes that harmless — an atom the process owner and the
reviewer read, such as `:event_id`. The library does part of it itself, and the rest is yours:

- **A command a reaction issues is keyed by its cause**: `"policy:<contract>:<name>:<event id>:
  <index>"`, `"pm:<contract>:<name>:<source id>:<index>"`. A second delivery appends nothing, so a
  policy or a process manager needs nothing more — which is why `P3` does not ask a process manager.
- **An effect's side effect is not keyed by the library.** Pass `event.__meta__.id` on to the system
  called, or record the answer with an idempotency key derived from it, as `SendP1Report` does with
  `"p1-report-sent:#{meta.id}"`. The far end is where a duplicate e-mail is sent.
- **A read model writes the host's tables.** Key its rows by the event (`on_conflict: :nothing` on
  the event's id, as `DailyTotals` does), or a replay double-counts.
- **Another application's event is deduplicated by the inbox**, by the message's key: the
  publisher's `idempotent_on:` values, or the message id when it declares none. A redelivery, and the
  same fact published again under a new id, react once. A publisher whose `idempotent_on:` is too
  narrow makes two real facts one: when you write the `publish`, name the fields that make one fact,
  not merely some that identify it.

## Where a new consumer starts

What is in the log when a consumer is first registered is history, and nothing new reacts to
history by itself (`EhOsContract.Subscription`, "Where a new consumer starts"):

- a new policy starts at the head of the log: a deploy onto a year of history issues nothing for
  that year;
- a new process manager replays with its reactions suppressed: it learns the runs already there and
  steers none; a timer of theirs already due is dropped;
- an ordered read model starts at position 0; an inline one at the head, and one added to a log
  that already has its events is rebuilt by hand;
- a read model whose declaration or events change is `stale` until rebuilt, and rebuilding needs its
  optional `reset/0`; without it, it stays stale. A process manager that changes is `stale` too, and
  is rebuilt at boot, since the library owns its table. One projecting personal fields needs `forget/2` or
  the engine will not boot
  (`docs/adr/contract-v2.md` §14).

Reacting to history is a person's `--reset`, never a side effect of a deploy. If the change needs
it, say so in the pull request.

Another application's history does not come over the bus at all: an inbox's consumer gets what is
published once the transport delivers to it — between nodes, from EHOS's grant of `<name>.subscribe`
on — and the engine starts every inbox before any relay, so in one node nothing is published past
it. What was published before is asked of its owner (`eh-os` D-03).

## A process manager, in particular

- `correlate` names the run. An event it takes that lacks those fields joins no run and is passed
  over, and nothing refuses it at compile time for a local event (`F4` only refuses them optional
  or personal; `X6` checks a sibling's): check each event it names carries them.
  Its state holds no personal data (`F7`): it lives outside the log, where erasure cannot reach.
- A timer fires `wait:` after the event that set it, or `at:` a `:timestamp` of its state. The
  firing is an event in the log, so a timer fired twice dispatches once, and a replay recomputes the
  same timers.
- Declare `ends_on` (`process-manager-without-ends-on`), or every run stays open for ever with its
  state kept. A manager that reacts only to its own timers (`process-manager-without-event-reactions`)
  is a schedule, and may be simpler as one.
- A timer that issues is a callback of the state alone: whatever the command needs — the run's
  correlation is injected — has to be in the state by then.

## Procedure

1. Name what the reaction produces, and pick the kind from the table.
2. Pick `delivery` from what a failure must leave in the log. Write the reason in the moduledoc,
   one line, so the next reader does not re-derive it.
3. If `:at_least_once`, name `idempotency`, and make the effect's or projection's own writes keyed by
   the event.
4. Declare it in the contract, then a scenario for it: an `on` event with the `issues` it expects
   for a policy or a process manager, a `query` with `answers` for a read model
   (`reaction-without-scenario`). An effect has no scenario (`S6`): its test is yours.
5. Bind the module (`use <Contract>, policy: :name`), compile, and add what `I2` asks for. `issue/1`
   takes command struct literals within the declaration's `issues:` (`I4`, `I6`).
6. Test what runs after the commit with `config :eh_os_contract, subscriptions: :manual` and
   `EhOsContract.Testing.drain/1`. The first `drain/1` is the deploy. For a policy or a process
   manager, drain once before dispatching what it takes, or it treats that event as history and does
   nothing. An ordered read model starts at position 0, so its first `drain/1` projects what the log
   already holds.
7. Run the gate from `sandbox/` and read any new `check` line naming the reaction.

## Not this skill

The unit that decides a policy's command — `write-decider`. Declaring the event it reacts to —
`add-event`. Whether a reaction belongs in the contract, or is a plain function call —
`module-boundary-check`. Changing a reaction that already runs against history — `change-contract`,
because a changed declaration marks a read model stale and moves the contract's version.
