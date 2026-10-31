# Getting started

<!-- covers: rules no-contracts -->

This page tells how to add the engine to an application and see it work one time. It is for a
developer who knows Elixir, Ecto and Phoenix, but not this library. You write one contract, run its
scenarios as tests, dispatch one command and check the model. [The glossary](glossary.md) defines
each word in italics.

<a id="before-you-start"></a>

## Before you start

- Elixir 1.18 or later.
- An Ecto repo on PostgreSQL.
- Oban 2.20 or later, on the same repo. The engine runs each effect delivered `:at_least_once` as
  an Oban job. Dispatch inserts the job in the transaction that appends its event.

<a id="add-the-dependency"></a>

## 1. Add the dependency and the compiler

The package is not on Hex. Add it from git to `deps/0` in `mix.exs`:

```elixir
{:eh_os_contract,
 git: "https://github.com/EmpoweredHouse/eh-os-contract.git",
 sparse: "packages/eh_os_contract"}
```

Then add the compiler `:eh_os_contract` after the compilers of Elixir, in `project/0`:

```elixir
compilers: Mix.compilers() ++ [:eh_os_contract]
```

This compiler checks the rules between a contract, its domain and the other contracts.

**Result:** `mix deps.get` fetches the package, and `mix.lock` pins its commit.

<a id="write-a-domain-and-a-contract"></a>

## 2. Write a domain and a contract

A *domain* holds the words of the business. A *contract* holds what one context decides. This
contract has one *aggregate*, a loan of a copy, and two *scenarios*:

```elixir
defmodule GettingStarted.Domain do
  use EhOsContract.Domain, name: :getting_started, language: :en

  subdomain :core, "Core", type: :core

  context :lending, "Lending", subdomain: :core

  actor :librarian, :human, "Librarian"
end

defmodule GettingStarted.Contracts.Loans do
  use EhOsContract.Contract,
    domain: GettingStarted.Domain,
    context: :lending,
    id: "getting_started.loans"

  aggregate :loan, "Loan" do
    identity :copy_id

    state do
      field :lent, :boolean, default: false
    end

    command :lend_copy, "Lend a copy",
      by: :librarian,
      emits: :copy_lent,
      rejects: :lent_once do
      field :member_id, :string
    end

    event :copy_lent, "Copy lent" do
      field :member_id, :string
    end

    invariant :lent_once, "A copy is lent to one member at a time"
  end

  scenario "a copy is lent" do
    command :lend_copy, %{copy_id: "c-1", member_id: "m-1"}
    expect :copy_lent
  end

  scenario "a lent copy is not lent again" do
    given :copy_lent, %{copy_id: "c-1", member_id: "m-1"}
    command :lend_copy, %{copy_id: "c-1", member_id: "m-2"}
    rejected :lent_once
  end
end
```

The field `copy_id` identifies each loan. The *invariant* `lent_once` is the rule that the command
can reject on. A librarian can read the two scenarios and confirm them.

**Result:** `mix compile` passes. If the model contradicts itself, the compiler stops with a code
and a message. [The compile refusals](refusals.md) list each code.

<a id="implement-the-aggregate"></a>

## 3. Implement the aggregate

The *implementation* holds the code that decides. It points to its contract:

```elixir
defmodule GettingStarted.Loan do
  use GettingStarted.Contracts.Loans, aggregate: :loan

  @impl true
  def lend_copy(%LendCopy{}, %State{lent: true}), do: reject(:lent_once)

  def lend_copy(%LendCopy{copy_id: id, member_id: member}, _state),
    do: emit(%CopyLent{copy_id: id, member_id: member})

  @impl true
  def evolve(state, %CopyLent{}), do: %{state | lent: true}
end
```

The contract generates the structs `LendCopy`, `CopyLent` and `State`. The callback `lend_copy/2`
decides with `emit/1` or `reject/1`. The callback `evolve/2` folds each event into the state.

**Result:** `mix compile` passes. If you remove a callback, or emit an event that the command does
not declare, the compile fails.

<a id="run-the-scenarios-as-tests"></a>

## 4. Run the scenarios as tests

Add one test module for the contract. It runs each scenario against the implementation:

```
defmodule GettingStarted.LoansScenariosTest do
  use EhOsContract.ScenarioCase, contract: GettingStarted.Contracts.Loans
end
```

The scenarios of this contract need no database.

