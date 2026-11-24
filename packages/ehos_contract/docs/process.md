# What is a process module?

<!-- covers: entities process.correlate, process.stage, process.ends_on, process.promise, process.deadline; rules process-without-accountable, promise-without-within, unverified-declaration, owner-view-without-label -->

This page tells what a process module adds to the units that decide. It tells how the engine files
events into runs, and how it judges the promises and the deadline of each run. It is for a
developer who writes a process module, and for a process owner who reads one. [The
glossary](glossary.md) defines each word in italics.

## What does a process module add?

A unit decides over its own stream: one loan, one fine. A business often answers for a longer
case. Example: a loan, from the day that the copy goes out to the day that it comes back, or is
paid for. One such case is a *run* of a process.

A *process module* describes one kind of run. It is a module of its own, `use
EhosContract.Process`:

- It names the events that make a run. The events can come from one contract or from several.
- It files each of these events into a run.
- It states what the business promised about each run.

A process module decides nothing. It declares no event, and nothing is dispatched to it. The units
decide without it. The process module is what the engine measures: the [conformance
report](conformance.md) compares the log with its promises.

[Write a domain, a contract and a process module](contract.md) shows how to start one. The
[reference](dsl/process-dsl.md) lists each key.

## An example

A library lends copies in one contract. It charges for lost copies in another contract. For the
library, a loan runs until the copy comes back, or until the charge for it is settled:

```elixir
defmodule Concepts.Process.Domain do
  use EhosContract.Domain, name: :process_example, language: :en

  subdomain :core, "Core", type: :core

  context :desk, "Lending desk", subdomain: :core

  actor :librarian, :human, "Librarian"

  external :catalogue, "Catalogue", direction: :outbound do
    operation :look_up_price, "Look up the price of a copy"
  end
end

defmodule Concepts.Process.Contracts.Loans do
  use EhosContract.Contract,
    domain: Concepts.Process.Domain,
    context: :desk,
    id: "process_example.loans"

  aggregate :loan, "Loan of a copy" do
    identity :loan_id

    command :lend_copy, "Lend a copy", by: :librarian, emits: :copy_lent do
      field :copy_id, :id
    end

    command :take_back, "Take a copy back", by: :librarian, emits: :copy_returned
    command :write_off, "Write a copy off as lost", by: :librarian, emits: :copy_written_off

    event :copy_lent, "Copy lent" do
      field :copy_id, :id
    end

    event :copy_returned, "Copy returned"
    event :copy_written_off, "Copy written off as lost"
  end

  effect :ask_price, "Ask the catalogue the price of a lost copy",
    handles: :copy_written_off,
    calls: {:catalogue, :look_up_price},
    idempotency: [key: :event_id, owner: :downstream]
end

defmodule Concepts.Process.Contracts.Fines do
  use EhosContract.Contract,
    domain: Concepts.Process.Domain,
    context: :desk,
    id: "process_example.fines"

  aggregate :fine, "Charge for a lost copy" do
    identity :fine_id

    command :charge_fine, "Charge for a lost copy", by: :librarian, emits: :fine_charged do
      field :loan_id, :id
      field :amount, :decimal
    end

    command :settle_fine, "Settle a charge", by: :librarian, emits: :fine_settled do
      field :loan_id, :id
    end

    event :fine_charged, "Lost copy charged" do
      field :loan_id, :id
      field :amount, :decimal
    end

    event :fine_settled, "Charge settled" do
      field :loan_id, :id
    end
  end
end

defmodule Concepts.Process.Processes.Loan do
  use EhosContract.Process,
    id: "process_example.loan",
    domain: Concepts.Process.Domain,
    label: "A loan, until the copy is back or paid for",
    accountable: :librarian

  correlate :loan_id

  stage :lending, "Lending", include: [{Concepts.Process.Contracts.Loans, :copy_lent}]

  stage :return, "Return",
    include: [{Concepts.Process.Contracts.Loans, [:copy_returned, :copy_written_off]}]

  stage :charge, "Charge",
    include: [{Concepts.Process.Contracts.Fines, [:fine_charged, :fine_settled]}]

  ends_on [:copy_returned, :fine_settled]

  deadline {120, :day}, unverified: true

  promise :back_within_a_month do
    from :copy_lent
    eventually :copy_returned
    within {30, :day}
    or_else :copy_written_off
    source "Lending rules, section 4"
  end

  promise :lost_copy_charged_within_a_week do
    from :copy_written_off
    eventually :fine_charged
    within {7, :day}
  end
end
```

