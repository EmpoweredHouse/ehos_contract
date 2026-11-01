# What is a scenario?

<!-- covers: entities contract.scenario; rules reaction-without-scenario, prose-without-scenario, transition-without-scenario, recording-without-scenario -->

This page tells what a scenario is, how the engine runs it as a test, and which declarations need
one. It is for a developer who writes a contract, and for a process owner who reads its examples.
[The glossary](glossary.md) defines each word in italics.

A rule written as a label, such as "A copy is returned once", tells the developer what to keep. It
does not show that the code keeps it. A *scenario* is an example that shows it:

```
given   what occurred before   (events)
when    one trigger            (a command, an event for a reaction, a query, or an event recorded)
then    what follows           (events, a rejection, commands issued, a timer, rows answered)
```

- The contract holds its scenarios, in the words of the process owner. The owner reads each one and
  says if it is correct.
- The engine runs each scenario as a test of the implementation. It holds the result to the same
  rules that dispatch applies.
- A scenario uses no stubs and no mocks. It calls the callbacks of the implementation, with the
  structs that the contract makes.

## An example

A librarian lends a copy, and takes it back. A policy releases the hold on a lent copy. A query
lists the open loans of a member.

```elixir
defmodule Concepts.Scenarios.Domain do
  use EhOsContract.Domain, name: :scenarios_example, language: :en

  subdomain :core, "Core", type: :core

  context :desk, "Lending desk", subdomain: :core

  actor :librarian, :human, "Librarian"

  value :loan_weeks, :integer, label: "Weeks of a loan" do
    invariant :one_to_four_weeks, "A copy is lent for 1 to 4 weeks",
      violated_by: [0, 5],
      satisfied_by: [1, 4]
  end
end

defmodule Concepts.Scenarios.LoanWeeks do
  use Concepts.Scenarios.Domain, value: :loan_weeks

  @impl true
  def one_to_four_weeks(weeks), do: weeks in 1..4
end

defmodule Concepts.Scenarios.Contracts.Loans do
  use EhOsContract.Contract,
    domain: Concepts.Scenarios.Domain,
    context: :desk,
    id: "scenarios_example.loans"

  aggregate :loan, "Loan of a copy" do
    identity :loan_id

    invariant :returned_once, "A copy is returned once"

    lifecycle do
      status :lent, "Lent"
      status :returned, "Returned", final: true

      initial :lent, on: :copy_lent
      transition :lent, :copy_returned, :returned
    end

    command :lend_copy, "Lend a copy", by: :librarian, emits: :copy_lent do
      field :copy_id, :id
      field :member_id, :id
      field :weeks, :loan_weeks, optional: true
    end

    command :return_copy, "Take a copy back",
      by: :librarian,
      emits: :copy_returned,
      from: :lent,
      or_rejects: :returned_once,
      rejects: :returned_once

    event :copy_lent, "Copy lent" do
      field :copy_id, :id
      field :member_id, :id
    end

    event :copy_returned, "Copy returned"
  end

  aggregate :hold, "Hold on a copy" do
    identity :copy_id

    command :release_hold, "Release the hold", emits: :hold_released

    event :hold_released, "Hold released"

    event :hold_placed, "Hold placed at the counter", recorded_by: :librarian do
      field :member_id, :id
    end
  end

  policy :release_on_lending, "Release the hold on a copy that is lent",
    handles: :copy_lent,
    issues: :release_hold do
    constraint :the_lent_copy, "The hold released is the lent copy's, not another's"
  end

  read_model :open_loans, "Open loans", projects: [:copy_lent, :copy_returned] do
    field :loan_id, :id
    field :member_id, :id
  end

  query :open_loans_of_member, "A member's open loans", reads: :open_loans, by: :librarian do
    param :member_id, :id
    constraint :only_open, "A returned copy is not on the list"
  end

  scenario "a copy is lent" do
    command :lend_copy, %{copy_id: "c-1", member_id: "m-1"}
    expect :copy_lent, %{copy_id: "c-1"}
  end

  scenario "a lent copy comes back" do
    given :copy_lent, %{copy_id: "c-1", member_id: "m-1"}
    command :return_copy
    expect :copy_returned
  end

  scenario "a returned copy is not returned twice" do
    given :copy_lent, %{copy_id: "c-1", member_id: "m-1"}
    given :copy_returned
    command :return_copy
    rejected :returned_once
  end

  scenario "lending a copy releases its hold", illustrates: :the_lent_copy do
    target :release_on_lending
    on :copy_lent, %{copy_id: "c-1", member_id: "m-1"}
    issues :release_hold, %{copy_id: "c-1"}
  end

  scenario "a member's open loans leave out what came back", illustrates: :only_open do
    given :copy_lent, %{loan_id: "l-1", copy_id: "c-1", member_id: "m-1"}
    given :copy_lent, %{loan_id: "l-2", copy_id: "c-2", member_id: "m-1"}
    given :copy_returned, %{loan_id: "l-1"}
    query :open_loans_of_member, %{member_id: "m-1"}
    answers [%{loan_id: "l-2"}]
  end

  scenario "the librarian notes a hold placed at the counter" do
    actor :librarian
    record :hold_placed, %{copy_id: "c-2", member_id: "m-1"}
    expect :hold_placed, %{member_id: "m-1"}
  end
end

defmodule Concepts.Scenarios.Loan do
  use Concepts.Scenarios.Contracts.Loans, aggregate: :loan

  @impl true
  def lend_copy(%LendCopy{} = command, _state) do
    emit(%CopyLent{
      loan_id: command.loan_id,
      copy_id: command.copy_id,
      member_id: command.member_id
    })
  end

  @impl true
  def return_copy(%ReturnCopy{loan_id: id}, _state), do: emit(%CopyReturned{loan_id: id})
end
```

