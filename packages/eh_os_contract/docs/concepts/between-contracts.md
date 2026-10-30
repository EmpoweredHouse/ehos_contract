# Between contracts and applications: consumes, publish and subscribe

How an event of one contract reaches another: a sibling contract of the same application reads it from the
same log, and another application gets it only when it is published, into an inbox.

<!-- covers: entities contract.consumes, contract.publish, contract.subscribe; rules in-transaction-across-contexts -->

There are 2 distances, and they work differently:

| Where the other contract is | It takes the event by | Where the event is | Who may react |
| --- | --- | --- | --- |
| the same application, the same domain | `consumes Sibling, [:event]` | in this application's log | any reaction, a read model, a boundary that consults it, a process's stage |
| another application | `subscribe "<name>.vN"`, with the fields it reads | in the subscriber's inbox, never in its log | a policy only |

The contracts of an application share one log, so a sibling's event is a row the consumer can read; another application's log is not this one's, and its events leave it only through a `publish`.

## Consuming a sibling's events

`consumes` names a sibling contract of the same domain and the events this contract takes from it. Once
consumed, an event is named by its name alone everywhere in the contract (a policy `handles:` it, a process
manager `starts_on` it, a boundary `consults` it, a stage `include`s it), and `as: [old: :new]` renames one that
would clash with a local name. The sibling's declaration defines the event: `consumes` declares no
fields, and the compiler reads the sibling as it is compiled now, so a change to the sibling's event reaches
every contract that consumes it at the next compile. The reference is
[`consumes`](../dsl/contract-consumes.md).

