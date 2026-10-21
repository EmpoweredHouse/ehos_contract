# Reactions: policies, effects and process managers

What happens because something else happened: the 3 kinds of reaction a contract declares, when each
runs, what a failure leaves in the log, and how a second delivery is made harmless.

<!-- covers: entities contract.policy, contract.effect, contract.process_manager, contract.process_manager.timer, contract.process_manager.starts_on, contract.process_manager.on, contract.process_manager.ends_on; rules in-transaction-policy-fan-out, competing-in-transaction-consumers, process-manager-without-ends-on, process-manager-without-event-reactions, event-without-consumer, backward-edge -->

A unit decides; a reaction follows. Every reaction is declared in the contract beside the units, takes events
of this contract or of a sibling it `consumes`, and is bound by a module of its own, `use <Contract>, policy:
:name`, as a unit is. A policy may also take an event this contract `subscribe`s to from another
application, from its inbox ([between contracts](between-contracts.md)). The fourth kind of consumer, a read model with the query that reads it, keeps rows for
someone to read and decides nothing; it has [its own page](reading.md).

## Which kind

Pick the kind by what the reaction produces.

| It… | Kind | Its callback |
| --- | --- | --- |
| issues a command of this contract whenever an event happens | `policy` | one per event it handles, `(event)`, returning what it `issue`s |
| acts outside the log: calls a system, sends a message | `effect` | one per event it handles, `(event)`, returning `:ok` or `{:error, reason}` |
| steers one run over time: remembers, waits, gives up | `process_manager` | one per reaction or timer that issues, `(event, state)` or `(state)` |

- **A policy is stateless.** It sees one event and nothing else, and the command it issues is decided by that
  command's unit like any other: a rejection is the unit's answer. A policy that needs to remember something
  between events, or to act when something does *not* happen in time, is a process manager.
- **An effect is the only kind that touches the world outside the database.** When the world's answer matters
  to the process, the effect records it as an event, through `EhOsContract.record/3` as a `:system` actor the
  domain declares, and the rest of the process reacts to that event. An effect names the external systems it
  calls, `calls: {:mailer, :send_reminder}`: the external and, when the domain lists what it does, one of its
  operations.
- **A process manager steers a run.** `correlate` names the fields that tell one run from another; it
  `starts_on` an event, reacts `on` later events and on its own timers, sets and cancels timers, and ends on an
  `ends_on` event. Its `state` is what it remembers between steps, folded by `evolve/2` as a unit's is.

The keys of each are in the reference: [policy](../dsl/contract-policy.md), [effect](../dsl/contract-effect.md),
[process manager](../dsl/contract-process_manager.md).

## An example

A loan is closed when its copy comes back; a month after it is opened, unless the copy is back, it is
marked overdue, and the member is sent a reminder.

```elixir
defmodule Concepts.Reactions.Domain do
  use EhOsContract.Domain, name: :reactions_example, language: :en

  subdomain :core, "Core", type: :core
  context :loans, "Loans", subdomain: :core
  actor :librarian, :human, "Librarian"

  external :mailer, "Mail service", direction: :outbound do
    operation :send_reminder, "Send a member a reminder"
  end
end
```

```elixir
defmodule Concepts.Reactions.Contracts.Loans do
  use EhOsContract.Contract,
    domain: Concepts.Reactions.Domain,
    context: :loans,
    id: "reactions_example.loans"

  aggregate :loan, "Loan of a copy" do
    identity :loan_id

    command :open_loan, "Lend a copy", by: :librarian, emits: :loan_opened do
      field :member_id, :id
    end

    command :return_copy, "Take a copy back", by: :librarian, emits: :copy_returned

    # Issued by the reactions below, never by a person, so no `by:`.
    command :close_loan, "Close the loan", emits: :loan_closed
    command :mark_overdue, "Mark the loan overdue", emits: :loan_marked_overdue

    event :loan_opened, "Copy lent" do
      field :member_id, :id
    end

    event :copy_returned, "Copy returned"
    event :loan_marked_overdue, "Loan overdue"
    event :loan_closed, "Loan closed"
  end

  policy :close_on_return, "A returned copy closes its loan",
    handles: :copy_returned,
    issues: :close_loan

  effect :remind_member, "Remind the member of an overdue loan",
    handles: :loan_marked_overdue,
    calls: {:mailer, :send_reminder},
    idempotency: [key: :event_id, owner: :downstream]

  process_manager :overdue_watch, "Watching a loan for its return" do
    correlate :loan_id

    starts_on :loan_opened, sets: :due
    on :copy_returned, cancels: :due

    timer :due, "Return date", wait: {30, :day}, issues: :mark_overdue

    ends_on :loan_closed
  end

  scenario "a returned copy closes its loan" do
    target :close_on_return
    on :copy_returned
    issues :close_loan
  end

  scenario "a month without the copy marks the loan overdue" do
    target :overdue_watch
    given :loan_opened, %{member_id: "m-1"}
    on :due
    issues :mark_overdue
  end
end
```

