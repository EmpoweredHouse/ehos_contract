# Scenarios: examples the process owner reads, run as tests

What a scenario is, what it can say about a command, a reaction and a query, how
`EhOsContract.ScenarioCase` runs it against the implementation, and which declarations need one.

<!-- covers: entities contract.scenario; rules reaction-without-scenario, prose-without-scenario, transition-without-scenario -->

A rule written as a label ("a copy is returned once") tells whoever writes the code what to keep, and
nothing shows the code keeps it. A **scenario** is the case that does: events that already happened, one
trigger, and what follows. It is written in the contract, in the process owner's words, so the owner can read
it and say whether it is right; and it runs as a test of the implementation, against the same rules dispatch
applies.

```
given   what already happened         (events)
when    one trigger                   (a command, an event a reaction handles, or a query)
then    what follows                  (events, a rejection, commands issued, a timer, rows answered)
```

A scenario is no stub and no mock: it calls the implementation's own callbacks, with the structs the contract
generates, and holds what they return to the declaration as dispatch would.

## An example

```elixir
defmodule Concepts.Scenarios.Domain do
  use EhOsContract.Domain, name: :scenarios_example, language: :en

  subdomain :core, "Core", type: :core

  context :desk, "Lending desk", subdomain: :core

  actor :librarian, :human, "Librarian"
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

The test that runs every scenario of the contract is one line, in a test module of the application:

```elixir
use EhOsContract.ScenarioCase, contract: Concepts.Scenarios.Contracts.Loans
```

Each scenario becomes an ExUnit test named after its description. The implementation of the scenario's
target is the module of the contract's application bound to it; `implementations:` names the modules instead,
for a contract compiled outside an application. A target with no implementation fails its scenario: a
contract without code is legal, a test of one is not.

## The trigger, and who the scenario is about

A scenario has exactly one trigger (`S1`):

- **`command`**: a command of the contract, to the unit that declares it.
- **`on`**: an event delivered to the reaction that handles it: a policy or a process manager; for a process
  manager also one of its own timers, `on :reminder_due`.
- **`query`**: a query of the contract, with its parameters as the data.

The trigger names its target when one declaration takes it. When several take one event, `target` says
which (`S1`): in the example `copy_lent` is handled by the policy and projected by the read model, so the
policy's scenario names the policy. An effect and a read model are never a target (`S6`): an effect's outcome is
outside the log, and a read model is shown by the scenario of a query that reads it.

`actor:` picks who issues a scenario's command, among its `by:` (`S7`).

## What follows

Which outcomes a scenario may state depends on its target (`S6`):

| Target | Given | Outcome |
| --- | --- | --- |
| a unit's command | the unit's own events, or a boundary's consulted ones | `expect` one or more events, or `rejected` with one rule (exactly one of the two) |
| a policy | none (`S2`) | `issues` the commands it issues |
| a process manager | the events it handles | `issues`, `sets` and `cancels` a timer, `ended: true`; `state` its run holds after the step |
| a query | events its read model projects | `answers` the rows, or for a query that returns one, the row |

What a scenario expects has to be possible: `expect` names an event the command emits (`S5`), `rejected` a
rule it `rejects:` (`S4`), and an outcome the declaration cannot produce does not compile (`S6`). Its data
names declared fields of the right type, with every required one in a `given` or the trigger (`S3`), and fits
the domain's values (`X9`). The unit's identity is the exception: left out, it is the scenario's own.

`illustrates:` names the rules a reaction's or a query's scenario shows: a constraint of the policy, process
manager or query, or an invariant of the process manager (`S10`). A command's scenario shows its rules with
`rejected` instead, and `illustrates:` there does not compile.

## How a scenario runs

**A command.** The unit's state starts from its defaults with the scenario's identity, folds every `given`
through the implementation's `evolve/2`, and the command's callback decides. A unit with a lifecycle is first
placed in the status its givens leave it in; a command whose `from:` does not admit that status is refused on
its `or_rejects:` before the callback is called, as dispatch refuses it. In the example, "a returned copy is
not returned twice" passes without `return_copy` checking anything: the copy is `returned`, outside
`from: :lent`, and the engine refuses on `:returned_once`.

The events a scenario expects must appear among those decided, **in that order, as a subsequence**: other
events may come between them, and each carries at least the fields its data names. So a scenario about one
rule does not break when the decision grows by an event. An event outside the command's `emits:`, or one the
lifecycle does not allow from where the unit stands, fails the scenario whatever it expects. `rejected`
passes only on a rejection on exactly that rule.

**A reaction.** A policy's callback is called with the event; a process manager's state folds its givens
first, and the reaction's or the timer's callback is called with it. The commands it `issues` are compared as
events are, as a subsequence, and a command outside the reaction's `issues:` fails. A process manager's
`state` is the run after the step, as the engine keeps it (the delivered event folded after the reaction
decided, and after a timer the state as it was), compared on the fields it names. A step the engine would not
take holds no state: a given before the run starts, or a trigger after it ended, fails the scenario, and so
do events naming two runs in their correlation fields.

**A query.** Every `given` is projected through the read model's implementation, the query is asked with the
trigger's data, and its answer must have **exactly as many rows** as `answers`, each matching a different row
on the fields it names, in any order. Unlike events, an extra row fails: the givens decide the whole answer,
and what is left out is often what the scenario is about. The projection writes the application's tables, so
it runs in a transaction of the configured repo that is rolled back, and the test checks out an Ecto sandbox
connection when the repo's pool is the sandbox.

**Data.** Scenario data is plain: an ISO 8601 string is the `DateTime` or `Date` of a `:timestamp` or `:date`
field, and a digit string or an integer the `Decimal` of a `:decimal`. The givens and then the trigger occur a
minute apart, from 1 January 2026, 09:00 UTC, and each given has an id and a position, as an event read back
from the log has.

`use EhOsContract.ScenarioCase, contract:` also turns every example of the contract's domain services' rules
into a test, and `use EhOsContract.ScenarioCase, domain:` every example of a domain value's invariants.

## After deploy

Scenarios stay useful once the code runs. The conformance report counts, for each scenario whose trigger is a
command, whether the log has seen it happen (that command decided with the scenario's given types in the
stream, and the expected types emitted or the same rule refused), and lists the decisions no scenario
describes. Both are matched by event types, never by data. A decision no scenario describes is a question for
the process owner: the code decided something the agreed cases do not say.

## Which declarations need one

The compiler refuses an invariant, or a command's constraint, without a `rejected` scenario (`S8`): a rule
of a decision is proved only by a case that refuses on it. For everything else a missing scenario is a
warning of [the check](../rules.md):

- **`reaction-without-scenario`** (warning): no scenario runs a policy, a process manager or a query. Add one
  on the event it takes with what it `issues`, or for a query what it `answers`. An effect is left out, since
  no scenario runs one.
- **`prose-without-scenario`** (warning): a constraint of a policy, a process manager or a query, or an
  invariant of a process manager, is named in no scenario's `illustrates:`. Add a scenario of that
  declaration that shows it. An effect's constraint, and a declaration no scenario runs at all, are left out.
- **`transition-without-scenario`** (warning): no scenario takes a declared transition of a lifecycle. Add a
  command's scenario whose givens leave the unit in the transition's `from` status and which expects its
  event; a `rejected` scenario decides nothing and does not count. A transition from several statuses needs a
  scenario from each; one on an event no command emits, or from a status no command's `from:` admits, is
  left out.
- **`in-transaction-policy-fan-out`** (warning): a scenario shows a policy delivered `:in_transaction`
  issuing more than one command. See [reactions](reactions.md).

Every key of a scenario and of what it holds is on [the reference page](../dsl/contract-scenario.md).
