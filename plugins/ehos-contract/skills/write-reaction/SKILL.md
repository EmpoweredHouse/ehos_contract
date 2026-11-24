---
name: write-reaction
description: Before declaring or implementing what takes an event of a contract — a reaction: a `policy` that issues a command, an `effect` that calls an external system, a `process_manager` that steers a run with state and timers, or the consumer that is not a reaction, a `read_model` with the `query` that reads it — choose the kind, choose `delivery` (`:in_transaction` or `:at_least_once`) by what a failure must leave in the log, name `idempotency` for a policy or an effect delivered `:at_least_once` so a second delivery is harmless, and know where a new consumer starts in a log that already has history. Use once the event exists; not for deciding whether the reaction belongs in the contract at all (see `module-boundary-check`) and not for the unit that decides the command a policy issues (see `write-decider`).
---

# Writing what takes an event

Checked on 30 September 2026 (plan E11e) against
`packages/ehos_contract/docs/contract.md`, `packages/ehos_contract/docs/dsl/contract-dsl.md`, `packages/ehos_contract/docs/rules.md` and the
engine's source (`EhosContract.Consumer`, `EhosContract.Dispatcher`, `EhosContract.Subscription`,
`EhosContract.EffectJob`, `EhosContract.ProcessManager`, `EhosContract.Testing`). The reasons are in
`docs/adr/contract-v2.md` §12. Not yet run on a real change: read what it says against those before
trusting it.

**In an application.** This skill is also the `ehos-contract` Claude Code plugin's, which an
application built on EHOS enables. There, the engine's paths below are under `deps/ehos_contract/`,
at the version the application pins: `packages/ehos_contract/docs/contract.md` is
`deps/ehos_contract/packages/ehos_contract/docs/contract.md`. `CLAUDE.md`, `docs/` and `sandbox/`
are ehos-contract's, on [GitHub](https://github.com/EmpoweredHouse/ehos_contract): where
a step names `sandbox/lib/…`, read the application's own `lib/<app>/`, and where it runs the gate
from `sandbox/`, run the application's `mix precommit`.

## Which kind

A reaction (a policy, an effect or a process manager) or a read model is declared in the contract of
the context it belongs to, beside the units, and bound by a module with `use <Contract>, <kind>: :name`.
A read model is a consumer of events, not a reaction: it decides nothing and issues nothing. Pick
the kind by what it produces:

| It… | Kind | Callback | Example |
| --- | --- | --- | --- |
| issues a command of this contract whenever an event happens | `policy` | per handled event, `(event) :: issued` | `Fulfilment.Warehouse.OpenPickListWhenPaid` |
| acts outside the log: calls a system, sends a message | `effect` | per handled event, `(event) :: :ok \| {:error, term}` | `Billing.Payments.CollectPayment` |
| steers one run over time: remembers, waits, gives up | `process_manager` | per reaction or timer that issues, `(event, state)` / `(state)`; `evolve/2` with a state | `Lending.Circulation.OverdueChase` |
| keeps rows for someone to read | `read_model` + `query` | per projected event, `(event) :: :ok`; the query `(params, ctx) :: rows` | `Lending.Membership.Directory`, `…MemberContact` |

- A policy is stateless: it sees one event and nothing else. When it needs to remember something
  between events, or to act when something does *not* happen in time, it is a process manager.
- An effect is the only kind that may touch the world outside the database. When the world's answer
  matters to the process, the effect records it as an event (`EhosContract.record/3`, as its
  `:system` actor, whose events declare `recorded_by:`), and the rest of the process reacts to that.
  A scenario that `record`s the event with that actor shows what the effect may write into the log
  (`add-event`); the effect's call itself is outside the log, so no scenario runs it.
- A read model is the client's state, projected. It holds no decision: a rule about what may happen
  belongs to a unit's invariant, never to a projection someone reads before deciding.
- An event of a sibling contract is taken through `consumes Sibling, [:event]` (K1, X5). An event of
  another application arrives through `subscribe "<name>.vN"` with the fields it reads (D11), into an
  inbox and never into this log (`EhosContract.Inbox`), so **only a policy takes it** (`D12`): a
  read model, an effect or a process manager that needs it takes the event the policy's command
  records. Its `delivery:` changes nothing for that event — the inbox runs it in the transaction that
  writes its row — and the contract then asks for `<name>.subscribe`, the application's capability.

## Delivery: what a failure leaves behind

This is the decision the kind leaves open, and it is about the log, not about speed.

**`:in_transaction`** (the default for a policy and a read model, within one context) runs inside the dispatch that
appended the event (`EhosContract.dispatch/3`, step 7): read models project, then policies react,
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
  Getting past it is a person's decision, `mix ehos_contract.subscriptions --skip` or `--reset`.
