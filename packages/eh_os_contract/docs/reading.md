# What are read models and queries?

<!-- covers: entities contract.read_model, contract.query; rules read-model-without-query -->

This page tells how an application shows what its units decided. A read model keeps rows that it
writes from events, and a query reads them. It is for a developer who declares them in a
contract. [The glossary](glossary.md) defines each word in italics.

## What do a read model and a query do?

The state of a unit is for its decisions, and no other code reads it. A person or another part of
the application reads a *read model*: rows that the application keeps in its own table. The
implementation of the read model writes the rows from the events, when they are appended.
Examples: the copies out on loan, the totals of a day, the people on a list.

A *query* is a question to one read model. As a command does, a query has a *capability* that an
actor must have. A query writes nothing: a read is not an event.

The references list each key: [`read_model`](dsl/contract-read_model.md) and
[`query`](dsl/contract-query.md).

## An example

A library lends copies to members. The librarian asks which copies a member has, and who has a
given copy.

```elixir
defmodule Concepts.Reading.Domain do
  use EhOsContract.Domain, name: :reading_example, language: :en

  subdomain :core, "Core", type: :core
  context :lending, "Lending", subdomain: :core
  actor :librarian, :human, "Librarian"
  subject :member, "Member"
end
```

```elixir
defmodule Concepts.Reading.Contracts.Loans do
  use EhOsContract.Contract,
    domain: Concepts.Reading.Domain,
    context: :lending,
    id: "reading_example.loans"

  aggregate :loan, "Loan of a copy" do
    identity :loan_id

    command :lend_copy, "Lend a copy", by: :librarian, emits: :copy_lent do
      field :copy_id, :id
      field :member_id, :id, subject: :member
      field :member_name, :string, personal: :member_id
    end

    command :take_back, "Take a copy back", by: :librarian, emits: :copy_returned

    event :copy_lent, "Copy lent" do
      field :copy_id, :id
      field :member_id, :id, subject: :member
      field :member_name, :string, personal: :member_id
    end

    event :copy_returned, "Copy returned"
  end

  read_model :copies_out, "Copies out on loan",
    projects: [:copy_lent, :copy_returned],
    table: "reading_example_copies_out",
    key: :loan_id do
    field :loan_id, :id
    field :copy_id, :id
    field :member_id, :id, subject: :member
    field :member_name, :string, personal: :member_id
  end

  query :loans_of_member, "A member's loans", reads: :copies_out, by: :librarian do
    param :member_id, :id
  end

  query :holder_of_copy, "Who has a copy", reads: :copies_out, by: :librarian, returns: :one do
    param :copy_id, :id
  end

  scenario "a member's loans, and nobody else's" do
    given :copy_lent, %{loan_id: "loan-1", copy_id: "copy-1", member_id: "member-anna", member_name: "Anna"}
    given :copy_lent, %{loan_id: "loan-2", copy_id: "copy-2", member_id: "member-ben", member_name: "Ben"}
    query :loans_of_member, %{member_id: "member-anna"}
    answers [%{copy_id: "copy-1"}]
  end

  scenario "a returned copy is with nobody" do
    given :copy_lent, %{loan_id: "loan-1", copy_id: "copy-1", member_id: "member-anna", member_name: "Anna"}
    given :copy_returned, %{loan_id: "loan-1"}
    query :holder_of_copy, %{copy_id: "copy-1"}
    answers nil
  end
end
```

[Write a read model and its query](read-models.md) gives the modules that implement this
contract.

## How does an event become a row and an answer?

![The implementation of a read model writes rows from each event, in the transaction of dispatch or later from a subscription, and a query answers from those rows.](img/reading-flow.svg)

1. Dispatch appends an event to the log.
2. For a read model delivered `:at_least_once`, a *subscription* reads the log after the commit.
3. The subscription runs the implementation of the read model for each event.
4. For a read model delivered `:in_transaction`, dispatch runs the implementation before the
   commit.
5. The implementation writes rows to the table of the read model.
6. The application asks a query, with the actor.
7. If the actor can ask, the engine calls the implementation of the query.
8. The implementation reads the rows.
9. The engine checks the rows, then returns them.

## When does a read model write?

The *delivery* of the read model tells when its implementation runs.

**`:in_transaction`** is the delivery if you leave it out. Dispatch runs the implementation in the
transaction that appends the events, before the commit.

