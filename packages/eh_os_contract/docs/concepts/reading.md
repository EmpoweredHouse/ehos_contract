# Reading: read models and queries

This page covers how an application reads what its units decided: a read model keeps rows projected
from events, and a query is the question an actor may ask of them.

<!-- covers: entities contract.read_model, contract.query; rules read-model-without-query -->

A unit's state is for its decisions, and nobody else reads it. Everything a person or another part of
the application wants to see (the copies out on loan, a day's totals, who is waiting) is a
**read model**: rows the application keeps in its own tables, written from the events as they are
appended. A **query** is a question asked of one read model, and like a command it is a capability an
actor is granted. The keys are in the reference: [`read_model`](../dsl/contract-read_model.md) and
[`query`](../dsl/contract-query.md).

## An example

A library lends copies to members. The librarian asks which copies a member has, and who has a given
copy.

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

## A read model

A read model declares the shape of its rows (`field`) and the events it `projects`: events of this
contract, or ones it `consumes` from a sibling ([`P5`](../contract.md#refusals-p)). It is implemented by a module with one callback
per projected event, which writes the application's own tables and returns `:ok`. The application
creates them with its own migrations.

The read model's `Row` is an Ecto schema of its fields. A read model that names its table, `table:`,
and the row fields that make a row unique, `key:`, gets a schema of that table with the key as its
primary key, so a projection writes through it (`insert_all(Row, rows, on_conflict: …,
conflict_target: key)`) and a query reads `from r in Row`, each field of the contract's type: an enum
an `Ecto.Enum` stored as its member's name, a `:timestamp` with microseconds, written at whatever
precision a time comes in, a domain value the type the domain gives it. A read model without `table:` has an embedded schema, with no table behind it.
The key is required with a table and refused without one ([`P6`](../contract.md#refusals-p)).

The schema holds the declared fields and nothing else. A column the projection keeps for itself, the
position it has read up to, say, is a field of the read model too, or written by the table's name,
outside the schema.

```elixir
defmodule Concepts.Reading.CopiesOut do
  use Concepts.Reading.Contracts.Loans, read_model: :copies_out

  import Ecto.Query

  @impl true
  def copy_lent(%CopyLent{} = event) do
    row = %{
      loan_id: event.loan_id,
      copy_id: event.copy_id,
      member_id: event.member_id,
      member_name: if(is_binary(event.member_name), do: event.member_name)
    }

    # A second delivery of the same event, or a rebuild, writes no second row.
    repo().insert_all(Row, [row], on_conflict: :nothing, conflict_target: [:loan_id])
    :ok
  end

  @impl true
  def copy_returned(%CopyReturned{loan_id: loan}) do
    repo().delete_all(from(r in Row, where: r.loan_id == ^loan))
    :ok
  end

  @impl true
  def forget(:member, member) do
    repo().update_all(from(r in Row, where: r.member_id == ^member), set: [member_name: nil])
    :ok
  end

  @impl true
  def reset do
    repo().delete_all(Row)
    :ok
  end

  defp repo, do: EhOsContract.Config.fetch!(:repo)
end
```

**When it is written.** The read model's `delivery` decides:

- `:in_transaction`, when `delivery` is left out: dispatch projects the appended events inside the
  transaction that appends them, before it commits. A query reads the command's effect as soon as
  dispatch returns, and a projection that raises rolls the command back with it. A read model that
  takes an event of a sibling contract in another context must declare its `delivery` ([`X10`](../contract.md#refusals-x)).
- `:at_least_once`: a subscription reads the log in order after the commit, in batches, and moves its
  position in the same transaction as the rows it wrote, so each batch's rows are committed once. A
  callback may still run more than once (a batch that raises is run again), so keep it to writes in that
  transaction, or make what it does outside it idempotent. An event that
  raises is retried, and after 3 attempts the subscription stops at it as `failing` rather than
  skip it; `mix eh_os_contract.subscriptions` shows where each one stands, and moving past the event
  is a person's decision.

A read model takes only events in this application's log: an event received from another application
arrives in an inbox that only a policy takes ([`D12`](../contract.md#refusals-d)). Project what the policy's command records
instead.

**Rebuilding.** A read model's version is a digest of its declaration and of every event it takes.
When it changes, its subscription is marked `stale` at the next boot. If the read model defines `reset/0`,
it is rebuilt at that boot, unless the subscriptions are `:manual` (`config :eh_os_contract, subscriptions:`), as
in tests: `reset/0` deletes everything it wrote, and the log is replayed into it. Without
`reset/0` it stays `stale` and goes on taking new events over the old rows. `mix
eh_os_contract.subscriptions --reset <contract id>:read_model:<name>` rebuilds one by hand.

**Where a new one starts.** A new read model delivered `:at_least_once` starts at the beginning of the
log and takes all of it. One delivered `:in_transaction` starts at the head, since dispatch projects
it from then on. If you add it to a log that already holds its events, rebuild it by hand.

**Personal data.** A read model that projects a personal field must define `forget/2`, or the host
does not boot. When a subject is erased (`EhOsContract.erase/3`), each such read model receives the
subject's type and id and deletes or blanks what it keeps of them. A read model delivered `:in_transaction`
does this inside the erasure's transaction, so index the column that holds the subject's id. An event replayed
after its subject was erased reads back with `%EhOsContract.Erased{}` in place of each personal field,
which is why `copy_lent` above keeps a name only when it is a string.

## A query

A query names the read model it `reads`, who may ask it (`by:`, required, [`D10`](../contract.md#refusals-d)), its parameters
(`param`), and whether it answers rows or one row (`returns: :many`, the default, or `:one`). Its
implementation is one function named after it, taking the parameters' struct and a context with the
actor, and answering the read model's `Row` structs (a list, or one row or `nil`). With a table, it
queries the schema and answers what Ecto loads, with no field listed again:

```elixir
defmodule Concepts.Reading.LoansOfMember do
  use Concepts.Reading.Contracts.Loans, query: :loans_of_member

  import Ecto.Query

  @impl true
  def loans_of_member(%LoansOfMember{member_id: member}, _ctx) do
    from(r in Row, where: r.member_id == ^member, order_by: r.loan_id)
    |> EhOsContract.Config.fetch!(:repo).all()
  end
end

defmodule Concepts.Reading.HolderOfCopy do
  use Concepts.Reading.Contracts.Loans, query: :holder_of_copy

  import Ecto.Query

  @impl true
  def holder_of_copy(%HolderOfCopy{copy_id: copy}, _ctx) do
    from(r in Row, where: r.copy_id == ^copy)
    |> EhOsContract.Config.fetch!(:repo).one()
  end
end
```

The engine checks the answer against the declaration: anything other than rows of the read model, in the number
`returns:` declares, raises. Nothing is written: a read is not a fact.

**A query's scenario** projects its `given` events through the read model's implementation, asks the
query, and compares the answer with `answers`: exactly as many rows, each matching a different one on
the fields it names, in any order. It writes the host's tables, so `EhOsContract.ScenarioCase` runs it
in a transaction of the configured repo that is rolled back.

## How a host asks

The application's own code asks with the parameters' struct and the actor:

```elixir
alias Concepts.Reading.Contracts.Loans

EhOsContract.query(Loans, %Loans.Queries.LoansOfMember{member_id: member}, actor: actor)
```

It answers `{:ok, rows}` (`{:ok, row_or_nil}` for `returns: :one`), or `{:error, reason}` when the
actor may not ask or the parameters do not fit. For an actor with a credential, the engine asks
`EhOsContract.Authorizer` for the query's capability, `reading_example.loans_of_member` (the domain's
name and the query's), as it would for a command.

**Reading a write.** A read model delivered `:at_least_once` may not have taken an event yet when the
command that appended it returns. Pass the receipt's position, and the query waits until the read
model has taken it:

```elixir
{:ok, receipt} = EhOsContract.dispatch(Loans, command, actor: actor)
EhOsContract.query(Loans, params, actor: actor, min_position: receipt.position)
```

It polls for up to `wait:` milliseconds (5000 by default), then refuses with `{:error,
:not_caught_up}` rather than answer from before the write.

**From outside.** A request with a credential asks by the capability's name, with the parameters as
the caller sent them, through `EhOsContract.call/3` (`EhOsContract.call({:query,
"reading_example.loans_of_member"}, %{"member_id" => id}, actor: actor)`) or over HTTP through
`EhOsContract.Plug`, as `GET <mount>/queries/reading_example.loans_of_member?member_id=...`. Both decode
the parameters against the declaration and go through `query/3`.

**Narrowing by a grant.** A query declared `scope: :branch_id` answers only rows whose `branch_id`
the credential grants: the scope is a parameter and a field of the read model's row of the same type,
and every actor in `by:` carries it ([`D10`](../contract.md#refusals-d)). A value outside the grant is refused before the
implementation runs, and every row it answers is checked again, so a wrong `where` raises
`EhOsContract.Authorizer.OutsideScopeError` instead of handing out another branch's rows. How grants
are made is in [authorization](../authorization.md).

## What the compiler refuses

- a read model projecting an event neither of this contract nor consumed from a sibling, or a query
  reading what is not a read model of this contract ([`P5`](../contract.md#refusals-p));
- a read model with `table:` and no `key:`, or a `key:` without `table:`; a table that is not a plain SQL
  name or that another read model of the contract keeps its rows in; a key field that is not a row field, or
  is optional, personal, a list or a domain value made of fields ([`P6`](../contract.md#refusals-p));
- a read model taking an event received from another application ([`D12`](../contract.md#refusals-d));
- a read model of a sibling's event in another context without `delivery` ([`X10`](../contract.md#refusals-x));
- a query without `by:`, or a scope that is not a same-typed parameter and row field ([`D10`](../contract.md#refusals-d));
- a query named like a command, or like an event an actor records ([`N1`](../contract.md#refusals-n)): each is a capability, and
  their names share one namespace;
- a query's scenario whose `given` are not events its read model projects ([`S2`](../contract.md#refusals-s)), or without one
  `answers` shaped as the query returns ([`S6`](../contract.md#refusals-s)).

## What `mix eh_os_contract.check` reports

- `read-model-without-query` (warning, [rules](../rules.md)): no query reads a read model, so every
  event it projects costs a write no answer ever reads. Declare the query that reads it, or remove it.
