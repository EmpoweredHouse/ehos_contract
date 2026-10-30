# Writing a domain and a contract

A business is written down in up to three kinds of module. A **domain** holds the words its people use,
the contexts it is split into, who acts in it and which systems it depends on. A **contract** belongs to one
context and holds what its units decide, what happened, what reacts to it and what is read. A
[**process module**](#process-modules) holds a run of the business, across one or more contracts, and what
was promised about it; a business with no run, such as a register of rooms, needs none. All are Elixir
modules on [Spark](https://hexdocs.pm/spark), in the manner of [ESDM](https://www.esdm.io): the model is
code, and there is nothing beside it. Each word has one meaning, in [the glossary](glossary.md).

The engine reads them twice. At compile time it refuses a model that contradicts itself and code that
contradicts the model. At run time it dispatches commands through the model, appends what they decide to
its own log, and compares what the log holds with what the contracts and process modules declare.

This page is how to start and what will not compile. Every key of the three DSLs, with its type, default and
description, is in the generated reference: [the domain](dsl/domain-dsl.md), [the contract](dsl/contract-dsl.md)
and [the process module](dsl/process-dsl.md).
What `mix eh_os_contract.check` reports about a model that compiles is in [its rules](rules.md).

## A domain

<!-- covers: entities domain.subdomain, domain.context, domain.actor -->

```elixir
defmodule Lending.Domain do
  use EhOsContract.Domain, name: :lending, language: :en

  subdomain :core, "Core", type: :core

  context :loans, "Loans", subdomain: :core

  actor :librarian, :human, "Librarian"
end
```

`name:` is the application's name towards EHOS: capabilities are `lending.<command>` and roles
`lending.<actor>`, and every name its contracts publish begins with `lending.`. So it is one segment of a
namespace (lowercase letters, digits, `_` and `-`, starting with a letter and not ending with a dash, like
`:"my-shop"`), and a domain named otherwise does not compile ([`D11`](refusals.md#refusals-d)). `language:` is the language the labels
are written in. Labels are the words of the people in the process, in their language, and the engine prints
them as written. `code_language:`, English unless given, is the language identifiers are written in. The check
holds the names of the context's contracts to each term's translation into that language. `time_zone:`, UTC unless given, is the zone the business's days are in, like `"Europe/Warsaw"`:
an event's required timestamps are tagged with the day they fall on there, which the host's configured time zone
database answers (`config :elixir, :time_zone_database`); a zone it does not know does not compile ([`D13`](refusals.md#refusals-d)).

An actor may name what it answers for, `responsibility :overdue_reports, "…", source: "P-25"`, prose a page
shows and nothing runs. A relation between contexts may pair the words each side uses for the same thing,
`terms: [{"Visit", "Encounter"}]`, the first end's word and the second's, each a term of its context's
glossary; the glossary shows, under a term, what the other end calls it.

An entity is one in Evans's sense: a thing with an identity that lasts while its attributes change. Its
lifecycle is kept by the application's code or another system, outside this log; contracts point at it by its
identity, as a field `{:id, :copy}`. `entity :copy, "Copy", context: :loans, identity: :copy_id` declares it,
and the library injects `copy_id` into its fields as a required, non-personal `:id`, as it injects a unit's
identity; `issued_by: :catalogue` names the external that gives it, when one does.

## A contract

<!-- covers: entities contract.aggregate, contract.policy, contract.subscribe, contract.scenario -->

A contract belongs to one context of one domain. It names itself, `id: "lending.loans"` on its
`use`: the domain's `name:`, then dotted snake_case segments, unique in the application. The id types every event the
contract records: `"lending.loans.loan_opened"`. Renaming the id, or moving an event to a contract with another id,
changes the type of every event it covers, and the log's old rows are no longer read as those events. Rows and keys
name the contract by its id, not its module, so renaming the module keeps its history.

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

- **An aggregate decides over one stream**, the one its identity names. Its state is what it remembers
  between decisions, its invariants what must stay true, its commands what it is asked, and its events what
  it decides. `identity` is injected into its state, commands and events. A consistency boundary that spans
  streams is a `dcb`, which `consults` the events it decides over.
- **A field can say which unit it identifies**, as it says which entity: `field :loan_id, {:id, :loan}`. The
  name is an entity of the domain or a unit of one of its contracts, and exactly one of them
  ([`X3`](refusals.md#refusals-x)); a unit is looked for among the contracts the project compiles, so a domain's contracts
  compile in one project. A unit keyed by another unit's number says so in its identity, `identity loan_id:
  {:id, :loan}`, or `identity [:period_id, loan_id: {:id, :loan}]` beside fields of its own. The log sees a
  plain `:id`; `mix eh_os_contract.check` counts a reference to another context's unit as one into that
  context, against the context map, and the pages link the field to the unit. A command never `reads:` a
  unit, whose state is its events ([`A8`](refusals.md#refusals-a)).
- **A key with rules of its own is typed by a domain value.** A unit keyed by a month, a year or a fiscal
  period names the value in its identity, `identity [:company_id, period_id: :period]`, and dispatch holds
  the key to the value's invariants as it holds any field: a command or a recorded event whose key breaks
  one is refused with `{:period_id, {:invariant, name}}` before any stream is read. The value rests on
  `:id`, since the key names the stream and tags the unit's events ([`F1`](refusals.md#refusals-f)); a generated
  identity is a UUID and takes no value.
- **An aggregate may declare its lifecycle**: the statuses its decisions depend on, in the client's words,
  the `initial` one each first event starts it in, and the `transition`s events make between them, for example
  `transition :booked, :patient_arrived, :in_progress`. A transition names an event type and nothing about
  its fields, so the graph is checked as it compiles: every status reached, and only a `final:` one without a way out.
  A command may name the statuses it is issued in, `from: :booked`, with the invariant it is refused on in
  any other, `or_rejects: :only_a_booked_visit`. **The engine computes the status** from the names of the
  stream's events and puts it into the state as `status`, which `evolve/2` reads and never sets. Dispatch
  refuses a command outside its `from:` before the decision; an event the decision emits that the graph does
  not allow from where the aggregate stands raises, as one outside `emits:` does, and nothing is appended.
  An event no transition names is allowed in every status that is not final, once an initial event has
  started the aggregate; a recorded event that does not fit is appended and moves nothing. A boundary has no
  lifecycle: it spans streams.
- **A command names who may issue it** (`by:`), what it may emit, and which invariants it may refuse on.
  Dispatch refuses an actor outside `by:` before anything else. An event outside `emits:` after the
  decision raises: it is a defect in the code, never a business outcome, and nothing is appended.
- **A contract describes what its units decide, not the run they make.** A loan from lending to return, or a
  visit from booking to its report, is a [process](#process-modules): a module of its own that names the events of
  the run, from 1 contract or several, and what was promised about it. A contract whose units only
  decide and record, such as a register of equipment or of rooms, needs no process.
- **A scenario is a test the contract carries**: given events, when a command, then events or a
  rejection. Every invariant needs a `rejected` scenario ([`S8`](refusals.md#refusals-s)). `EhOsContract.ScenarioCase` turns each into
  an ExUnit test against the implementation; a scenario that records an event, which nothing decides, runs
  none, and is held to what `EhOsContract.record/3` checks:

  ```elixir
  use EhOsContract.ScenarioCase, contract: Lending.Contracts.Loans
  ```

  Unless a given says when, its event happened 1 minute after the given before it, and the first one at
  2026-01-01 09:00 UTC. A given says when like this: `given :loan_opened, %{copy_id: "c-1"}, at: "2026-09-01T09:00:00Z"`.
  The moment is an ISO 8601 timestamp with an offset, never earlier than the given before it, since a log holds
  events in the order they happened. A given without a moment does not come before one with it ([`S3`](refusals.md#refusals-s)).

- **The implementation reads the contract where it is written.** Each callback of a generated behaviour
  carries what the contract says of it: the declaration's label and source, what it may emit or issue,
  the rules that hold there (each with the scenario that refuses on it or illustrates it, or marked
  prose alone), and its scenarios. `b Lending.Contracts.Loans.Aggregates.Loan.open_loan` in IEx prints it.

What reacts to events is declared beside the units: a `policy` issues a command of this contract, an
`effect` calls an external system, naming one of its `operation`s (`calls: {:p1, :submit_report}`) when
the domain says what the system does; and a `process_manager` steers a run with its own state and timers.
A `read_model` is not a reaction: it projects rows that a `query` reads.

A reaction names its rules as a command does, with
`constraint`, and a process manager its `invariant`s too; a scenario that names one in `illustrates:`
is the test that it holds, and `mix eh_os_contract.check` warns of one no scenario illustrates. An
effect's constraint stays prose, since no scenario runs an effect. A process manager's scenario may also
say the `state` its run holds after the trigger, `state %{check_at: "2026-02-01T00:00:00Z"}`, which
`ScenarioCase` compares after folding the delivered event, as the engine does.

A reaction delivered
`:at_least_once` names what makes a second delivery harmless and who keeps it so, `idempotency: [key:
:event_id, owner: :downstream]`: its own code (`:self`), the system an effect calls, given the key
(`:downstream`), or the engine (`:infrastructure`), which keys the commands a policy issues. A policy or a
read model left without `delivery` runs `:in_transaction`, inside the transaction that records the event. So
one that takes an event of a sibling of another context has to declare it (**[`X10`](refusals.md#refusals-x)**), and
`mix eh_os_contract.check` warns of a declared `:in_transaction` there. `consumes` takes a sibling contract's events, and
`publish` lets one leave the application: its relay (`EhOsContract.Relay`) hands it to the configured
`EhOsContract.Bus`, from the first deploy of the `publish` on.

Say `Loans` publishes its loans with `publish :loan_opened, as: "lending.loan.opened.v1", from: :loan_opened,
fields: [:loan_id, :copy_id], idempotent_on: [:loan_id]`. A contract of **another application**, a
reservations service say, takes the event by that name, with the fields it reads:

```elixir
subscribe "lending.loan.opened.v1", as: :copy_lent do
  field :loan_id, :id
  field :copy_id, :id
end

policy :release_hold, "Release the hold on a lent copy", handles: :copy_lent, issues: :release_hold
```

The event never enters the subscriber's log: it arrives in an inbox (`EhOsContract.Inbox`), which commits its
row with what the policy dispatched and only then acknowledges. Since a read model, an effect and a process
manager read the log, **only a policy takes it** ([`D12`](refusals.md#refusals-d)); they react to what the policy's command records
instead. A second delivery finds the inbox row and is dropped, and so does the same event published again
under a new id when the publisher declares `idempotent_on:`, whose values make the message's key. The
subscriber asks for the capability `lending.loan.opened.subscribe`, the application's, which EHOS grants
and the transport delivers by.

Some fields a decision depends on are not the caller's to say, for example whether a loan's copy was scanned at the desk,
which the desk's own system knows. Such a field is declared `supplied_by: :host`: `field :scanned, :boolean, supplied_by:
:host`. Through `EhOsContract.call/3`, and so `EhOsContract.Plug`, a request that sends it at all is refused by
name, `{:invalid, [scanned: :supplied]}`; once the caller is authorized, the configured `EhOsContract.Supplier`
gives its value (`config :eh_os_contract, supplier: MyApp.Supplier`), and `{:not_supplied, reason}` (a 503)
when it cannot. The application's own `dispatch/3` is trusted, as every other field of its struct is. Only a
command's field, or a recorded event's, takes it ([`F10`](refusals.md#refusals-f)), and a node with such a field and no supplier does not
start.

A decision may depend on an entity the application keeps outside the log. For example, whether a member may
borrow another copy depends on the membership card, which the library's own system keeps. The domain declares the
entity (`entity :card, "Membership card", context: :loans, identity: :card_id`, with its fields). The command
names it by a field typed `{:id, :card}` and says it reads it: `reads: [card: :card_id]`. The field has to be the
command's own, required and typed `{:id, entity}`, and each name is given once. Only an actor in `by:` issues
such a command, never a policy or a process manager ([`A8`](refusals.md#refusals-a)). The decision then takes a third argument,
`%{card: %{card_id: "c-1", suspended: false}}`. It is the row the configured `EhOsContract.Entities` gives (`config
:eh_os_contract, entities: MyApp.Entities`), asked once per command before it is decided, as the actor who issued
it, with the fields the domain declares for the entity. A row that is not there refuses the
command as a field naming nothing, `{:invalid, [card_id: :unknown]}`, a 422. The row read is kept with the
command's record. A scenario of such a command gives the row with `given_entity :card, %{card_id: "c-1",
suspended: false}` ([`S12`](refusals.md#refusals-s)), its fields held to the entity's ([`X9`](refusals.md#refusals-x)). A node with
such a command and no `EhOsContract.Entities` does not start.

Some rules name a person, not a role: a loan is returned by the librarian who lent it, not by any librarian. Inside
the command, `actor_is :librarian_id, or_rejects: :returned_where_lent` says who must issue it: the person a field of
the unit's state holds, a non-personal `:id` that an earlier event filled ([`A9`](refusals.md#refusals-a)). Dispatch compares
it with the credential's subject after folding the state and before the decision. Anyone else is refused on the
invariant, with a `rejected` row, as a lifecycle's `from:` refuses. A field still empty names nobody, so every
person is refused. A `:system` actor and a reaction act for the application, and pass. There is no exception for a
role: a person who must act on another's unit does so through a command declared for it. A scenario names the
person with `as "librarian-ola"` beside its `actor` ([`S7`](refusals.md#refusals-s)), and is refused for anyone else.

<a id="process-modules"></a>

## A process

<!-- covers: entities process.correlate, process.stage, process.ends_on, process.promise, process.deadline, process.scenario -->

A run of the business is written as a process module, whether its events come from 1 contract or from several.
Examples: a loan from lending to return, or a visit booked, documented and reported by 3 parts of a practice. The module names
the run, what tells one run from another, its stages and the events of each contract they include, the events
that end a run, its promises, and how long a run may take:

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
end
```

`id:` and `label:` are required; `id:` is formed as a contract's is ([`D11`](refusals.md#refusals-d)). A stage's `include:` names a
contract and one of its events, or a list of them, and names the contract without a compile dependency, as
`consumes` does. Everywhere else in the module an included event is named by its name alone, so two includes
of one name are refused ([`N1`](refusals.md#refusals-n)). The module refuses what it can see is wrong in itself:

- no `correlate`, an empty one, 2 `correlate`s, or one naming a field twice ([`R2`](refusals.md#refusals-r));
- a `correlate` of more than 6 fields ([`F9`](refusals.md#refusals-f));
- no stage, a stage that includes nothing, or an `include:` entry naming no event or no contract module ([`R3`](refusals.md#refusals-r));
- a promise or `ends_on` naming an event it does not include, or `ends_on` twice ([`R5`](refusals.md#refusals-r));
- a duration not in a fixed unit or longer than 100 years, `deadline` twice, or a `deadline` with no `ends_on`, since a deadline measures a run to its end ([`R6`](refusals.md#refusals-r)).

It compiles to a
model `EhOsContract.Model.fetch/1` returns, of kind `:process`. Dispatch files every event the process includes
under a run of it, named by its `id:`; `mix eh_os_contract.report`
prints a section for each process module, and the check reads it too. How runs, promises and deadlines are
judged is in [processes](concepts/process.md).

A promise is shown with a scenario: the events that happened and when, the moments an external system was
seen unavailable, and the verdict the promise gets at a moment (`:satisfied`, `:violated`, `:pending` or
`:suspended`), with the route that kept it, when it was kept:

```elixir
scenario "returned on the twentieth day — kept", verdict: :satisfied, via: :eventually do
  given :loan_opened, %{loan_id: "l-1"}, at: "2026-09-01T09:00:00Z"
  given :copy_returned, %{loan_id: "l-1"}, at: "2026-09-20T09:00:00Z"
  promise :returned_within_a_month, at: "2026-10-15T09:00:00Z"
end
```

`outage :catalogue, at: "2026-09-10T08:00:00Z"` says an external system was seen unavailable at that moment. It
names a system that the events the promise waits on (`eventually` and `or_else`) depend on, or one the promise
names in `waits_on` ([`X4`](refusals.md#refusals-x)), since an outage of anything else excuses nothing.
`use EhOsContract.ScenarioCase, process: Lending.Processes.Loan` writes
1 test per scenario. The test builds each given as the event its contract declares, files it into its run and judges
the promise as the report would, without a database. A scenario judges exactly 1 promise of the module, and each
description is used once ([`S1`](refusals.md#refusals-s)). Its givens are events the process includes ([`S2`](refusals.md#refusals-s)). Their
data is held to the contract that declares each event, the unit's identity included, since runs and items are told
apart by it ([`X9`](refusals.md#refusals-x)). Every `at:` is a timestamp, and a given's is never earlier than the given before it
([`S3`](refusals.md#refusals-s)). The scenario names a verdict the promise can get, with `via:` only on `:satisfied` and `:or_else`
only for a promise that has one. It gives the event that opens the promise, and nothing after the moment of
judgement ([`S11`](refusals.md#refusals-s)).

## The code that decides

A contract names no implementation. A module binds to one of its declarations, and the contract generates
the structs and the behaviour that module implements. The structs live under the contract
(`Lending.Contracts.Loans.Commands.OpenLoan`, `Lending.Contracts.Loans.Events.LoanOpened`), and a module
bound to the unit has them by their short names:

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

`emit/1` takes the literal structs a command may produce (one, a list of them, or a `for` producing
them), and refuses at compile time one outside its `emits:`; `reject/1` names one of its `rejects:`.
Implementations point at the contract, never the other way round, so changing the code never recompiles
the contract, and the engine finds them in the running binary (`config :eh_os_contract, applications: [...]`).

A unit whose events all declare `recorded_by:` and whose state is only its identity has nothing to
implement: no command reaches it, and an integration records its events with `EhOsContract.record/3`. A
module with only the `use` for it adds nothing, and one with an `evolve/2` warns that no behaviour asks for
it. A unit that keeps more state than its identity still needs `evolve/2`, to fold what is recorded.

A command goes through `EhOsContract.dispatch/3`, with the actor the host authenticated:

```elixir
alias Lending.Contracts.Loans

command = %Loans.Commands.OpenLoan{loan_id: id, copy_id: copy, member_id: member}
EhOsContract.dispatch(Loans, command, actor: actor)
```

Who the actor is, and how the credential EHOS issues becomes one, is in [authorization](authorization.md).
## What will not compile

A model is checked at compile time and by `mix eh_os_contract.check`. Every refusal of the compiler,
with its code, is in [the compile refusals](refusals.md).

The rules between modules are a Mix compiler, because references between the modules record no compile
dependency. A host registers it after Elixir's:

```elixir
compilers: Mix.compilers() ++ [:eh_os_contract]
```
