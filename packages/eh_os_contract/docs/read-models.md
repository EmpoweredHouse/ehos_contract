# Write a read model and its query

This page tells how to write the table and the modules of a read model and a query. It also tells
how the application asks the query. It is for a developer who implements a contract.
[The glossary](glossary.md) defines the words of the contract.

## Before you start

- A contract that declares the read model and its query.
  [What are read models and queries?](reading.md) tells about them.
- The application of the modules is in `config :eh_os_contract, applications: [...]`.
  [Getting started](getting-started.md) tells how.
- The application has an Ecto repo, and the engine uses it (`config :eh_os_contract, repo:`).

This page uses the contract of [the reading page](reading.md):

```elixir
defmodule Concepts.ReadModels.Domain do
  use EhOsContract.Domain, name: :read_models_example, language: :en

  subdomain :core, "Core", type: :core
  context :lending, "Lending", subdomain: :core
  actor :librarian, :human, "Librarian"
  subject :member, "Member"
end

defmodule Concepts.ReadModels.Contracts.Loans do
  use EhOsContract.Contract,
    domain: Concepts.ReadModels.Domain,
    context: :lending,
    id: "read_models_example.loans"

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
    table: "read_models_example_copies_out",
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

## Make the table

1. Write the migration of the table from the declaration:

   ```bash
   mix eh_os_contract.gen.migration Concepts.ReadModels.Contracts.Loans copies_out
   ```

   `--all` writes a migration for each read model with a table that no migration creates yet.
   `--migrations-path DIR` writes into another directory. The task never writes over a
   migration.

   The result: a file `<timestamp>_create_read_models_example_copies_out.exs` in the migrations of
   the repo. It creates:
   - a column for each field, of the type that the field is stored as;
   - the `key:` as the primary key;
   - `null: false` on each required field, except a personal field, which an erasure blanks;
   - an index on the id of each subject and on the scope of each query.

2. Run the migration: `mix ecto.migrate`. The migration belongs to the application from now on.
   Change the table in later migrations.
3. Add a test that holds the tables to the contracts:

   <!-- not compiled: a test of the host -->
   ```elixir
   test "the read models' tables fit their contracts" do
     EhOsContract.Testing.assert_read_model_tables()
   end
   ```

   The result: if a field is in the contract and not in the table, the test fails, before the
   first write fails. The test permits an extra column, unless it is `NOT NULL` with no default.

## Write the module of the read model

The module has one callback for each event that the read model projects. The callback has the
name of the event, writes the tables of the application, and returns `:ok`:

```elixir
defmodule Concepts.ReadModels.CopiesOut do
  use Concepts.ReadModels.Contracts.Loans, read_model: :copies_out

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

- **Make a second write change nothing.** A rebuild or a second delivery gives the same event
  again. `on_conflict: :nothing` on the key does this here.
- **Define `forget/2` for an event with personal data.** It gets the type and the id of an erased
  subject. Delete or blank what the rows keep of the subject. Without it,
  the host does not boot.
- **Expect an erased personal field.** After an erasure, an event that is read again has
  `%EhOsContract.Erased{}` in place of each personal field. `copy_lent/1` keeps a name only when
  it is a string.