- An effect is retried, three attempts in all; what Oban keeps of a failure names the effect and
  the position, never a value.

So: `:in_transaction` when "if this did not happen, the command did not happen either" — a
projection that must be readable the moment the command returns, a policy whose command is part of
the same business step. `:at_least_once` when the reaction is a different failure domain — anything
that calls out, fans out, or may be slow. The compiler and `check` push the same way:

- `X4` refuses a bare `calls: :p1` when the domain says what `:p1` does (`operation`, plan EP5a):
  name the one this effect asks for, `calls: {:p1, :submit_report}`; `check` warns of an operation
  no effect calls (`operation-never-called`).
- `P2` refuses an effect that `calls:` an external delivered `:in_transaction`: a call cannot be
  rolled back with the append.
- `X12` refuses a read model, an effect or a process manager taking a sibling's event, or a boundary
  consulting one, across an `anticorruption_layer`: the downstream context translates first, so a policy takes the event and
  issues a command of its own context, and the others react to what that command records. `X13`
  refuses consuming an event the sibling does not `publish` across an `open_host_service` or a
  `published_language`.
- `X10` refuses a policy or a read model that takes an event of a sibling contract of another
  context and leaves `delivery` out: two contexts committing together is a choice to write down, not
  a default. `check` warns of one declared `:in_transaction` there (`in-transaction-across-contexts`);
  explain it in the pull request, or make it `:at_least_once` (a policy with its `idempotency`; a
  read model takes none). The warning covers an effect declared `:in_transaction` there too.
- `in-transaction-policy-fan-out` warns when a scenario shows an in-transaction policy issuing more
  than one command: each holds the append lock for the whole list.
- `competing-in-transaction-consumers` warns when two in-transaction policies or effects take one
  event: they run in an order the contract does not state. If one depends on the other, have it
  react to the event the other decides, so the order is a path the process shows.

## Idempotency: a second delivery must change nothing

`:at_least_once` means the reaction **will** see an event twice. `P3` makes a policy or an effect
delivered so name `idempotency:`, what makes that harmless and who keeps it so —
`[key: :event_id, owner: :self]` (plan EP4). The owner is the line of code it asks for: `:self`, this
module keys what it writes; `:downstream`, an effect passes the key to the system it calls, which
ignores a repeat (`P3` allows it on an effect only); `:infrastructure`, the engine keys it by the
event's id, as it does every command a policy issues (`P3` refuses it on an effect, whose call the
engine does not key, and on any key but `:event_id`). The callback's `@doc` repeats the owner's sentence. The library does
part of it itself, and the rest is yours:

- **A command a reaction issues is keyed by its cause**: `"policy:<contract>:<name>:<event id>:
  <index>"`, `"pm:<contract>:<name>:<source id>:<index>"`. A second delivery appends nothing, so a
  policy or a process manager needs nothing more — which is why `P3` does not ask a process manager.
- **An effect's side effect is not keyed by the library.** Pass `event.__meta__.id` on to the system
  called (`owner: :downstream`: the far end is where a second charge or a second report would be
  refused), or record the answer with an idempotency key derived from it (`owner: :self`), such as
  `"gateway-answered:#{meta.id}"`. `Billing.Payments.CollectPayment` is the first kind. The far end is where a
  duplicate e-mail is sent.
- **A read model writes the host's tables, through its `Row`.** Name the table and the row fields
  that make a row unique in the declaration (`table: "lending_member_directory", key:
  :membership_id`): `Row` is then an Ecto schema of that table, with the contract's types. Write
  through it with the key as the conflict target (`insert_all(Row, rows, on_conflict: :nothing,
  conflict_target: [:membership_id])`, as `Lending.Membership.Directory` does; a value made of
  fields is written as the struct the event carries, and read back as one), or a replay
  double-counts. The query reads `from r in Row` and answers what Ecto loads, as
  `Lending.Membership.MemberContact` does: never a `select:` map listing the fields again, nor an
  `Ecto.Schema` of your own beside the contract. A column the projection keeps for itself is a
  field of the read model too, or written by the table's name. Generate the table's migration with
  `mix ehos_contract.gen.migration <Contract> <read_model>` rather than writing its columns again,
  and keep one test that calls `EhosContract.Testing.assert_read_model_tables()`, so a field
  added later to the contract and not to the table fails in the tests.
- **Another application's event is deduplicated by the inbox**, by the message's key: the
  publisher's `idempotent_on:` values, or the message id when it declares none. A redelivery reacts
  once either way; the same event published again under a new id reacts once only when the publisher
  declares `idempotent_on:`. A publisher whose `idempotent_on:` is too
  narrow makes two real events one: when you write the `publish`, name the fields that make one event,
  not merely some that identify it.

## Where a new consumer starts