**Result:** `mix test` runs 2 tests, `scenario: a copy is lent` and
`scenario: a lent copy is not lent again`. Both pass. [Scenarios](concepts/scenarios.md) tells
what each part of a scenario checks.

<a id="create-the-tables"></a>

## 5. Create the tables

The engine keeps its *log* and its other data in its own tables. Generate an empty migration with
`mix ecto.gen.migration add_eh_os_contract`, and call the migrations of Oban and of the engine:

```elixir
defmodule MyApp.Repo.Migrations.AddEhOsContract do
  use Ecto.Migration

  def up do
    Oban.Migration.up()
    EhOsContract.Migrations.up()
  end

  def down do
    EhOsContract.Migrations.down()
    Oban.Migration.down()
  end
end
```

`EhOsContract.Migrations` does not create the tables of Oban. If your application runs Oban
already, remove the two `Oban.Migration` lines. Do not change this migration later. When a release
raises `EhOsContract.Migrations.current_version/0`, generate a new migration that calls
`EhOsContract.Migrations.up(version: N)` and `down(version: N)`. `N` is the new value of
`current_version/0`.

**Result:** `mix ecto.migrate` creates the tables whose names start with `eh_os_contract_`.

<a id="configure-and-start"></a>

## 6. Configure and start the engine

Tell the engine which OTP applications hold your contracts, and which repo to use:

```elixir
config :eh_os_contract,
  applications: [:my_app],
  repo: MyApp.Repo
```

Add `EhOsContract` to the supervision tree, after the repo and Oban:

```elixir
children = [
  MyApp.Repo,
  {Oban, Application.fetch_env!(:my_app, Oban)},
  EhOsContract,
  MyAppWeb.Endpoint
]
```

At start, the engine finds the contracts and records which version of each contract runs. The
report needs this record. The engine also starts a runner for each consumer that reads the log
after the commit.

In `config/test.exs`, stop these runners:

```elixir
config :eh_os_contract, subscriptions: :manual
config :my_app, Oban, testing: :manual
```

A test that needs a runner, an effect or a timer calls `EhOsContract.Testing.drain/1`.

Oban must run the queue `:events`, which holds the jobs of the effects and of the timers of process
managers. Add it to the configuration of Oban in `config/config.exs`:

```elixir
config :my_app, Oban, repo: MyApp.Repo, queues: [events: 10]
```

If Oban does not run this queue, the jobs stay in the table. No effect runs, and no timer fires.

Mark `async: false` on each test that writes the log. Each append holds one lock until its
transaction ends. In the Ecto sandbox, a transaction lasts for the whole test. Two such tests wait
for each other, and one fails on the timeout of the repo.

If a contract declares a personal field, give a master key before you start the application.
Without one, the application does not start. Each key is 32 bytes in Base64, with an id. The current
key is first.

In production, read the key from the environment in `config/runtime.exs`. Do not commit a key of
production:

```elixir
if config_env() == :prod do
  config :eh_os_contract, EhOsContract.Vault,
    keys: [{"2026-09", System.fetch_env!("EH_OS_CONTRACT_KEK")}]
end
```