- **Define `reset/0`.** It deletes all the rows. The engine calls it to rebuild the read model.
  [Repair or replay a subscription](subscriptions.md#rebuild-a-read-model) tells when.

## Write the module of the query

The module has one function, with the name of the query. It takes the struct of the parameters
and a context with the actor. It returns the `Row` structs of the read model: a list, or one row
or `nil` for `returns: :one`. With a table, it queries the schema, and returns what Ecto loads. It does not list the fields
again:

```elixir
defmodule Concepts.ReadModels.LoansOfMember do
  use Concepts.ReadModels.Contracts.Loans, query: :loans_of_member

  import Ecto.Query

  @impl true
  def loans_of_member(%LoansOfMember{member_id: member}, _ctx) do
    from(r in Row, where: r.member_id == ^member, order_by: r.loan_id)
    |> EhOsContract.Config.fetch!(:repo).all()
  end
end

defmodule Concepts.ReadModels.HolderOfCopy do
  use Concepts.ReadModels.Contracts.Loans, query: :holder_of_copy

  import Ecto.Query

  @impl true
  def holder_of_copy(%HolderOfCopy{copy_id: copy}, _ctx) do
    from(r in Row, where: r.copy_id == ^copy)
    |> EhOsContract.Config.fetch!(:repo).one()
  end
end
```

The scenarios of the contract now run. A scenario of a query writes its `given` events through the
module of the read model, and asks the module of the query. `EhOsContract.ScenarioCase` runs it in
a transaction that it rolls back. [What is a scenario?](scenarios.md) tells more.

## Ask the query

The code of the application asks with the struct of the parameters and the actor:

<!-- not compiled: a call in the host's code -->
```elixir
alias Concepts.ReadModels.Contracts.Loans

EhOsContract.query(Loans, %Loans.Queries.LoansOfMember{member_id: member}, actor: actor)
```

The result: `{:ok, rows}`, or `{:ok, row_or_nil}` for `returns: :one`. The section
[What can go wrong](#what-can-go-wrong) lists the errors of `EhOsContract.query/3`.

<a id="read-your-own-write"></a>

### Read your own write

A read model delivered `:at_least_once` can be behind when a command returns. To wait for it,
give the position of the receipt to the query, after the commit.

> **Do not wait inside your own transaction.**
> If you dispatch in your own transaction, the read model cannot see the event yet. The query
> waits for all of `wait:`, while the transaction holds the append lock. Every other append waits
> too.

<!-- not compiled: a call in the host's code -->
```elixir
{:ok, receipt} = EhOsContract.dispatch(Loans, command, actor: actor)
EhOsContract.query(Loans, params, actor: actor, min_position: receipt.position)
```

The query waits until the read model took that position. It looks again each 25 milliseconds,
for up to `wait:` milliseconds (5000 if you leave it out). Then it returns
`{:error, :not_caught_up}`. It does not answer from before the write.

### Ask from outside the application

A request with a credential asks by the name of the capability, with the parameters as the caller
sent them:

- through `EhOsContract.call/3`:
  `EhOsContract.call({:query, "read_models_example.loans_of_member"}, %{"member_id" => id}, actor: actor)`;
- over HTTP, through `EhOsContract.Plug`:
  `GET <mount>/queries/read_models_example.loans_of_member?member_id=...`.

Both decode the parameters against the declaration, and then call `EhOsContract.query/3`.

<a id="what-can-go-wrong"></a>

## What can go wrong

**The compiler refuses the read model or the query.** The families
[`P`](refusals.md#refusals-p), [`D`](refusals.md#refusals-d) and [`N`](refusals.md#refusals-n)
list each refusal. A scenario of a query gives only events that its read model projects
([`S2`](refusals.md#refusals-s)). It has one `answers`, with the shape that the query returns
([`S6`](refusals.md#refusals-s)).

**The host does not boot.** A read model takes an event with personal data, and its module has no
`forget/2`. Add it.

**`EhOsContract.query/3` returns an error.**

| Error | Cause |
| --- | --- |
| `{:error, :missing_capability}` | the credential does not grant the capability of the query, or `by:` names no `:human` actor |
| `{:error, :unscoped_grant}` | the query has a `scope:`, and the credential grants no values for it |
| `{:error, :outside_scope}` | the scope parameter is outside what the credential grants |
| `{:error, :not_declared}` | the actor is a `:system` actor that is not in `by:`, or a reaction |
| `{:error, {:invalid, problems}}` | the parameters do not fit the declaration |
| `{:error, :not_caught_up}` | the read model did not take `min_position:` before `wait:` ended |

**The query raises an `ArgumentError`.** The module answered something other than rows of the read
model, in the number that `returns:` declares. Return the `Row` structs.

**The query raises `EhOsContract.Authorizer.OutsideScopeError`.** The query has a `scope:`, and the
module answered a row that the credential does not grant. The `where` of the query is wrong. The
caller gets no row.

**A query reads part of the rows.** The read model is being rebuilt. Give `min_position:` to wait for
it.

## Next steps

- [Repair or replay a subscription](subscriptions.md): rebuild the read model after a change.
- [What is a scenario?](scenarios.md): how a scenario of a query runs.
- [Authorization](authorization.md): the capabilities and grants that a query asks for.