The policy's module has one callback per event it handles, named after the event, and `issue/1` takes the
literal structs of the commands its `issues:` names:

```elixir
defmodule Concepts.Reactions.CloseOnReturn do
  use Concepts.Reactions.Contracts.Loans, policy: :close_on_return

  @impl true
  def copy_returned(%CopyReturned{loan_id: id}), do: issue(%CloseLoan{loan_id: id})
end
```

## Delivery: what a failure leaves in the log

`delivery` is not about speed. It says whether the reaction belongs to the same step of the business as the
event it takes, and so what is left in the log when the reaction fails.

**`:in_transaction`** runs inside the dispatch that appended the event, before it commits. It is the default
for a policy (and a read model). Dispatch runs every `:in_transaction` consumer that takes the event, in any
contract of the application: read models first, then policies, then effects. What a policy issues is
dispatched at once, in the same transaction.

- An exception in the reaction, or an effect's `{:error, reason}`, **rolls back the command that caused
  it**: the person's command fails for a reason that is not theirs. When dispatch owns the transaction it
  writes a `failed` row naming where it failed and the exception's module.
- A rejection of the command a policy issues is the unit's answer, not a failure: the first command stands.
- If a policy, further down the same chain, reacts again to a kind of event it already reacted to, that is a
  cycle, and dispatch raises.
- Every such reaction runs while the transaction holds the store's global append lock, so every other
  append waits for it.

**`:at_least_once`** runs after the commit. It is the default for an effect and the only delivery of a process
manager. A policy delivered so is an ordered subscription to the log: 1 event per step, each step in its own
transaction. An effect is an Oban job, inserted in the transaction that appends the event and holding only the
effect's key and the event's id. A process manager is an ordered subscription too.

- The triggering event stays in the log whatever the reaction does.
- An event a subscription fails on is retried; after 3 attempts the subscription is `failing` at that
  event and **stops there**. It never skips by itself: moving it on is a person's decision,
  `mix eh_os_contract.subscriptions --skip` or `--reset`.
- An effect's job is retried, 3 attempts in all. What Oban keeps of a failure names the effect and the
  event's position, never a value, since a value may be personal data.

So `:in_transaction` fits when "if this did not happen, the command did not happen either": a policy whose
command is part of the same business step. `:at_least_once` fits when the reaction is a different failure domain:
anything that calls out, fans out, or may be slow. An effect that calls an external system is always
`:at_least_once`, since a call cannot be rolled back with the append.

## Idempotency: a second delivery changes nothing

Delivered `:at_least_once`, a reaction **will** see an event twice. A policy or an effect delivered so names
`idempotency:`: the key that makes a second delivery harmless, and who keeps it so.

- **`owner: :infrastructure`**: the engine. Every command a policy or a process manager issues is keyed by
  its cause, `"policy:<contract id>:<name>:<event id>:<index>"` or `"pm:<contract id>:<name>:<event id>:<index>"`,
  so a second delivery appends nothing. That is why a process manager names no `idempotency`, and why a
  policy needs nothing more than `[key: :event_id, owner: :infrastructure]`.
- **`owner: :downstream`**: an effect passes the key to the system it calls, which ignores a repeat. The
  key is the event's `__meta__.id`.
- **`owner: :self`**: the reaction's own code keys what it writes: an effect that records the answer it got
  passes an idempotency key derived from the event's id to `EhOsContract.record/3`.

The engine does not key an effect's call to the world. That is the far end, where a duplicate e-mail would be
sent, and `idempotency:` is where the contract says who stops it.