- A query sees the result of the command when dispatch returns.
- If the implementation raises, the command fails with it.
- A read model that takes an event of a contract in another context must declare its delivery
  ([`X10`](refusals.md#refusals-x)).

**`:at_least_once`** runs the implementation after the commit, from a subscription.

- The subscription reads the log in order, in batches of up to 500 events.
- It moves its position in the same transaction as the rows that it wrote. So the rows of each
  batch are committed one time.
- If a batch raises, the subscription runs it again. A callback can run more than one time. Write
  only in that transaction, or make what the callback does outside it idempotent.
- If an event raises 3 times, the subscription is `failing` and stops at that event. It does not
  skip the event. [Repair or replay a subscription](subscriptions.md) tells how to move it.

A query of a read model delivered `:at_least_once` can come before the read model took the event.
[Write a read model and its query](read-models.md#read-your-own-write) tells how to wait for it.

## Which events can a read model take?

A read model `projects` the events of its own contract, and the events that its contract
`consumes` from another contract of the same application ([`P5`](refusals.md#refusals-p)).

A read model takes only the events of this log. An event of another application arrives in an
inbox, and only a policy takes it ([`D12`](refusals.md#refusals-d)). To show such an event, project
the event that the command of the policy appends.

## What does a read model keep?

The `field`s of a read model give the shape of its rows. The read model has a `Row`: an Ecto
schema of these fields.

With `table:` and `key:`, the `Row` is a schema of that table. The key is its primary key. A
projection writes through it, and a query reads `from r in Row`. Without `table:`, the `Row` is an
embedded schema, with no table. A table needs a key, and a key needs a table
([`P6`](refusals.md#refusals-p)).

Each field has the type of the contract:

| The field in the contract | In the `Row` |
| --- | --- |
| an enum | an `Ecto.Enum`, stored as the name of its member |
| a `:timestamp` | a time with microseconds, at the precision of the time that you write |
| a value of the domain | the type that the domain gives it |
| a value made of fields, or a list of them | a `jsonb` column, written as the log writes it and read back as the struct of the value |

The schema holds the declared fields and nothing else. If the projection keeps a column for itself,
such as the position that it read to, declare it as a field. Or write it by the name of the table,
outside the schema.

> **A read model keeps personal data outside the log.**
> An erasure destroys the key of the subject. The events lose its personal fields. The rows
> of a read model keep their copy until the read model removes it.

So a read model that takes an event with personal data defines `forget/2`. Without it, the host
does not boot. When a subject is erased (`EhOsContract.erase/3`), each such read model gets the
type and the id of the subject. It deletes or blanks what it keeps of the subject.

- A read model delivered `:in_transaction` forgets in the transaction of the erasure. Index the
  column that holds the id of the subject.
- A read model delivered `:at_least_once` gets the erasure as an event of the log, in order.
- When an event is read again after an erasure, each personal field is `%EhOsContract.Erased{}`.
  In a value made of fields, the `Row` reads an erased personal field as `nil`.
- When you inspect a `Row`, the engine hides each personal field.

## Where does a new read model start?

A new read model delivered `:at_least_once` starts at the start of the log. It takes all of it.

A new read model delivered `:in_transaction` starts at the head of the log. Dispatch writes to it
from then on. If the log already holds its events, rebuild it by hand:
[Repair or replay a subscription](subscriptions.md#rebuild-a-read-model).

The version of a read model is a digest of its declaration and of each event that it takes. If
the version changes, the engine marks the read model `stale` at the next boot. If the read model
defines `reset/0`, the engine rebuilds it at that boot. Without `reset/0`, it stays `stale`, and
writes new events over its old rows.

## What does a query answer?

A query names the read model that it `reads`, the actors who can ask it (`by:`), and its
parameters (`param`). `by:` is required ([`D10`](refusals.md#refusals-d)). A query answers a list
of rows (`returns: :many`, the default), or one row or `nil` (`returns: :one`).

- The name of the capability is the name of the domain and the name of the query:
  `reading_example.loans_of_member`. For an actor with a credential, the engine asks the
  `EhOsContract.Authorizer` for it, as for a command.
- The engine checks the answer against the declaration. If the answer is not rows of the read
  model, in the number that `returns:` declares, the engine raises.
- A query, a command and an event that an actor records share one set of names, because each one
  is a capability ([`N1`](refusals.md#refusals-n)).

**A query can narrow by a grant.** A query declared `scope: :branch_id` answers only the rows whose
`branch_id` the credential grants.

- The scope is a parameter, and a field of the row with the same type. Each actor in `by:` carries
  it ([`D10`](refusals.md#refusals-d)).
- If the parameter is outside the grant, the engine refuses the query before the implementation
  runs.
- The engine checks each row of the answer again. If a row is outside the grant, it raises
  `EhOsContract.Authorizer.OutsideScopeError`, and returns no row.
- A `:system` actor is not narrowed.

[Authorization](authorization.md) tells how grants are made.

## What does the check say about a read model?

`mix eh_os_contract.check` warns with `read-model-without-query` when no query reads a read model.
Each event that it projects then costs a write that no answer reads. Declare the query that reads
it, or remove the read model. [The rules](rules.md) list all the warnings.

## Next steps

- [Write a read model and its query](read-models.md): the modules, the migration, and how the
  application asks.
- [Repair or replay a subscription](subscriptions.md): rebuild a read model, or move it past an
  event.
- [How does the engine keep and erase personal data?](personal-data.md): what an erasure does to the log and to read
  models.
- [The compile refusals](refusals.md#refusals-p): each refusal of a read model or a query.
