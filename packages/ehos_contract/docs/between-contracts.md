# How does an event reach another contract?

<!-- covers: entities contract.consumes, contract.publish, contract.subscribe; rules in-transaction-across-contexts -->

This page tells how an event of one contract reaches another contract. In the same application, it
comes from the same log. In another application, it comes through a publication and an inbox. It is for a
developer who connects contracts. [The glossary](glossary.md) defines each word in italics.

## Which way does an event go?

The way depends on where the other contract is:

| Where the other contract is | It takes the event with | Where the event is | What can take it |
| --- | --- | --- | --- |
| in the same application and the same domain | `consumes Sibling, [:event]` | in the log of this application | a reaction, a read model, a boundary that consults it, a stage of a process |
| in another application | `subscribe {namespace, publication, version}`, with the fields that it reads | in the inbox of the subscriber, never in its log | a policy only |

The contracts of one application share one log. So the event of a sibling contract is a row that
the consumer can read. Another application has its own log. Its events leave it only through a
`publish`.

## How does a contract take the events of a sibling?

`consumes` names a sibling contract of the same domain, and the events that this contract takes
from it. The reference is [`consumes`](dsl/contract-consumes.md).

- After `consumes`, the contract names the event by its name alone. Examples: `handles:`,
  `starts_on`, `consults` and `include`.
- If the name of the event is the same as a local name, `as: [old: :new]` gives it a new name.
- The sibling defines the event. `consumes` declares no fields.
- The compiler reads the sibling as it is now. A change to the event of the sibling reaches each
  contract that consumes it at the next compile.

The contract names the module of the sibling without a compile dependency. The Mix compiler
`compile.ehos_contract` checks the link instead:

