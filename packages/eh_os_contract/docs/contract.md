# Write a domain, a contract and a process module

<!-- covers: entities domain.subdomain, domain.context, domain.actor, contract.aggregate, contract.scenario, process.correlate, process.stage, process.ends_on, process.promise, process.deadline, process.scenario -->

This page tells how to describe a business as Elixir modules that the engine reads. It is for a
developer who writes the model of an application. Each step has an example that compiles. Each word
has one meaning, in [the glossary](glossary.md).

You describe a business in up to three kinds of module:

- A *domain* contains the words of the business, its contexts, its actors and the external systems
  that it uses.
- A *contract* belongs to one context. It contains the units that decide, their commands and events,
  the reactions to the events, the read models and the queries.
- A *process module* describes one kind of run of the business, across one or more contracts, and the
  promises about each run. A business with no run, such as a register of rooms, needs none.

The engine reads these modules. At compile time, it refuses a model that contradicts itself and code
that contradicts the model. At run time, it dispatches commands, appends the events to its log, and
compares the log with the contracts and the process modules.

<a id="before-you-start"></a>

## Before you start

- Add `eh_os_contract` to the dependencies of your application, as
  [Getting started](getting-started.md) tells.
- Add the compiler `:eh_os_contract` after the compilers of Elixir, in `project/0` of `mix.exs`:

  <!-- not compiled: a line of the host's mix.exs -->
  ```elixir
  compilers: Mix.compilers() ++ [:eh_os_contract]
  ```

  This compiler checks the rules between modules. A contract names its domain without a compile
  dependency, so Elixir alone does not check these rules.

<a id="what-is-checked-at-which-time"></a>

## What is checked at which time?

The engine checks a model in five layers. The first four layers stop the compile when a model breaks a
rule. The fifth layer is a task that you run.

![While Elixir compiles, the engine checks the schema, one module and the implementation; then the compiler eh_os_contract checks between modules; the check task reports.](img/contract-checks.svg)

1. **Schema.** Spark checks the keys of each declaration: a key that is not known, a missing key, a
   value of the wrong type.
2. **One module.** The engine checks the rules of one domain, contract or process module. The message
   gives the file and the line.
3. **Implementation.** The macros of an implementation check the code at the line that breaks a rule.
4. **Between modules.** After Elixir compiles the project, the compiler `:eh_os_contract` checks a
   contract against its domain and its sibling contracts.
5. **The check.** `mix eh_os_contract.check` reports what the compiler cannot hold: errors, warnings and
   notices. An error makes the task fail. With `--warnings-as-errors`, a warning makes it fail too.

Each refusal of layers 2 to 4 starts with its code. [The compile refusals](refusals.md) list each
code. [The rules of the check](rules.md) list what layer 5 reports.

## Write the domain

The domain names the application, its contexts and its actors. Write it first, because each contract
names its domain.

```elixir
defmodule Lending.Domain do
  use EhOsContract.Domain, name: :lending, language: :en

  subdomain :core, "Core", type: :core

  context :loans, "Loans", subdomain: :core

  actor :librarian, :human, "Librarian"
end
```

- `name:` is the name of the application. Each capability of a person starts with it, for example
  `lending.open_loan`. Each name that a contract publishes starts with it too.