For development and tests, write a separate key, which protects no real data, in `config/dev.exs`
and `config/test.exs`.
[Subjects and personal data](concepts/domain-data.md#subjects-and-personal-data) tells how to rotate
a key.

[The configuration](configuration.md) lists each other key. The engine does not start with a key
that it does not know.

**Result:** the application starts. `mix eh_os_contract.check` does not warn `no-contracts`. If it
does, `applications:` names the wrong application: the engine found no contract in it.

<a id="dispatch-a-command"></a>

## 7. Dispatch a command

Send the command from your own code, with an *actor*. An actor of a person carries the
*capabilities* that its credential grants. For `lend_copy`, the capability is
`getting_started.lend_copy`.

Build an actor by hand only to try the engine, or in a test.
`EhOsContract.Actor.credential/3` verifies nothing. In production, a verified credential gives the
actor: `EhOsContract.call/3` and `EhOsContract.Plug` take one.
[Authorization](authorization.md) tells how.

```elixir
alias GettingStarted.Contracts.Loans

# To try the engine only: this actor has the capability without a credential.
actor = EhOsContract.Actor.credential("librarian-1", ["getting_started.lend_copy"])

EhOsContract.dispatch(Loans, %Loans.Commands.LendCopy{copy_id: "c-1", member_id: "m-1"},
  actor: actor
)
```

![Dispatch checks the actor, then in one transaction reads and folds the unit, gets the decision, appends the declared events and runs the consumers.](img/dispatch.svg)

1. The application gives the command and the actor to `EhOsContract.dispatch/3`.
2. For an actor from a credential, dispatch asks the *authorizer* if the actor has the capability.
   Without configuration, this is `EhOsContract.Authorizer.Default`. A `:system` actor must be in
   the `by:` of the command. Then dispatch checks the fields of the command.
3. Dispatch starts one transaction. In it, dispatch reads the stream of the loan `c-1`.
4. `evolve/2` gets each event of the stream, in order, and returns the state.
5. `lend_copy/2` gets the command and the state. It returns `copy_lent`, or a rejection on
   `lent_once`.
6. Dispatch writes `copy_lent` to the log. An event that the command does not declare stops the
   dispatch, and the log gets nothing.
7. The read models, policies and effects delivered `:in_transaction` run now. Dispatch also inserts
   an Oban job for each effect delivered `:at_least_once`.
8. Dispatch commits its transaction and returns the result. The engine also records a refused
   command.
9. The read models, policies and process managers delivered `:at_least_once` read the new events
   from the log. Oban runs the jobs of the effects.

Keep each consumer delivered `:in_transaction` to the database. Each append holds one lock until its
transaction commits. While such a consumer runs, each other append to the log waits.
[Reactions](concepts/reactions.md) tells how to choose the delivery.


**Result:** dispatch returns `{:ok, %EhOsContract.Receipt{}}`, with a `%CopyLent{}` struct in
`events`. Dispatch the same command again, and it returns
`{:error, %EhOsContract.Rejection{invariant: :lent_once}}`.

<a id="follow-one-piece-of-work"></a>

## 8. Follow one piece of work in the logs

Each command belongs to a piece of work, which a UUID identifies. Give the UUID as
`correlation_id:` in the options of dispatch, or as the header `x-correlation-id` over HTTP.
Without one, the engine makes a new one.

The engine puts the value in the metadata of the Logger, as `correlation_id`. It does this while it
runs the command, and while it reacts to an event, a timer or a message of that work. After that,
the metadata has its earlier value again. Add the key to the metadata of your formatter:

```elixir
config :logger, :default_formatter, metadata: [:request_id, :correlation_id]
```

The engine writes the value in lower case, as the log keeps it. An erasure belongs to no piece of
work, so it sets no value. A value that is not the text of a UUID, for example from a message of
another application, also sets none.

**Result:** each line that the Logger writes for the work shows its `correlation_id`. You
can follow one piece of work across applications.

<a id="check-draw-and-report"></a>

## 9. Check, draw and report

```
mix eh_os_contract.check
mix eh_os_contract.schema
mix eh_os_contract.graph --contract getting_started.loans --output loans.json
mix eh_os_contract.view
mix eh_os_contract.report --since 2026-07-01T00:00:00Z
```

- `mix eh_os_contract.check` reports errors, warnings and notices about the model. Run it in CI.
  It fails when it finds an error. With `--warnings-as-errors`, a warning also fails it. [The rules](rules.md) give the reason
  for each finding.
- `mix eh_os_contract.schema` records the fields of each event in `eh_os_contract.lock`. Commit
  the file. Run `mix eh_os_contract.schema --check` in CI too: it fails when the events differ from the
  file.
- `mix eh_os_contract.graph` writes the graph of the contract as a JSON document.
- `mix eh_os_contract.view` shows the domain as a tree.
- `mix eh_os_contract.report` answers [the four questions of conformance](glossary.md#four-questions)
  for each contract and process module, for a period.

**Result:** the check names each finding with its rule. The report has a section
`CONTRACT: getting_started.loans`. [The command-line tasks](cli.md) list each task and its options.

## Next steps

- [What is eh_os_contract?](introduction.md): what the engine does, and what it does not do.
- [Write a domain, a contract and a process module](contract.md): the full task, with a process
  module and its promises.
- The concepts: [the domain](concepts/domain.md), [actors, personal data and values](concepts/domain-data.md),
  [units that decide](concepts/units.md), [reactions](concepts/reactions.md), [reading](concepts/reading.md),
  [forms](concepts/forms.md), [between contracts](concepts/between-contracts.md),
  [processes](concepts/process.md) and [scenarios](concepts/scenarios.md).
- [The Claude Code plugin](https://github.com/EmpoweredHouse/eh-os-contract/blob/main/plugins/eh-os-contract/README.md):
  skills that write contracts by the rules of this engine.