## Where a new reaction starts

What is in the log when a reaction is first deployed is history, and nothing new reacts to history by itself:

- **A new policy delivered `:at_least_once` starts at the head of the log.** A deploy onto a year of history
  issues nothing for that year.
- **A new process manager replays the log with its reactions suppressed.** It learns the runs already there
  and steers none of them; a timer of theirs that came due before the deploy is dropped.
- **An effect has no position.** Its job is inserted by the dispatch that appends the event, so it acts on
  events appended once it is deployed.

Reacting to history is a person's `mix eh_os_contract.subscriptions --reset`, never a side effect of a deploy.
A policy reset to the start of the log derives the same keys from each event, so what it issued before is not
issued twice.

## Timers

A timer fires `wait:` after the event that set it, or `at:` a `:timestamp` field of the manager's state. A
reaction `sets:` it and `cancels:` it, and an `ends_on` event ends the run and forgets every timer it has.

The firing is an event in the run's own stream, which the process manager takes in order with everything
else. A timer fired twice dispatches once, and a replay sees each firing where it happened. The callback of a timer
that issues receives only the state: whatever its command needs, beyond the run's correlation, has to be
in the state by then.

A timer's label says what the timer is for, "Return date", not how long it waits: `wait:` or `at:` says when,
and a label that repeats it drifts the day someone changes it.

An event the manager takes that lacks its `correlate` fields joins no run and is passed over, and for a
local event nothing refuses that at compile time: check that each event it names carries them. Its state
holds no personal data ([`F7`](../contract.md#refusals-f)): it lives outside the log, where erasure cannot reach it.

## What the compiler refuses

- A policy or an effect taking an event that is neither this contract's nor consumed, or a policy issuing a
  command of another contract ([`P1`](../contract.md#refusals-p)). Issue a command of this contract; another context's unit is reached
  through its own policy.
- An effect with `calls:` delivered `:in_transaction` ([`P2`](../contract.md#refusals-p)): deliver it `:at_least_once`.
- A policy or an effect delivered `:at_least_once` without `idempotency`; `owner: :downstream` outside an
  effect; `owner: :infrastructure` on an effect, or on a key other than `:event_id` ([`P3`](../contract.md#refusals-p)).
- A process manager that starts on nothing, has an empty `correlate`, or is delivered `:in_transaction`; a
  trigger that is neither an event it may take nor its own timer; a timer without exactly one of `wait:` and
  `at:` ([`P4`](../contract.md#refusals-p)).
- A timer's `wait:` that is negative, malformed, or longer than 100 years, a year counted as 366 days and a
  month as a twelfth of that ([`R6`](../contract.md#refusals-r)): a timer longer than a century is a mistake in the contract.
- A command no actor may issue and no reaction issues ([`C1`](../contract.md#refusals-c)).
- In a module: `issue/1` given anything but struct literals of the commands its `issues:` names ([`I4`](../contract.md#refusals-i), [`I6`](../contract.md#refusals-i)).

## What `mix eh_os_contract.check` reports

- `in-transaction-policy-fan-out` (warning): a scenario shows an in-transaction policy issuing more than one
  command, each while the append lock is held. Deliver it `:at_least_once`.
- `competing-in-transaction-consumers` (warning): 2 policies or effects take one event inside its
  transaction, in an order the contract does not state. If one depends on the other, have it react to the
  event the other decides.
- `process-manager-without-ends-on` (warning): every run stays open for ever, with its state. Declare
  `ends_on`.
- `process-manager-without-event-reactions` (warning): after it starts, the manager reacts only to its own
  timers, so the process can end it but not steer it. It is a schedule, and may be simpler as one.
- `event-without-consumer` (warning): nothing reacts to or reads an event: no reaction, read model,
  boundary, consuming contract or `publish`, and no lifecycle or process module that the conformance
  report reads. Add the reader it was declared for, or ask whether it is needed.
- `backward-edge` (warning): a policy or a process manager reacting to an event that one stage of a
  [process module](process.md) includes issues a command whose events sit in an earlier stage of it. Either
  the stages are in the wrong order or the reaction is a loop the process has not declared.

All of the rules are in [the catalogue](../rules.md). Reactions to another context's events, and to another
application's, are on [their own page](between-contracts.md).