The contracts know nothing of the run. They decide loans and fines, and declare their events. In
`Loans`, `loan_id` is the identity of the loan. In `Fines`, it is an ordinary field. Both are
`:id`, so the process module can correlate on it ([`X6`](refusals.md#refusals-x)).

## How does the engine file an event into a run?

The *correlation* is the list of fields that tell one run from another. `correlate` declares it.
A module declares `correlate` once, with one field or more, and each field once
([`R2`](refusals.md#refusals-r)).

When the engine appends an event that a process module includes, it reads the correlation
fields from the event. The values and the `id:` of the process module make the key of the run.
The engine files the event under that key, in the same append as the event.

- An included event without a value for each correlation field belongs to no run of that process.
- One event can belong to the runs of more than one process module.
- An event after the end of a run has the same key. The engine files it into the same run.

In the example, the first loan event, the last loan event and the fine all carry the same
`loan_id`. So they are in one run.

Each included event carries the correlation fields. Each field is required and not personal. It is
the same kind of identifier in each contract: `:id`, `{:id, entity}`, or a value of the domain
that rests on one ([`X6`](refusals.md#refusals-x)). A correlation has 6 fields or fewer
([`F9`](refusals.md#refusals-f)). If the key of a run is too long, dispatch refuses the command with
`{:error, :key_too_long}`.

Correlate on what the business calls "one case":

- A field that is too coarse puts unrelated cases into one run. Example: a member instead of a
  loan. The engine then judges all loans of the member together.
- A field that is too fine splits one case into two runs. A promise that spans both halves is then
  never satisfied.

The report counts runs. It never names one. The application already knows which loan is late.

## What do the other parts of the module say?

**`domain:`** names a compiled domain ([`X1`](refusals.md#refusals-x)). **`id:`** starts with the
`name:` of the domain, then has dotted snake_case segments ([`D11`](refusals.md#refusals-d)).

The `id:` keys the runs, as the `id:` of a contract keys its events. Two process modules of one
application cannot have the same `id:` ([`X7`](refusals.md#refusals-x)). A process module can have
the same `id:` as a contract. If you rename the `id:`, the key of each new run changes. The report
then does not find the runs that are already in the log.

**`stage`** declares one step of a run. A *stage* names its events with `include:`, as
`{Contract, :event}` or `{Contract, [:event, …]}`:

- The stages have an order: the order in the module.
- A module has one stage or more, and each stage includes one event or more. Each entry of
  `include:` names a contract module and an event ([`R3`](refusals.md#refusals-r)).
- An included event is one that the contract declares. It is not an event that the contract
  consumes or receives ([`X5`](refusals.md#refusals-x)).
- `include:` makes no compile dependency on the contract.
- Everywhere else in the module, the name of the event is enough. So two included events cannot
  have one name, also from two contracts ([`N1`](refusals.md#refusals-n)).

The engine does not hold a run to the order of its stages. The report counts the runs that entered
them out of order.

**`ends_on`** lists the events that end a run. A module declares it once, and each event is one
that a stage includes ([`R5`](refusals.md#refusals-r)). The first of them ends it. A run without one of
these events is open. The contracts do not mark an event as the end of anything. A settled fine
ends a loan only for this process.

**`accountable`** names the actor that answers for the process. A finding about the process goes to
this actor. The report prints the label of the actor beside the process. The actor can belong to
any context of the domain, because a process can cross contexts ([`X2`](refusals.md#refusals-x)).

The module compiles to a model of kind `:process`. `EhosContract.Model.fetch/1` returns it.

## What does a promise state?

A *promise* states what the process owner agreed for each run: after one event, another event
follows.

- **`from`** is the event that opens the promise. The window opens at the **first** `from` of the
  run. A second `from` does not move the window.
- **`eventually`** is the event that satisfies the promise.
- **`within`** is the window: `{count, unit}`, in seconds, minutes, hours or days.
- **`or_else`** is another event that also satisfies the promise. Example: the copy was written off. It
  is a correct end, but not the one that the business wanted. `within` applies to it too.
- **`waits_on`** names the external systems that the promise waits for through an earlier step.
  [Record an outage of an external system](outages.md) tells how.
- **`source`** tells where the promise comes from, in the words of the business.

`from`, `eventually` and `or_else` are events that the process module includes
([`R5`](refusals.md#refusals-r)). `within` accepts only seconds, minutes, hours and days. It
refuses a calendar unit, such as a week, a month or a year ([`R6`](refusals.md#refusals-r)). The
engine measures a window in seconds, with no calendar, and a month has no fixed length. A window is from 0 up to
100 years ([`R6`](refusals.md#refusals-r)).

The window opens at the first `from` that the engine reads. A report with a period reads only the
events inside the period: [The conformance report](conformance.md#which-events-does-each-number-read)
tells what follows.

## Which verdicts can a promise have?

A *verdict* is the result of one promise for one run at one moment. Only a run in which `from`
occurred gets a verdict. Before `from`, the promise has nothing to judge.

![The from event opens the window and makes the verdict pending; eventually or or_else inside the window satisfies it; at the end of the window it is suspended if a system it waits for was unavailable inside the window, and violated if not.](img/promise-verdicts.svg)

1. The first `from` of the run opens the window. The verdict is `pending`.
2. `eventually` occurs inside the window. The verdict is `satisfied`, by the route `eventually`.
3. `or_else` occurs inside the window. The verdict is `satisfied`, by the route `or_else`.
4. The window ends, and neither event occurred. The verdict is `violated`.
5. The window ends, and neither event occurred. But a system that the promise waits for was
   unavailable inside the window. The verdict is `suspended`, never `violated`.

| Verdict | When | The report says |
| --- | --- | --- |
| `:pending` | The window is open, and neither event occurred yet. | "still in progress" |
| `:satisfied` | `eventually` or `or_else` occurred inside the window. | "Met" |
| `:violated` | The window ended, and neither event occurred. | "BREACHED" |
| `:suspended` | As `:violated`, but an outage of a system that the promise waits for was seen inside the window. | "Suspended" |

These rules apply too:

- An `eventually` or an `or_else` before the first `from` satisfies nothing.
- If both events occur inside the window, the route is `eventually`.
- An event after the end of the window does not change `violated` or `suspended`.

A `suspended` run is one that the business does not answer for. The report counts it apart, never
among the violated runs. A promise waits for a system in two ways, and these outages suspend a run:

- an outage of a system that the `eventually` or the `or_else` event `depends_on`, which the
  contract that declares that event recorded;
- an outage of a system in `waits_on`, which any contract of the process module recorded.

An outage of what `from` depends on suspends nothing: that system worked, because `from` occurred.
The outage must be at or after the first `from`, and at or before the end of the window.

**A promise without `within`** has no case that fails. An `eventually` or an `or_else` satisfies it. A
run without either stays `pending` for ever, and is never `suspended`. That is correct while nobody
agreed a number. `mix ehos_contract.check` gives a notice about it, so nobody reads it as a satisfied
promise.

**A promise for each item.** Sometimes the unit of the `from` event is finer than the run. Example:
a run of one loan, in which each of several items is lent. Then the engine judges the promise for
each item:

- The identity of the unit of `from` names the item. Each item has its own window, from its own
  first `from`.
- An `eventually` or an `or_else` resolves the item that its identity fields name. One without all
  of these fields resolves no item.
- The run gets the worst verdict of its items: `violated`, then `pending`, then `suspended`, then
  `satisfied`.

## What does the deadline measure?

A *deadline* is the longest time that a whole run can take. `deadline {90, :day}` measures from the
first event of the run to the first event that ends it. So it needs `ends_on`
([`R6`](refusals.md#refusals-r)). A module declares one deadline, in the same fixed units as
`within`, from 0 up to 100 years.

| The run | Outcome |
| --- | --- |
| ended inside the deadline | kept |
| ended after the deadline | exceeded |
| is open, and the deadline has passed | overdue: only a lower bound of its duration is known |
| is open, inside the deadline | not reported: this is the normal case |

For the deadline, the report counts a run in the period in which it **started**. It measures the run over all its
events. So a run that started in June does not look as if it started in July.

## What does `unverified: true` do?

Mark a promise or a deadline `unverified: true` if the process owner has not confirmed its number
yet.

- The conformance report leaves out an unverified promise and an unverified deadline. A number that
  the client never agreed to would read as measured.
- The engine still judges an unverified promise. `EhosContract.Trace.evaluate/3` gives its verdicts,
  for example in a test.
- `mix ehos_contract.check` gives a warning for each one, until you remove the mark.

## How do you read a process module?

- **Scenarios.** A process module can carry scenarios that give the verdict of a promise.
  [Write a domain, a contract and a process module](contract.md) shows one.
- **Pages.** `mix ehos_contract.pages` writes a page for each process module. The page name is the
  `id:` without the name of the domain: `fulfilment.order` is `processes/order.md`. The page lists
  the correlation, the accountable actor, and the stages in order. Each included event links to its
  page in its contract. The page also lists the events that end a run, the promises and the
  deadline. It names the external systems that the events depend on, and the scenarios. It says
  which declaration the report leaves out. The page of the domain and the page of each included
  contract link to it.
- **Graph.** `mix ehos_contract.pages` also writes `graph/process/<id>.json`, a `graph.v1`
  document. `mix ehos_contract.graph --process <id>` prints the same document.
- **Tree.** `mix ehos_contract.view` lists each process module under the domain, with its stages
  and the events of each stage.
- **Glossary.** `mix ehos_contract.glossary` lists a process module under a term of a context. The
  process must include events of that context. The term must name its `id:`, a stage, a promise or
  a correlation field.

[The tasks](cli.md) give each option.

## What does `mix ehos_contract.check` say about a process module?

[The rules](rules.md) about a process module:

- `process-without-accountable` (warning): a finding about the process goes to nobody. Name the
  actor with `accountable`.
- `unverified-declaration` (warning): a deadline or a promise is marked `unverified: true`, so the
  report leaves it out. Remove the mark when the process owner confirms the number.
- `promise-without-within` (notice): the promise has no case that fails. Add `within` when the owner
  agrees a window.
- `owner-view-without-label` (notice): a stage has no label. A process owner then reads the name
  from the code. Give it the words of the business: `stage :departure, "Departure of the patient",
  include: …`.

## Next steps

- [Record an outage of an external system](outages.md): how a promise gets the verdict
  `suspended`.
- [The conformance report](conformance.md): what the report prints for a process module.
- [What is a scenario?](scenarios.md): the examples that a contract and a process module carry.
- [The compile refusals](refusals.md#refusals-r): each refusal of a process module, in the families
  R and X.