One line in a test module of the application runs each scenario of the contract:

<!-- not compiled: a line of the host's test module -->
```elixir
use EhOsContract.ScenarioCase, contract: Concepts.Scenarios.Contracts.Loans
```

- Each scenario becomes an ExUnit test, with its description as the name.
- The scenario runs the module of the application that implements its target. For a contract
  outside an application, `implementations:` names the modules.
- A target without an implementation fails its scenario, except a recording, which runs no code. A
  contract without code is valid. A test of it is not.
- The same line makes a test of each example of the rules of the domain services of the contract.
- `use EhOsContract.ScenarioCase, domain:` makes a test of each example of the invariants of the
  values of a domain.

## What is the trigger, and what is the target?

A scenario has exactly one *trigger* ([`S1`](refusals.md#refusals-s)). It is one of these
kinds:

- **`command`**: a command of the contract, to the unit that declares it.
- **`on`**: an event that goes to the policy or the process manager that handles it. For a process
  manager, it can also be one of its timers: `on :reminder_due`.
- **`query`**: a query of the contract. The data of the scenario gives its params.
- **`record`**: an event that its unit declares `recorded_by:`. An actor writes it into the log
  without a decision, as `EhOsContract.record/3` does. Examples: what a person saw, or what an
  outside system told an integration.

The *target* is the declaration that the scenario runs.

- If one declaration takes the trigger, the trigger gives the target.
- If more than one declaration takes the event, `target` names one
  ([`S1`](refusals.md#refusals-s)). In the example, the policy handles `copy_lent` and the read
  model projects it. So the scenario of the policy names the policy.
- An effect and a read model are never a target ([`S6`](refusals.md#refusals-s)). The result of an
  effect is outside the log. The scenario of a query shows its read model.

`actor` names who issues the command of a scenario, from its `by:`
([`S7`](refusals.md#refusals-s)). The scenario of a recording always names who records the event,
from its `recorded_by:` ([`S7`](refusals.md#refusals-s)). It shows who can write that event into
the log.

## What can a scenario expect?

The target decides which givens and outcomes a scenario can have
([`S6`](refusals.md#refusals-s)). This table gives them:

| Target | Given | Outcome |
| --- | --- | --- |
| a command of a unit | the events of the unit, or the consulted events of a boundary | `expect` one or more events, or `rejected` with one rule, or with an invariant of a domain value that its data breaks (exactly one of the two) |
| a policy | none ([`S2`](refusals.md#refusals-s)) | `issues` the commands that it issues |
| a process manager | the events that it handles | `issues`, `sets` and `cancels` a timer, `ended: true`; `state` of its run after the step |
| a query | the events that its read model projects | `answers` the rows, or the row for a query that returns one |
| an event recorded | the events of the unit, or the consulted events of a boundary | `expect` the recorded event, or `rejected` with an invariant of a domain value that its data breaks (exactly one of the two) |

The compiler refuses an outcome that the declaration cannot give:

- `expect` names an event that the command emits ([`S5`](refusals.md#refusals-s)). After a
  recording, it names only the recorded event.
- `rejected` names a rule that the command `rejects:` ([`S4`](refusals.md#refusals-s)). It can also
  name an invariant of a domain value that a field holds, the identity included.
- After a recording, `rejected` names only an invariant of a domain value that its fields hold.
  Nothing decides a recording, and nothing else refuses it.

A field typed by a value whose invariant refuses 5 shows it so:

<!-- in: Concepts.Scenarios.Contracts.Loans -->
```elixir
scenario "a copy is not lent for 5 weeks" do
  command :lend_copy, %{copy_id: "c-1", member_id: "m-1", weeks: 5}
  rejected :one_to_four_weeks
end
```

`illustrates:` names the rules that the scenario of a reaction or a query shows
([`S10`](refusals.md#refusals-s)). Each is a constraint of the policy, the process manager or the
query, or an invariant of the process manager. The scenario of a command shows its rules with
`rejected`. The compiler refuses `illustrates:` there.

## What does the engine do for each kind of trigger?

![Each trigger goes to its own part. The engine compares the events and commands in order, and the rows of an answer one by one.](img/scenario-triggers.svg)

1. A command goes to its unit. The unit folds the givens, and decides.
2. An event goes to a policy or a process manager. It reacts.
3. A recording runs no code. The engine checks the event against its declaration.
4. The read model projects the givens, and the query answers.
5. The engine compares the decision with `expect` or `rejected`.
6. It compares the issued commands with `issues`.
7. It compares the recorded event with `expect` or `rejected`.
8. It compares the rows with `answers`.

The engine compares events and commands in order, and accepts others between them. It compares
each row of an answer, and accepts no other row. The sections below tell each step.

### A command

1. The engine holds the data of the scenario to the invariants of the domain values of its fields,
   as dispatch does before a decision. If the data breaks one, the engine refuses the command on
   it.
2. The state of the unit starts from its defaults, with the identity of the scenario. If the
   scenario leaves the identity out, the engine uses its own, and checks no invariant of it.
3. The implementation folds each `given` into the state through `evolve/2`.
4. If the unit has a lifecycle, the engine puts it in the status that the givens leave it in. If
   the `from:` of the command does not admit that status, the engine refuses the command on its
   `or_rejects:`. The callback does not run, as in dispatch.
5. The callback of the command decides.

In the example, "a returned copy is not returned twice" passes, and `return_copy` checks nothing.
The copy is `returned`, outside `from: :lent`, and the engine refuses on `:returned_once`.

The expected events must be among the decided events, **in the same order, as a subsequence**.
Other events can come between them. Each event has at least the fields that its data names. So a
scenario about one rule does not fail when the decision gets one more event.

- An event outside the `emits:` of the command fails the scenario, whatever the scenario expects.
- An event that the lifecycle does not allow from the status also fails it, whatever it expects.
- `rejected` passes only on a rejection on exactly that rule.

### A reaction

- The engine calls the callback of a policy with the event.
- For a process manager, the engine first folds the givens into its state. Then it calls the
  callback of the event or of the timer with that state.
- The engine compares the issued commands with `issues` as a subsequence, as for events. A command
  outside the `issues:` of the reaction fails the scenario.
- The engine compares `state` with the run as the engine keeps it after the step, on the fields
  that `state` names. After an event, this is the state with the event folded in, after the
  reaction decided. After a timer, the state does not change.

A step that the engine would not take holds no state. So these scenarios fail:

- a given before the run starts;
- a trigger after the run ended;
- events that name 2 runs in their correlation fields.

### A recording

No implementation runs, because nothing decides a recording. The engine holds the event to what
`EhOsContract.record/3` holds it to before it reads the log:

- A `:system` actor records the event only if its `recorded_by:` names the actor.
- The scenario does not judge the credential of a person. The authorizer does.
- The data fits the types of its fields, and the invariants of their domain values.
- If the library gives the identity of the aggregate, the event can be recorded only for an
  aggregate that a command made. So the scenario needs a `given`.

The recorded event is the one event appended. The engine compares it with `expect` as the events
of a command. `rejected` passes only on the invariant of that value.

### A query

1. The read model projects each `given` through its implementation.
2. The engine asks the query with the data of the trigger.
3. The answer must have **exactly as many rows** as `answers`. Each row of `answers` matches a
   different row, on the fields that it names, in any order.

An extra row fails the scenario, unlike an extra event. The givens decide the whole answer, and
many scenarios show what the answer leaves out.

The projection writes the tables of the application. So it runs in a transaction of the configured
repo, and the transaction is rolled back. If the pool of the repo is the Ecto sandbox, the test
checks out a sandbox connection.

### How does the engine read the data?

The data of a scenario is plain data:

- An ISO 8601 string is the `DateTime` of a `:timestamp` field, or the `Date` of a `:date` field.
- A string of digits, or an integer, is the `Decimal` of a `:decimal` field.
- The givens, and then the trigger, occur 1 minute apart, from 1 January 2026, 09:00 UTC. A given
  can say when it occurred: `at: "2026-09-07T09:00:00Z"`.
- Each given has an id and a position, as an event read back from the log has.

Each field that the data names must be declared, with the correct type. Each required field must be
in a `given` or in the trigger ([`S3`](refusals.md#refusals-s)). The data must fit the values of the
domain ([`X9`](refusals.md#refusals-x)). The identity of the unit is the exception: if the data
leaves it out, the scenario uses its own.

## What does a property test add?

A scenario tests the case that its author thought of. A *property test* tries the code of a unit on
hundreds of histories that the contract allows. `EhOsContract.Generators` makes these histories
from the contract.

<!-- not compiled: a line of the host's test module -->
```elixir
use EhOsContract.PropertyCase, contract: Concepts.Scenarios.Contracts.Loans
```

It checks 3 things:

1. `evolve/2` folds each history, also a history in which the data of a person is erased.
2. Each command, issued in a status that its `from:` admits, decides one of two things. It refuses
   on one of its `rejects:`. Or it emits only events that its `emits:` names, with the identity of
   the command, values that fit, and an order that the lifecycle allows.
3. If the implementation says what each invariant means with `holds?(invariant, state)`, each
   invariant holds after each command that it decides.

A failure shows the shortest history, or list of commands, that makes it occur. Examples: a visit
opened again while it is in progress, a correction booked on a settlement that is not closed yet.

The module exists only when StreamData is a dependency of the application, usually for tests only.

## How does the conformance report read the scenarios?

After a deploy, the conformance report reads the scenarios too.

- For each scenario with a command as its trigger, it counts if the log saw it occur.
- The log saw it if the command decided with the given types in the stream. The command also emitted
  the expected types, or refused on the same rule.
- It lists the decisions that no scenario describes.
- It matches both by the types of the events, never by their data.

A decision that no scenario describes is a question for the process owner. The code decided
something that the agreed examples do not say.

## Which declarations need a scenario?

The compiler refuses an invariant, or a constraint of a command, without a `rejected` scenario
([`S8`](refusals.md#refusals-s)). Only an example that refuses on a rule of a decision proves the
rule.

For other declarations, a missing scenario is a warning of `mix eh_os_contract.check`.
[The rules of the check](rules.md) give each rule:

- `reaction-without-scenario`: no scenario runs a policy, a process manager or a query. Add one on
  the event that it takes, with what it `issues`. For a query, add one with what it `answers`. The
  check leaves out an effect, because no scenario runs one.
- `prose-without-scenario`: no `illustrates:` names a constraint of a policy, a process manager or
  a query, or an invariant of a process manager. Add a scenario of that declaration that shows it.
  The check leaves out the constraint of an effect, and a declaration that no scenario runs.
- `transition-without-scenario`: no scenario takes a transition of a lifecycle. Add a scenario of
  a command that expects the event of the transition. Its givens leave the unit in the `from`
  status. A `rejected` scenario decides nothing, and does not count. A transition from more than
  one status needs a scenario from each. The check leaves out a transition on an event that no
  command emits, or from a status that the `from:` of no command admits.
- `recording-without-scenario`: no scenario records an event that its `recorded_by:` actors
  record. Add one that records it, by one of those actors. It expects what it appends, or the
  invariant of a value that it breaks. For an integration, it shows what the outside system can write into the
  log.
- `in-transaction-policy-fan-out`: a scenario shows a policy, delivered `:in_transaction`, that
  issues more than one command. [Reactions](reactions.md) tells why.

## Next steps

- [What are the units that decide?](units.md): the invariants and the lifecycles that scenarios
  prove.
- [Write the code that decides](deciding.md): the code that the scenarios of commands run.
- [Reactions](reactions.md): the policies and process managers that scenarios run.
- [The scenario reference](dsl/contract-scenario.md): each key of a scenario.
- [The compile refusals](refusals.md#refusals-s): each refusal of a scenario.