What is in the log when a consumer is first registered is history, and nothing new reacts to
history by itself (`EhosContract.Subscription`, "Where a new consumer starts"):

- a new policy starts at the head of the log: a deploy onto a year of history issues nothing for
  that year;
- a new process manager replays with its reactions suppressed: it learns the runs already there and
  steers none; a timer of theirs already due is dropped;
- an ordered read model starts at position 0; an inline one at the head, and one added to a log
  that already has its events is rebuilt by hand;
- a read model whose declaration or events change is `stale` until rebuilt (a label or a `source:`
  alone changes neither), and rebuilding needs its
  optional `reset/0`; without it, it stays stale. A process manager that changes is `stale` too, and
  is rebuilt at boot, since the library owns its table. One projecting personal fields needs `forget/2` or
  the engine will not boot
  (`docs/adr/contract-v2.md` §14).

Reacting to history is a person's `--reset`, never a side effect of a deploy. If the change needs
it, say so in the pull request.

Another application's history does not come over the bus at all: an inbox's consumer gets what is
published once the transport delivers to it — between nodes, from EHOS's grant of `<name>.subscribe`
on — and the engine starts every inbox before any relay, so in one node nothing is published past
it. What was published before is asked of its owner, the application that published it.

## A process manager, in particular

- `correlate` names the run. An event it takes that lacks those fields joins no run and is passed
  over, and nothing refuses it at compile time for a local event (`F4` only refuses them optional
  or personal; `X6` checks a sibling's): check each event it names carries them.
  Its state holds no personal data (`F7`): it lives outside the log, where erasure cannot reach.
- A timer's label is required and names what the timer is for, "Reminder", never how
  long it waits, "Three days later": `wait:` or `at:` says when, the pages print it beside the
  label, and a label that says it drifts the day someone changes `wait:` (plan N3).
- A timer fires `wait:` after the event that set it, or `at:` a `:timestamp` of its state. The
  firing is an event in the log, so a timer fired twice dispatches once, and a replay recomputes the
  same timers.
- Declare `ends_on` (`process-manager-without-ends-on`), or every run stays open for ever with its
  state kept. A manager that reacts only to its own timers (`process-manager-without-event-reactions`)
  is a schedule, and may be simpler as one.
- A timer that issues is a callback of the state alone: whatever the command needs — the run's
  correlation is injected — has to be in the state by then.

## Procedure

1. Name what the reaction produces, and pick the kind from the table. Name the rules it keeps as
   `constraint`s in its declaration (a process manager's also as `invariant`s), from the material
   with `source:`, rather than leaving them in the label or the code (plan EP2).
2. Pick `delivery` from what a failure must leave in the log. Write the reason in the moduledoc,
   one line, so the next reader does not re-derive it.
3. If `:at_least_once`, name `idempotency`, and make the effect's or projection's own writes keyed by
   the event.
4. Declare it in the contract, then a scenario for it: an `on` event with the `issues` it expects
   for a policy or a process manager — and for a process manager whose `evolve/2` decides something
   no command shows, the `state` its run holds after the event, one scenario per branch, as
   `monthly_billing` has for a date moved on and a date left be — a `query` with `answers`
   for a read model
   (`reaction-without-scenario`). Give every rule a scenario that names it in `illustrates:` —
   one for each way the rule decides, as `book_carrier` has one for a parcel and one for
   freight — before the code: the scenario is the test the implementation is written
   against, and a rule without one is prose alone (`prose-without-scenario`). An effect has no
   scenario (`S6`): its constraints stay prose, and its test is yours.
5. Bind the module (`use <Contract>, policy: :name`), compile, and add what `I2` asks for. `issue/1`
   takes command struct literals within the declaration's `issues:`, one, a list of them, or a `for`
   producing them; a `for` with `into:` or `reduce:` is refused (`I4`, `I6`). Each callback's
   generated doc (`b <Contract>.Policies.<Name>.<event>` in IEx) lists what it may issue, the rules it
   keeps with the scenarios that illustrate them, and its scenarios (plan EP3); a rule it names is
   not restated in the module's moduledoc.
6. Test what runs after the commit with `config :ehos_contract, subscriptions: :manual` and
   `EhosContract.Testing.drain/1`. The first `drain/1` is the deploy. For a policy or a process
   manager, drain once before dispatching what it takes, or it treats that event as history and does
   nothing. An ordered read model starts at position 0, so its first `drain/1` projects what the log
   already holds.
7. Run the gate from `sandbox/` and read any new `check` line naming the reaction.

## Not this skill

The unit that decides a policy's command — `write-decider`. Declaring the event it reacts to —
`add-event`. Whether a reaction belongs in the contract, or is a plain function call —
`module-boundary-check`. Changing a reaction that already runs against history — `change-contract`,
because a changed declaration marks a read model stale and moves the contract's version.