- The sibling is a compiled contract of the same domain, and it declares each event that this
  contract names ([`X5`](refusals.md#refusals-x)).
- Some fields tell one run or one boundary from another: a `correlate` field, or the `match:` of a
  boundary. Each such field is in the event of the sibling, with the same type. It is not optional
  and not personal ([`X6`](refusals.md#refusals-x)).

`consumes` takes only a contract of this domain ([`X5`](refusals.md#refusals-x)). The events of
another domain come only through `subscribe`. `consumes` also refuses a published name, the
contract itself, no events, a new name for an event that it does not consume, and fields
([`K1`](refusals.md#refusals-k)).

<a id="delivery-across-contexts"></a>

### Which delivery does a reaction to another context need?

A sibling can be in the same context, or in another context.

A policy or a read model without `delivery` runs `:in_transaction`, in the dispatch that appends
the event. For a sibling in the same context, this is usually correct: one step of the business,
committed one time.

For a sibling in **another context**, `:in_transaction` makes the two contexts commit together. If
the policy or the read model fails, the event of the other context rolls back. The command of a
person in one context fails because of a fault in another context.

So a policy or a read model that takes an event of another context declares its delivery, or the
contract does not compile ([`X10`](refusals.md#refusals-x)).

- Usually the delivery is `:at_least_once`. A policy then names its `idempotency`. A read model
  names none.
- An effect and a process manager already run `:at_least_once` if you leave out `delivery`.

[What is a reaction?](reactions.md#where-does-each-reaction-run) tells what a failure of each
delivery leaves.

## How does a field name a unit of a sibling?

A contract often keeps the number of a thing that a sibling decides. Example: the settlement of a
clinic keeps the visit that the booking contract made. The type of the field says so, as it says
which entity a field names: `field :visit_id, {:id, :visit}`. A unit with that number as its key
says it in its identity: `identity visit_id: {:id, :visit}`.

The name must match exactly one unit of the contracts of the domain, or one entity of the domain.
If it matches none, or more than one, the contract does not compile ([`X3`](refusals.md#refusals-x)).

> **Compile the contracts of a domain in one project.**
> The compiler looks for the unit only in the project that it compiles. It does not
> see a unit whose contract is in a dependency, and refuses a correct reference to it. If such a
> unit has the same name as an entity of the domain, the reference goes to the entity, without a
> refusal. The pages and the context map then point at the entity.

A reference carries no event. It tells what a number means:

- The pages link the field to the unit.
- `mix ehos_contract.check` counts the reference as a dependency of this context on the context
  of the sibling. The context map relates the two, in the direction of the reference. If no
  relation is declared, the check warns. A relation in the other direction, or `:separate_ways`, does
  not compile ([`X11`](refusals.md#refusals-x)).
- To react to what occurs to the visit, consume its events. To decide on them, consult them from a
  boundary.
- A command does not read a unit of a sibling as it reads an entity, because the state of a unit
  is its events.

## How does an event leave the application?

An event leaves the application only through `publish`. The publication names a local event, the
fields that it carries, and the version of these fields. The event that goes out is an
*integration event*:

<!-- in: Concepts.Between.Contracts.Loans -->
```elixir
publish :loan_opened,
  version: 1,
  from: :loan_opened,
  fields: [:loan_id, :copy_id],
  idempotent_on: [:loan_id]
```

- **The library builds the published name.** The name is the `name:` of the domain, the name of
  the publication and the version: `between_example.loan_opened.v1`. The name of a publication is
  in snake_case. Two publications of one application cannot have the same name.
- **The name and its fields are a promise to other applications.** `version:` is 1 if you leave
  it out. To remove a field or to change its type, raise the version. The new version is a new
  name, and each subscriber moves to it. To add a field, keep the version.
  [`mix ehos_contract.schema`](event-versions.md#what-does-a-publication-promise) records the
  fields of each publication and refuses a change that breaks this promise.
- **`fields:` lists fields of the event, and none is personal.** An erasure cannot reach a copy
  on a broker. The identity of a unit, or an `:id` that names a
  person, goes out in clear text, as the log keeps it.
- **`idempotent_on:` names the fields that make one event**, from `fields:`. Their values are the
  key of the message. With the key, a subscriber finds the same event that was published again
  with a new id. Name all the fields that make one event. A key that is too narrow makes two real
  events into one.
- If you leave out `idempotent_on:`, or one of its values is `nil`, the key is the id of the
  message: `<event id>/<published name>`.

[The compile refusals](refusals.md#refusals-d) list what the compiler refuses in a publication
([`D11`](refusals.md#refusals-d)). The reference is [`publish`](dsl/contract-publish.md).

## What occurs from a publication to the policy's command?

![The relay of the publisher hands each event to the bus, and the inbox of the subscriber runs the policy in one transaction before it acknowledges the message.](img/publication-to-policy.svg)

1. After the commit, the *relay* reads the events of the publication from the log of the
   publisher.
2. The relay hands a batch of messages to the *bus*.
3. The bus confirms that it holds the batch. Only then does the relay move its position.
4. Later, the bus delivers each message to the *inbox* of the subscriber.
5. In one transaction, the inbox writes its row and runs each policy that handles the event.
6. The policy issues its commands. Dispatch decides them, as for each command of a policy.
7. After the transaction commits, the inbox acknowledges the message.

### What does the relay do?

The relay is a subscription to the log, one for each `publish`. The log is the outbox, and there
is no outbox table.

- A step reads up to 100 events of the publication, and makes a message from each.
- If the relay stops after step 2 and before step 3, it publishes the batch again, under the same
  ids. So a message can arrive two times. It never arrives without its event in the log. It arrives
  zero times only in four cases:
  - the event was in the log before the `publish` was deployed, and nobody resets the relay;
  - a person skips the event on the relay, after the relay is `failing` at it;
  - the `publish` gets a new name;
  - a broker that keeps nothing, such as `EhosContract.Bus.Local`, restarts.
- **It starts at the head of the log**, as a policy does. The events in the log when the
  publication is first deployed are history, and the relay does not publish them by itself. To
  publish them, a person resets it: [Repair or replay a subscription](subscriptions.md).
- **A broker that is not available stops nothing.** The position stays, the relay counts no
  attempt, and it tries again later.
- **Without a bus**, the relay waits. When a bus is configured, it publishes all events since its
  position.
- **The relay has the name of the `publish`, not its version.** A new name of the declaration
  starts a new relay at the head. What the old relay did not publish never
  leaves.
- The relay sends each field as the log keeps it. A field that was personal in an older version
  of the event leaves encrypted. An identity leaves in clear text, also after its subject is
  erased.
- If the relay raises on an event 3 times, it is `failing`, and it stops at that event.

Configure the bus in the host:

<!-- not compiled: the host's configuration -->
```elixir
config :ehos_contract, bus: {EhosContract.Bus.Local, []}
```

The library supplies `EhosContract.Bus.Local`, for tests and for one node. The platform supplies a
transport between nodes as an adapter. The library depends on no broker.

## How does an application subscribe?

The subscriber names the event by the parts of its published name: the namespace of the
publisher, the name of the publication and the version. It gives the event a name in this
contract, and lists the fields that it reads. Only a policy takes it:

<!-- in: Concepts.Between.Holds.Contracts.Holds -->
```elixir
subscribe {:between_example, :loan_opened, 1}, as: :copy_lent do
  field :loan_id, :id
  field :copy_id, :id
end

policy :release_hold, "A lent copy is no longer held", handles: :copy_lent, issues: :release_hold
```

**The event never goes into the log of the subscriber.** It arrives in the inbox
(`EhosContract.Inbox`). A read model, an effect and a process manager read the log, where the event
never is. So the contract does not compile if one of them takes a subscribed event
([`D12`](refusals.md#refusals-d)). They react to what the command of the policy appends instead.

- **One event, one reaction.** The row of the inbox has the key of the message. The inbox drops a
  second delivery of a message, and acknowledges it. If the publisher declares `idempotent_on:`, the
  inbox also drops the same event published again with a new id. The inbox keeps its rows for good.
- **A message that does not fit comes again.** The data must fit the fields of the subscribed
  event. If it does not, or the policy raises, the transaction rolls back. The inbox answers
  `:nack`, and the bus delivers the message again. The limit of the transport on deliveries stops a
  message that never succeeds. Correct the declaration or the code before the transport reaches that
  limit, or the message does not come again. `EhosContract.Bus.Local`
  has no limit: by default, it delivers such a message again each second.
- **A rejection is an answer.** If the unit rejects the command of the policy, the inbox takes the
  message.
- **The `delivery` of the policy does not apply.** The inbox runs the policy in the transaction
  that writes its row.
- **The policy gets the run.** The `__meta__` of the struct carries the correlation of the message.
  So what the subscriber decides joins the run of the publisher.
- **Only what is published after the subscription arrives.** To get older events, ask their owner,
  not the bus. If the publisher resets its relay, the whole log arrives again, and the inbox takes
  each event that it did not take before.
- **If no bus is configured, no inbox starts**, and no subscribed event arrives.

A contract that subscribes asks for a capability: the published name without its version, and
`.subscribe`. Example: `between_example.loan_opened.subscribe`. The platform grants this
capability, and the transport delivers the event by it. The engine makes an inbox, and asks for
the capability, only when a policy handles the event. The reference is
[`subscribe`](dsl/contract-subscribe.md).

## An example

One application lends copies and bills for them: 2 contexts and 2 contracts, which share 1 log.
The loans contract publishes the loan. The billing contract consumes the same event as a sibling,
from another context, so it declares its delivery.

```elixir
defmodule Concepts.Between.Domain do
  use EhosContract.Domain, name: :between_example, language: :en

  subdomain :core, "Core", type: :core
  context :loans, "Loans", subdomain: :core
  context :billing, "Billing", subdomain: :core
  actor :librarian, :human, "Librarian"
end
```

```elixir
defmodule Concepts.Between.Contracts.Loans do
  use EhosContract.Contract,
    domain: Concepts.Between.Domain,
    context: :loans,
    id: "between_example.loans"

  aggregate :loan, "Loan of a copy" do
    identity :loan_id

    command :open_loan, "Lend a copy", by: :librarian, emits: :loan_opened do
      field :copy_id, :id
    end

    event :loan_opened, "Copy lent" do
      field :copy_id, :id
    end
  end

  publish :loan_opened,
    version: 1,
    from: :loan_opened,
    fields: [:loan_id, :copy_id],
    idempotent_on: [:loan_id]
end
```

```elixir
defmodule Concepts.Between.Contracts.Billing do
  use EhosContract.Contract,
    domain: Concepts.Between.Domain,
    context: :billing,
    id: "between_example.billing"

  consumes Concepts.Between.Contracts.Loans, [:loan_opened]

  aggregate :fee, "Fee for a loan" do
    identity :loan_id

    command :start_fee_clock, "Start counting the loan's fee", emits: :fee_clock_started
    event :fee_clock_started, "Fee clock started"
  end

  # Another context's event: left without `delivery`, this would not compile (X10).
  policy :bill_lent_copies, "A lent copy starts its fee",
    handles: :loan_opened,
    issues: :start_fee_clock,
    delivery: :at_least_once,
    idempotency: [key: :event_id, owner: :infrastructure]

  scenario "a lent copy starts its fee" do
    target :bill_lent_copies
    on :loan_opened, %{loan_id: "l-1", copy_id: "c-1"}
    issues :start_fee_clock
  end
end
```

A reservations application, with a domain of its own, takes the published loan. It releases the
hold on the copy:

```elixir
defmodule Concepts.Between.Holds.Domain do
  use EhosContract.Domain, name: :between_holds, language: :en

  subdomain :core, "Core", type: :core
  context :holds, "Holds", subdomain: :core
end
```

```elixir
defmodule Concepts.Between.Holds.Contracts.Holds do
  use EhosContract.Contract,
    domain: Concepts.Between.Holds.Domain,
    context: :holds,
    id: "between_holds.holds"

  subscribe {:between_example, :loan_opened, 1}, as: :copy_lent do
    field :loan_id, :id
    field :copy_id, :id
  end

  aggregate :hold, "Hold on a copy" do
    identity :copy_id

    command :release_hold, "Release the hold", emits: :hold_released
    event :hold_released, "Hold released"
  end

  policy :release_hold, "A lent copy is no longer held",
    handles: :copy_lent,
    issues: :release_hold

  scenario "a lent copy's hold is released" do
    target :release_hold
    on :copy_lent, %{loan_id: "l-1", copy_id: "c-1"}
    issues :release_hold
  end
end
```

## What does the check say?

`mix ehos_contract.check` warns with `in-transaction-across-contexts` when a policy, an effect or
a read model declares `delivery: :in_transaction` on an event of another context. The two contexts
then commit together. Make it `:at_least_once`. If the two contexts must commit together, say why
in the pull request. [The rules](rules.md) list all the warnings.

## Next steps

- [What is a reaction?](reactions.md): the policy that takes the event, and its delivery.
- [Repair or replay a subscription](subscriptions.md): publish the log again, or move a relay past
  an event.
- [How does a domain divide a business into contexts?](domain.md): the context map that a reference between contexts needs.
- [The compile refusals](refusals.md#refusals-x): each refusal between contracts, in the families X,
  K and D.
