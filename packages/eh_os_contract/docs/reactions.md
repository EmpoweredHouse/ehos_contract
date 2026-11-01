# What is a reaction?

<!-- covers: entities contract.policy, contract.effect, contract.process_manager, contract.process_manager.timer, contract.process_manager.starts_on, contract.process_manager.on, contract.process_manager.ends_on; rules in-transaction-policy-fan-out, competing-in-transaction-consumers, process-manager-without-ends-on, process-manager-without-event-reactions, event-without-consumer, backward-edge -->

This page tells what the three kinds of reaction are, and when each one runs. It also tells what a
failure leaves in the log, and how a second delivery changes nothing. It is for a developer who declares reactions in
a contract. [The glossary](glossary.md) defines each word in italics.

## What does a reaction do?

A unit decides. A *reaction* does something because an event occurred. The contract declares each
reaction beside its units, and a module of its own implements it:
`use <Contract>, policy: :name`.

A reaction takes the events of its own contract. It can also take the events of another contract
of the same domain, if its contract `consumes` them. A policy can also take an event of
another application from the inbox. [How does an event reach another contract?](between-contracts.md)
tells how.

Choose the kind by what the reaction makes:

| The reaction… | Kind | Its callback |
| --- | --- | --- |
| issues a command of this contract each time that an event occurs | `policy` | one for each event, `(event)`, which returns what it `issue`s |
| acts outside the log: it calls a system, or sends a message | `effect` | one for each event, `(event)`, which returns `:ok` or `{:error, reason}` |
| steers one run over time: it remembers, waits, and stops | `process_manager` | one for each reaction or timer that issues, `(event, state)` or `(state)` |

A read model also takes events, but it is not a reaction: it keeps rows for a reader and decides
nothing. [What are read models and queries?](reading.md) tells about it.

The references list each key: [`policy`](dsl/contract-policy.md),
[`effect`](dsl/contract-effect.md) and [`process_manager`](dsl/contract-process_manager.md).

## An example

A librarian lends a copy. When the copy comes back, its loan closes. If the copy is not back after
30 days, the loan is overdue, and the member gets a reminder.

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

The module of the policy has one callback for each event that it handles. The callback has the
name of the event:

```elixir
defmodule Concepts.Reactions.CloseOnReturn do
  use Concepts.Reactions.Contracts.Loans, policy: :close_on_return

  @impl true
  def copy_returned(%CopyReturned{loan_id: id}), do: issue(%CloseLoan{loan_id: id})
end
```