- The name is one segment: lowercase letters, digits, `_` and `-`. It starts with a letter and does
  not end with `-`, for example `:"my-shop"`. The compiler refuses another name
  ([`D11`](refusals.md#refusals-d)).
- `language:` is the language of the labels. A label is the word of the people in the business. The
  engine shows each label as you write it.
- `code_language:` is the language of the identifiers. It is English if you do not give it.
  `mix eh_os_contract.check` compares the names in a contract with the translations of the terms.
- `time_zone:` is the zone of the business days, for example `"Europe/Warsaw"`. It is UTC if you do
  not give it.
- The engine tags each required timestamp of an event with its day in that zone. For a zone other than
  UTC, configure a time zone database: `config :elixir, :time_zone_database`.
- The compiler refuses a zone that the time zone database does not know
  ([`D13`](refusals.md#refusals-d)).

[The domain](concepts/domain.md) tells how to add the glossary of a context and the relations between
contexts. [Actors, values, entities and external systems](concepts/domain-data.md) tells how to add them.
[Personal data](concepts/personal-data.md) tells how to add subjects and personal fields.

## Write a contract

A contract describes what the units of one context decide. Give each contract an `id:`: the name of
the domain, then segments in dotted snake_case, for example `"lending.loans"`.

Do not change the `id:` of a contract that has events in the log. The id is the start of the type of
each event, for example `"lending.loans.loan_opened"`. After a change, the engine does not read the
old rows as those events. A change of the module name is safe, because the log names a contract by
its id.

```elixir
defmodule Lending.Contracts.Loans do
  use EhOsContract.Contract, domain: Lending.Domain, context: :loans, id: "lending.loans"

  aggregate :loan, "Loan of a copy" do
    identity :loan_id

    state do
      field :returned, :boolean, default: false
    end

    invariant :returned_once, "A loan is returned once"

    command :open_loan, "Lend a copy", by: :librarian, emits: :loan_opened do
      field :copy_id, :id
      field :member_id, :id
    end

    command :return_copy, "Take a copy back",
      by: :librarian,
      emits: :copy_returned,
      rejects: :returned_once

    event :loan_opened, "Copy lent" do
      field :copy_id, :id
      field :member_id, :id
    end

    event :copy_returned, "Copy returned"
  end

  scenario "a copy is lent" do
    command :open_loan, %{copy_id: "c-1", member_id: "m-1"}
    expect :loan_opened
  end

  scenario "a returned copy is not returned twice" do
    given :loan_opened, %{copy_id: "c-1", member_id: "m-1"}
    given :copy_returned
    command :return_copy
    rejected :returned_once
  end
end
```

The example declares these parts:

- **The aggregate `:loan`.** It decides over one stream: the events of one loan. The engine adds the
  identity `loan_id` to its state, its commands and its events.
- **The state.** It is what the aggregate remembers between two decisions.
- **The invariant `:returned_once`.** It is a rule that must stay true.
- **The commands.** `by:` names the actors that can issue a command. Dispatch refuses another actor
  before it does anything else.
- **What a command can do.** `emits:` names the events that a command can produce. `rejects:` names
  the invariants that it can reject on.
- **The events.** Each event is something that occurred. The log keeps them.
- **The scenarios.** Each scenario gives events that occurred, a command, and the events or the
  rejection that follow. Each invariant needs a scenario that ends in `rejected`
  ([`S8`](refusals.md#refusals-s)).

Run the scenarios as tests. Add this line to a test module:

<!-- not compiled: a line of the host's test module -->
```elixir
use EhOsContract.ScenarioCase, contract: Lending.Contracts.Loans
```

The result is one ExUnit test for each scenario, against your implementation.
[Scenarios](concepts/scenarios.md) tells what each kind of scenario checks.

A contract describes what its units decide, not the run that they make. A loan from lending to
return is a run. Write it in a [process module](#write-a-process-module).

## Implement the unit

The implementation is the module that decides. It points to the contract with `use`. The contract
generates a struct for each command and event. It also generates a behaviour: one callback for each
command, and `evolve/2` when the unit keeps a state.

```elixir
defmodule Lending.Loan do
  use Lending.Contracts.Loans, aggregate: :loan

  @impl true
  def open_loan(%OpenLoan{} = command, _state) do
    emit(%LoanOpened{
      loan_id: command.loan_id,
      copy_id: command.copy_id,
      member_id: command.member_id
    })
  end

  @impl true
  def return_copy(_command, %State{returned: true}), do: reject(:returned_once)
  def return_copy(%ReturnCopy{loan_id: id}, _state), do: emit(%CopyReturned{loan_id: id})

  @impl true
  def evolve(state, %LoanOpened{}), do: state
  def evolve(state, %CopyReturned{}), do: %{state | returned: true}
end
```

- `emit/1` takes the struct literals of the events that the command produces. The compiler refuses
  an event outside the `emits:` of the command ([`I4`](refusals.md#refusals-i)).
- `reject/1` names an invariant from the `rejects:` of the command
  ([`I5`](refusals.md#refusals-i)).
- `evolve/2` folds each event into the state. The engine calls it for each event of the stream, in
  order.
- To see what the contract says about a callback, type
  `b Lending.Contracts.Loans.Aggregates.Loan.open_loan` in IEx.

Tell the engine where your implementations are: `config :eh_os_contract, applications: [:lending]`.
A unit whose events are all recorded needs no implementation if its state is only its identity. If it
keeps more state, its implementation has only `evolve/2`, to fold the recorded events.
[Units](concepts/units.md) tells more about the code that decides.

<a id="which-module-names-which"></a>

## Which module names which?

The implementation names its contract, and the contract names its domain. A contract never names its
implementation. So a change to the code does not compile the contract again.

![The implementation uses the contract, the contract and the process module name the domain, the process module includes events of the contract, and the contract names neither.](img/contract-modules.svg)

1. The implementation uses the contract. This is a compile dependency: the contract compiles first.
2. The contract names its domain with `domain:`. This makes no compile dependency. The compiler
   `:eh_os_contract` checks the name.
3. The process module names its domain with `domain:`, as a contract does.
4. The process module includes events of the contract in its stages. This makes no compile dependency.

## Dispatch a command

Send a command with `EhOsContract.dispatch/3`, with the actor that your application authenticated:

<!-- not compiled: a call in the host's code -->
```elixir
alias Lending.Contracts.Loans

command = %Loans.Commands.OpenLoan{loan_id: id, copy_id: copy, member_id: member}
EhOsContract.dispatch(Loans, command, actor: actor)
```

If the unit accepts the command, the result is `{:ok, receipt}`. The receipt holds the events that the
engine appended. If the unit rejects the command, the result is `{:error, %EhOsContract.Rejection{}}`,
and the log gets no event. [Authorization](authorization.md) tells how a credential becomes an actor.

<a id="write-a-process-module"></a>

## Write a process module

A process module describes one kind of run, with events from one or more contracts. It names the
fields that tell one run from another, the stages, the events that end a run and the deadline. It
also holds the promises and their scenarios.

```elixir
defmodule Lending.Processes.Loan do
  use EhOsContract.Process,
    id: "lending.loan",
    domain: Lending.Domain,
    label: "A loan, from lending to return",
    accountable: :librarian

  correlate :loan_id

  stage :lending, include: [{Lending.Contracts.Loans, :loan_opened}]
  stage :return, "Return", include: [{Lending.Contracts.Loans, [:copy_returned]}]

  ends_on :copy_returned

  promise :returned_within_a_month do
    from :loan_opened
    eventually :copy_returned
    within {30, :day}
  end

  deadline {60, :day}

  scenario "returned on the twentieth day — kept", verdict: :satisfied, via: :eventually do
    given :loan_opened, %{loan_id: "l-1", copy_id: "c-1", member_id: "m-1"},
      at: "2026-09-01T09:00:00Z"

    given :copy_returned, %{loan_id: "l-1"}, at: "2026-09-20T09:00:00Z"
    promise :returned_within_a_month, at: "2026-10-15T09:00:00Z"
  end
end
```

- `id:` and `label:` are required. The `id:` has the same form as the `id:` of a contract.
- `correlate` names the fields that tell one run from another. Each event that the process includes
  carries them.
- `include:` names a contract and one or more of its events. After that, name an included event by
  its name alone.
- `ends_on` names the events that end a run. `deadline` is the longest time from the first event to
  the end.
- A `promise` says that after the event in `from`, the event in `eventually` follows within the time
  in `within`.
- Show each promise with a `scenario`. `given` lists the events, and `promise … at:` gives the moment
  of judgement.
- `verdict:` is the verdict that the promise must get. `via:` is the route that kept it.

Each given holds the identity of its unit and the required fields that its contract declares
([`X9`](refusals.md#refusals-x)). If the
domain declares an external system, a scenario can show that it was not available:
`outage :catalogue, at: "2026-09-10T08:00:00Z"`. The events in `eventually` or `or_else` must depend
on that system, or the promise names it in `waits_on` ([`X4`](refusals.md#refusals-x)).

Run these scenarios with `use EhOsContract.ScenarioCase, process: Lending.Processes.Loan`. The result
is one test for each scenario, without a database. [Processes](concepts/process.md) tells how the
engine judges runs, promises and deadlines.

## Do more in a contract

| Task | Page |
| --- | --- |
| Give an aggregate statuses and the transitions between them | [Units](concepts/units.md) |
| Decide over the events of more than one stream | [Units](concepts/units.md) |
| Change an event that already has rows in the log | [Units](concepts/units.md) |
| React to an event with a policy, an effect or a process manager | [Reactions](concepts/reactions.md) |
| Keep a read model and answer a query | [Reading](concepts/reading.md) |
| Take events of another contract, or of another application | [Between contracts](concepts/between-contracts.md) |
| Issue a command from a form | [Forms](concepts/forms.md) |
| Mark personal data, and erase a subject | [Personal data](concepts/personal-data.md) |
| Rotate a master key | [Manage the master keys](concepts/master-keys.md) |

### Let only one person issue a command

Some rules name a person, not a role. Example: only the librarian who lent a copy takes it back.
Add `actor_is` to the command, with a field of the state that names the person. Declare the invariant
that dispatch rejects on. The command that opens the loan carries the librarian, and its event keeps
the librarian:

<!-- in: Lending.Contracts.Loans, aggregate :loan -->
```elixir
state do
  field :returned, :boolean, default: false
  field :librarian_id, :id, optional: true
end

invariant :returned_where_lent, "A copy is taken back by the librarian who lent it"

command :return_copy, "Take a copy back",
  by: :librarian,
  emits: :copy_returned,
  rejects: [:returned_once, :returned_where_lent] do
  actor_is :librarian_id, or_rejects: :returned_where_lent
end

command :open_loan, "Lend a copy", by: :librarian, emits: :loan_opened do
  field :copy_id, :id
  field :member_id, :id
  field :librarian_id, :id, optional: true
end

event :loan_opened, "Copy lent" do
  field :copy_id, :id
  field :member_id, :id
  field :librarian_id, :id, optional: true
end
```

Your application gives `librarian_id`: the subject of the credential of the librarian. The
implementation copies the field into the event, and `evolve/2` folds it into the state:

<!-- and in: Lending.Loan -->
```elixir
def open_loan(%OpenLoan{} = command, _state) do
  emit(%LoanOpened{
    loan_id: command.loan_id,
    copy_id: command.copy_id,
    member_id: command.member_id,
    librarian_id: command.librarian_id
  })
end

def evolve(state, %LoanOpened{librarian_id: id}), do: %{state | librarian_id: id}
def evolve(state, %CopyReturned{}), do: %{state | returned: true}
```

Show the rejection in a scenario. `as` names the person who issues the command
([`S7`](refusals.md#refusals-s)):

<!-- and in: Lending.Contracts.Loans -->
```elixir
scenario "a copy is not taken back by another librarian" do
  actor :librarian
  as "librarian-ola"
  given :loan_opened, %{copy_id: "c-1", member_id: "m-1", librarian_id: "librarian-jan"}
  command :return_copy
  rejected :returned_where_lent
end
```

- An earlier event fills the field. It is a non-personal `:id` of the state
  ([`A9`](refusals.md#refusals-a)).
- Dispatch compares the field with the subject of the credential, after it folds the state.
- If they are not equal, dispatch rejects the command on the invariant in `or_rejects:`. The log gets
  a rejected command and no event.
- If the field is empty, dispatch rejects each person. With `optional: true`, a loan that names no
  librarian is valid, and nobody takes its copy back through this command.
- A `:system` actor and a reaction act for the application. Dispatch does not compare them.
- A role gives no exception. If a person must act on the unit of another person, declare a command
  for it.

### Take a field from the host

Some fields of a decision are not the caller's to give. Example: the system at the desk knows if a
copy was scanned. Declare such a field with `supplied_by: :host`:

<!-- in: Lending.Contracts.Loans, command :open_loan -->
```elixir
field :scanned, :boolean, supplied_by: :host
```

A scenario of the command gives the value, as the supplier does at run time
([`S3`](refusals.md#refusals-s)):

<!-- and in: Lending.Contracts.Loans -->
```elixir
scenario "a copy is lent" do
  command :open_loan, %{copy_id: "c-1", member_id: "m-1", scanned: true}
  expect :loan_opened
end
```

1. Write a module that implements `EhOsContract.Supplier`.
2. Configure it: `config :eh_os_contract, supplier: MyApp.Supplier`.

- Through `EhOsContract.call/3` and `EhOsContract.Plug`, a request that sends the field is refused
  with `{:invalid, [scanned: :supplied]}`.
- After the engine authorizes the caller, the supplier gives the value.
- If the supplier cannot give it, the result is `{:not_supplied, reason}`, an HTTP 503. The engine
  writes nothing.
- A call of `dispatch/3` from your own code is trusted, as each other field of the struct is. The
  engine asks the supplier only if you pass `supply: true`, as a form does
  ([Forms](concepts/forms.md)).
- Only a field of a command, or of a recorded event, can be supplied
  ([`F10`](refusals.md#refusals-f)).
- A node that has such a field and no supplier does not start.

### Use an entity in a decision

A decision can need an entity that your application keeps outside the log. Example: a member with a
suspended card cannot borrow a copy.

1. Declare the entity in the domain, with its fields:
   `entity :card, "Membership card", context: :loans, identity: :card_id`.
2. Give the command a required field of type `{:id, :card}`, and add `reads: [card: :card_id]`
   ([`A8`](refusals.md#refusals-a)).
3. Configure the module that gives the rows: `config :eh_os_contract, entities: MyApp.Entities`.
4. Take the row as the third argument of the callback: `%{card: %{card_id: "c-1", suspended: false}}`.

- Dispatch asks `EhOsContract.Entities` for the row before the decision, as the actor of the command.
- If the row does not exist, dispatch refuses the command with `{:invalid, [card_id: :unknown]}`.
- The engine keeps the row that it read with the record of the command.
- Only an actor in `by:` can issue such a command. A policy or a process manager cannot.
- In a scenario, give the row with `given_entity :card, %{card_id: "c-1", suspended: false}`
  ([`S12`](refusals.md#refusals-s)).
- A node that has such a command and no `EhOsContract.Entities` does not start.

## What can go wrong

- **The compiler refuses the model.** Find the code of the message in
  [the compile refusals](refusals.md).
- **`mix eh_os_contract.check` gives a warning.** Find its rule in [the rules of the check](rules.md).
- **The check gives errors for the rules between modules.** The compilers do not include
  `:eh_os_contract`. Add it, as [Before you start](#before-you-start) tells, so that the compile
  stops on these errors.
- **The decision emits an event outside `emits:`.** Dispatch raises an exception and appends nothing.
  This is a defect in the code, not an answer of the business.

## Next steps

- [Units](concepts/units.md): aggregates, consistency boundaries and the code that decides.
- [Scenarios](concepts/scenarios.md): what each kind of scenario checks.
- [Processes](concepts/process.md): runs, stages, promises and deadlines.
- [The compile refusals](refusals.md): each refusal of the compiler, with its code.
- The DSL reference: each key of [the domain](dsl/domain-dsl.md),
  [the contract](dsl/contract-dsl.md) and [the process module](dsl/process-dsl.md).