The contract names the sibling's module without a compile dependency, and the Mix compiler
(`compile.eh_os_contract`) checks the link instead: the sibling is a compiled contract of the same domain, and
declares every event named ([`X5`](../contract.md#refusals-x)). The compiler also checks that a field this contract relies on to tell one run or one boundary from
another (a `correlate` field, a boundary's `match:`) exists in the sibling's event with the same type, and is
neither optional nor personal ([`X6`](../contract.md#refusals-x)).

### Delivery across contexts

A sibling may be in the same context or in another one, and that changes what the reaction has to say.

A policy or a read model left without `delivery` runs `:in_transaction`, inside the dispatch that records the
event. For a
sibling of the same context that is usually the right choice: one step of the business, committed once. For a sibling
of **another context** it means the two contexts commit together, and a failure of the policy or the read model rolls the other
context's event back: a person's command in one context fails because something in another one did. So a
policy or a read model that takes an event of a sibling of another context has to declare its delivery, or
the contract does not compile ([`X10`](../contract.md#refusals-x)). Usually that delivery is `:at_least_once`: a policy then names its
`idempotency`, a read model none. An effect and a process manager are left alone, since undeclared they run
`:at_least_once` already. How each delivery fails is on [the reactions page](reactions.md).

## Naming a sibling's unit

A contract often keeps the number of something a sibling decides: a clinic's settlement keeps the visit
that booking made. The field's type says so, as it says which entity a field identifies:
`field :visit_id, {:id, :visit}`. A unit keyed by that number says it in its identity, `identity visit_id:
{:id, :visit}`. The name has to match exactly one unit of the domain's contracts or entity of the domain, or the
contract does not compile ([`X3`](../contract.md#refusals-x)).

The compiler looks for the unit among the contracts of the project it compiles, so **a domain's contracts
compile in one project**. A unit whose contract sits in a dependency is not seen: a correct reference to it is
refused. And where such a unit shares its name with an entity of the domain, the compiler sees only the entity,
so the reference resolves to it instead of being refused as naming both, as it is when both are in one project;
the pages and the context map's count then point at the entity.

A reference carries no event. It says what a number means, so the pages link the field to the unit, and
`mix eh_os_contract.check` counts it as a dependency of this context on the sibling's: the context map has
to relate the two, in the direction the reference runs. To react to what happens to the visit, consume its
events; to decide on them, consult them from a boundary. A command never reads a sibling's unit the way it
reads an entity, since a unit's state is its events.

## Publishing an integration event

An event leaves the application only through `publish`. It names a local event, the versioned name it goes
out under, and the fields it carries:

```elixir
publish :loan_opened,
  as: "between_example.loan.opened.v1",
  from: :loan_opened,
  fields: [:loan_id, :copy_id],
  idempotent_on: [:loan_id]
```

- **The name is a contract with other applications.** It begins with the domain's `name:`, then dotted
  snake_case segments, and ends in a version, `.v1`. Two publications do not share a name.
- **`fields:` are some of the event's fields, none of them personal.** A copy on a broker cannot be erased
  with the subject's key. A unit's identity, or an `:id` naming a person, goes out in the clear, as it is
  stored.
- **`idempotent_on:` names the fields that make one event**, among `fields:`. Their values are the message's
  key, which is how a subscriber tells the same event published again under a new id from a new event. Name
  the fields that make one event, not merely some that identify it: a key too narrow makes two real events one.
  Left out, the message's id is its key.

**The relay** carries it (`EhOsContract.Relay`). It is an ordered subscription over the log, one per
`publish`: the log is the outbox, and there is no outbox table. A step reads the publication's events, builds
a message from each, hands the batch to the configured `EhOsContract.Bus`, and moves its position only when
the bus says it holds the batch. A relay that stops in between publishes the batch again under the same ids,
so a message may arrive twice, never zero times, and never without its event in the log.

```elixir
config :eh_os_contract, bus: {EhOsContract.Bus.Local, []}
```

The library ships `EhOsContract.Bus.Local`, for tests and one node; a transport between nodes is an adapter
the platform provides, and the library depends on no broker. What a host should know of the relay:

- **It starts at the head of the log**, as a policy does: what is in the log when a `publish` is first deployed
  is history, and nothing publishes it by itself. Publishing the log again is a person's
  `mix eh_os_contract.subscriptions --reset`.
- **A broker that cannot be reached stops nothing.** The position stays, no attempt is counted, and the relay
  tries again later. With no bus configured it waits, and publishes everything since once one is.
- **A relay is keyed by the `publish`'s name, not its `as:`.** Renaming the declaration starts a new relay at
  the head of the log, and what the old one had not yet published never leaves.

The reference is [`publish`](../dsl/contract-publish.md).

## Subscribing to another application's event

The subscriber names the event by its published name, gives it a name in this contract, and lists the fields
it reads. Only a policy takes it:

```elixir
subscribe "between_example.loan.opened.v1", as: :copy_lent do
  field :loan_id, :id
  field :copy_id, :id
end

policy :release_hold, "A lent copy is no longer held", handles: :copy_lent, issues: :release_hold
```

**The event never enters the subscriber's log.** It arrives in an inbox (`EhOsContract.Inbox`). In one
transaction, the inbox writes its row and runs each policy that handles the event; the policy's commands are
dispatched as a policy's always are. Only after that transaction commits does the inbox acknowledge the message. A read
model, an effect and a process manager read the log, where the event never is, so a contract in which one of
them takes a received event does not compile ([`D12`](../contract.md#refusals-d)); they react to what the policy's command records
instead. The policy's `delivery` changes nothing for a received event: the inbox runs it in the transaction
that writes its row.

- **One event, one reaction.** The inbox's row is keyed by the message's key. A second delivery of a message
  finds the row and is dropped, and so is the same event published again under a new id, when the publisher
  declares `idempotent_on:`.
- **A message that does not fit is delivered again.** One whose payload does not fit the fields the
  subscribed event declares, or whose policy raises, rolls back and is answered `:nack`, so nothing is lost while
  the declaration or the code is put right. A rejection of the policy's command is the unit's answer, and is
  taken.
- **The policy is told the run.** The received struct's `__meta__` carries the correlation the message
  carried, so what the subscriber decides joins the publisher's run.
- **Only what is published after it subscribes arrives.** What the publisher published before is its
  history, asked of its owner, not of the bus.

A contract that subscribes asks for the capability `<name>.subscribe` of the published name without its
version, `between_example.loan.opened.subscribe`. The platform grants this capability, and the transport delivers the event
according to it.
The reference is [`subscribe`](../dsl/contract-subscribe.md).

## An example

One application lends copies and bills for them: 2 contexts and 2 contracts that share 1 log. The loans contract
publishes the loan; billing consumes the same event as a sibling, from another context, and so declares its
delivery.

```elixir
defmodule Concepts.Between.Domain do
  use EhOsContract.Domain, name: :between_example, language: :en

  subdomain :core, "Core", type: :core
  context :loans, "Loans", subdomain: :core
  context :billing, "Billing", subdomain: :core
  actor :librarian, :human, "Librarian"
end
```

```elixir
defmodule Concepts.Between.Contracts.Loans do
  use EhOsContract.Contract,
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
    as: "between_example.loan.opened.v1",
    from: :loan_opened,
    fields: [:loan_id, :copy_id],
    idempotent_on: [:loan_id]
end
```

```elixir
defmodule Concepts.Between.Contracts.Billing do
  use EhOsContract.Contract,
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

A reservations application, with a domain of its own, takes the published loan to release a hold on the copy:

```elixir
defmodule Concepts.Between.Holds.Domain do
  use EhOsContract.Domain, name: :between_holds, language: :en

  subdomain :core, "Core", type: :core
  context :holds, "Holds", subdomain: :core
end
```

```elixir
defmodule Concepts.Between.Holds.Contracts.Holds do
  use EhOsContract.Contract,
    domain: Concepts.Between.Holds.Domain,
    context: :holds,
    id: "between_holds.holds"

  subscribe "between_example.loan.opened.v1", as: :copy_lent do
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

## What the compiler refuses

- `consumes` of a contract that is not compiled, of another domain, or of an event the sibling does not
  declare ([`X5`](../contract.md#refusals-x)); a field this contract correlates or matches on that is missing in the sibling's event, of
  another type, optional or personal ([`X6`](../contract.md#refusals-x)). Another domain's events come only through `subscribe`.
- `consumes` given a published name, which is `subscribe`d to; `consumes` of the contract itself, naming no
  events, renaming one it does not consume, or declaring fields ([`K1`](../contract.md#refusals-k)).
- A policy or a read model taking an event of a sibling of another context without declaring `delivery`
  ([`X10`](../contract.md#refusals-x)).
- A `publish` from no local event, with no fields, with fields the event does not have or personal ones, with
  `idempotent_on:` outside its `fields:`, or under a name that is unversioned, shared with another
  publication, or outside the domain's `name:`; a `subscribe` unversioned, without `as:`, or listing no fields
  ([`D11`](../contract.md#refusals-d)).
- A read model, an effect or a process manager taking a received event ([`D12`](../contract.md#refusals-d)).

## What `mix eh_os_contract.check` reports

- `in-transaction-across-contexts` (warning): a policy, an effect or a read model declared
  `delivery: :in_transaction` on an event of a sibling of another context, so the two contexts commit
  together. Make it `:at_least_once`, or, if the two really must commit together, say why in the pull
  request.

All of the rules are in [the catalogue](../rules.md).