`issue/1` takes only the struct literals of the commands in `issues:`
([`I4`](refusals.md#refusals-i), [`I6`](refusals.md#refusals-i)).

## What does each kind do?

**A policy has no state.** It sees one event and nothing else. The unit of the command decides
the command, as it decides any other command. If the unit rejects it, that is the answer of the
unit. A policy issues only the commands of its own contract ([`P1`](refusals.md#refusals-p)). To
reach a unit of another contract, that contract consumes the event and has its own policy.
A command without `by:` needs a reaction that issues it ([`C1`](refusals.md#refusals-c)).

If a policy must remember something between events, or must act when an event does *not*
occur in time, use a process manager.

**An effect is the only kind that acts outside the database.** It names the external systems that
it calls, such as `calls: {:mailer, :send_reminder}`. If the domain lists the operations of the
system, the effect also names one operation. If the answer of the system is important to the process, record it as
an event. Call `EhOsContract.record/3` with a `:system` actor that the domain declares. The rest of
the process then reacts to that event.

**A process manager steers a run.** A *run* is one case of a process, such as one loan.

- `correlate` names the fields that tell one run from another.
- `starts_on` names the event that starts a run.
- `on` names a later event that it reacts to. It can also react to its own timers.
- `ends_on` names the event that ends the run.
- Its `state` is what it remembers between steps. `evolve/2` folds it, as for a unit.

A run that ended cannot start again with the same values of its `correlate` fields.

<a id="where-does-each-reaction-run"></a>

## Where does each reaction run?

The *delivery* of a reaction tells when it runs. It does not make the reaction faster. It tells
what the log keeps when the reaction fails.

![A consumer delivered in the transaction fails the command with it; a subscription or an Oban job runs after the commit, and its failure leaves the event in the log.](img/reaction-delivery.svg)

1. Dispatch runs each consumer delivered `:in_transaction` before it commits.
2. If one of them fails, the command fails with it.
3. If none fails, dispatch commits. The log keeps the event.
4. A *subscription* reads the log in order, after the commit.
5. If a subscription fails 3 times on one event, it stops at that event.
6. In the same transaction, dispatch inserts an Oban job for each effect delivered
   `:at_least_once`.
7. If the job fails 3 times, Oban discards it.

| Kind | Delivery if you leave it out | Can it run `:in_transaction`? |
| --- | --- | --- |
| `policy` | `:in_transaction` | yes |
| `effect` | `:at_least_once` | yes, if it has no `calls:` ([`P2`](refusals.md#refusals-p)) |
| `process_manager` | `:at_least_once` | no ([`P4`](refusals.md#refusals-p)) |

### What occurs in the transaction?

`:in_transaction` runs the reaction in the dispatch that appended the event, before the commit.

- Dispatch runs each consumer delivered `:in_transaction` that takes the event. It looks in each
  contract of the applications in `config :eh_os_contract, applications:`, and of the application
  of the contract.
- The read models run first, then the policies, then the effects.
- Dispatch dispatches each command that a policy issues at once, in the same transaction.
- If a policy in the same chain reacts again to an event type that it reacted to before, that is
  a cycle. Dispatch raises.
- All these reactions run while the transaction holds the append lock of the log. Every other
  append waits.

If a reaction raises, or an effect returns `{:error, reason}`, the transaction rolls back. The
command that caused it fails, for a reason that is not the fault of the person who sent it. If
dispatch owns the transaction, it writes a row with the status `failed`. The row names the step
that failed and the module of the exception.

If the unit rejects the command of a policy, that is not a failure: the first command stays. The
same is true if the command of a policy is refused because its subject was erased.

### What occurs after the commit?

`:at_least_once` runs the reaction after the commit. The event stays in the log, whatever the
reaction does.

- **A policy or a process manager** reads the log through a subscription. The subscription takes
  one event in each step, and each step has its own transaction. Each step holds the append lock,
  because it dispatches commands.
- **An effect** is an Oban job in the queue `:events`. Dispatch inserts the job in the transaction
  that appends the event. The job holds the name of the effect, the id of the event and the name
  of the application, and no value of the event.

If a subscription fails on an event, it tries the event again, after a pause of up to 30 seconds.
After 3 attempts, the status of the subscription is `failing`. It stops at that event.

- A `failing` subscription does not try again by itself. A restart of the host does not start it,
  unless the declaration of a read model or a process manager changed.
- It never skips the event by itself. A person decides what to do.
  [Repair or replay a subscription](subscriptions.md) tells how.

Oban makes 3 attempts at the job of an effect. After the last attempt, Oban discards the job, and
the engine does nothing more. The conformance report shows the discarded job. What Oban keeps of a
failure names the effect and the position of the event, never a value: a value can be personal
data.

> **Oban must use the repo of dispatch.**
> Configure Oban with the same repo as the engine. Dispatch inserts the jobs in its own
> transaction. With another repo, dispatch raises an `ArgumentError`.

### Which delivery do I choose?

Use `:in_transaction` if the command did not occur when the reaction did not occur. An example is
a policy whose command is part of the same step of the business.

Use `:at_least_once` if a failure of the reaction must not fail the command. This is a reaction
that calls a system, issues many commands, or can be slow. An effect that calls an external system
is always `:at_least_once`, because the engine cannot roll back a call.

A policy that takes an event of another context must say its delivery.
[How does an event reach another contract?](between-contracts.md#delivery-across-contexts) tells
why.

## How does a second delivery change nothing?

A reaction delivered `:at_least_once` **will** see some events two times. A policy or an effect
delivered so declares `idempotency:`. It names the key that tells a second delivery from the first,
and who keeps the key ([`P3`](refusals.md#refusals-p)).

| `owner:` | Who stops the second delivery | For |
| --- | --- | --- |
| `:infrastructure` | the engine; the key is `:event_id` | a policy |
| `:downstream` | the system that the effect calls; the effect gives it the key | an effect |
| `:self` | the code of the reaction; it keys what it writes | a policy or an effect |

**The engine keys each command that a reaction issues.** The key comes from the cause of the
command:

- `"policy:<contract id>:<name>:<event id>:<index>"` for a policy;
- `"pm:<contract id>:<name>:<event id>:<index>"` for a process manager.

If a key is longer than 255 bytes, the engine uses a hash of it. When the unit accepts the command,
the key stays with its events. A second delivery with the same key appends nothing. A process
manager needs no `idempotency` for this reason, and a policy needs only
`[key: :event_id, owner: :infrastructure]`.

> **A rejected command has no key.**
> If the unit rejected the command, a second delivery decides it again. The answer can change if
> the unit changed in between.

**For `:downstream`**, the effect gives the key to the system that it calls. The system ignores a
call that it already took. With `key: :event_id`, the key is the `__meta__.id` of the event.
`key:` can also name a field of the event.

**For `:self`**, the code keys what it writes. Example: an effect records the answer that it got.
It gives `EhOsContract.record/3` an idempotency key that it makes from the id of the event.

The engine does not key the call of an effect to the world. A second e-mail is sent at the far
end. `idempotency:` is where the contract says who stops it. The engine does not read
`idempotency:` at run time.

## Where does a new reaction start?

The log can hold events from before a reaction was deployed. These events are history. A new
reaction does not react to history by itself.

- **A new policy delivered `:at_least_once` starts at the head.** If you deploy it onto a year of
  history, it issues nothing for that year.
- **A new process manager reads the log with its reactions turned off.** It learns the runs that
  exist, and steers none of them. It drops each timer of these runs that was due before the
  deploy.
- **An effect has no position.** Dispatch inserts its job when it appends the event. The effect
  acts only on events appended after the deploy.

To make a new policy react to history, a person resets it:
[Repair or replay a subscription](subscriptions.md). The policy makes the same keys from each event
again, so it issues no accepted command two times. A reset of a process manager issues nothing for
history.

> **A change to a process manager forgets its runs.**
> If you change its declaration, the engine marks it `stale` at the next boot. It then forgets every run and reads the log again, with its reactions turned off. It
> keeps only the timers that are not due yet, or that still have a job.

## How does a timer work?

A reaction `sets:` a timer and `cancels:` it. The timer fires at one of these times:

- `wait:` after the event that set it. The wait counts from the time of that event. Weeks,
  months and years follow the calendar, in UTC.
- `at:` a `:timestamp` field of the state, after `evolve/2` took the event. If the field is `nil`,
  the subscription fails at that event.

A `wait:` longer than 100 years is a mistake in the contract, and the compiler refuses it
([`R6`](refusals.md#refusals-r)).

If a reaction sets a timer again, the new time replaces the old one. An `ends_on` event ends the
run, and the run forgets all its timers.

The firing is an event in the stream of the run. The process manager takes it in order, with the
other events. If the job of one timer runs two times, it can append two firings. The process
manager dispatches the command one time. When the log is read again, each firing is where it
occurred.

The callback of a timer gets only the state. Put in the state what the command needs, apart from
the `correlate` fields.

Give a timer a label that says what it is for, such as "Return date". Do not say how long it
waits: `wait:` or `at:` says that. A label that repeats the time is wrong after a change to it.

> **Check that each event carries the `correlate` fields.**
> An event without them joins no run, and the process manager passes over it. For an event of
> this contract, the compiler does not refuse this.

The state of a process manager holds no personal data ([`F7`](refusals.md#refusals-f)). It is kept
outside the log, where an erasure does not reach it.

## What does the check say about a reaction?

`mix eh_os_contract.check` gives these warnings. [The rules](rules.md) list all of them.

- `in-transaction-policy-fan-out`: a scenario shows a policy delivered `:in_transaction` that
  issues more than one command. Each command holds the append lock. Deliver it `:at_least_once`.
- `competing-in-transaction-consumers`: two policies or effects take one event in its transaction,
  and the contract does not say their order. If one needs the other, make it react to the event
  that the other one decides.
- `process-manager-without-ends-on`: each run stays open, with its state, for ever. Declare
  `ends_on`.
- `process-manager-without-event-reactions`: after it starts, the process manager reacts only to
  its own timers. The process can end it, but cannot steer it. A schedule can be simpler.
- `event-without-consumer`: nothing reacts to the event or reads it. No reaction, read model,
  boundary, consuming contract or publication takes it. No lifecycle or process module that the
  conformance report reads includes it. Add the reader that it is for, or ask if the event is
  necessary.
- `backward-edge`: a policy or a process manager reacts to an event in one stage of a
  [process module](process.md). It issues a command whose events are in an earlier stage. The
  stages are in the wrong order, or the process has a loop that it does not declare.

## Next steps

- [Repair or replay a subscription](subscriptions.md): what to do when a reaction stops at an event.
- [What are read models and queries?](reading.md): the consumer that keeps rows for a reader.
- [How does an event reach another contract?](between-contracts.md): reactions to the events of
  another context and of another application.
- [What is a scenario?](scenarios.md): how the scenarios test a reaction.
- [The compile refusals](refusals.md#refusals-p): each refusal of a reaction, in the families P, R,
  C and I.
