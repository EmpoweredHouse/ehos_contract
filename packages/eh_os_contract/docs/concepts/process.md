# Processes: runs, stages, promises and deadlines

What a process adds to the units that decide: runs that group their events, the stages a run goes through,
how a run ends, what the process owner promised about it, and how the conformance report holds the log to
those promises.

<!-- covers: entities process.correlate, process.stage, process.ends_on, process.promise, process.deadline; rules process-without-accountable, promise-without-within, unverified-declaration, owner-view-without-label -->

A unit decides over its own stream: one loan, one fine. A business is usually accountable for something
longer (a loan from the day the copy goes out to the day it comes back, or is paid for) and that is a
**run** of a process. The units do not need a process to decide; the process is what the engine measures.
Its events are the units' events, and nothing is dispatched to a process. What it adds is a way to file
those events into runs, and a set of claims about runs that the report can check against the log.

A process is a module of its own, `use EhOsContract.Process`. It names the contracts' events that make a
run, whether they come from one contract or from several, and says what the business promised about a run.
[The guide](../contract.md) introduces it; this page is how it behaves.

## A run, and what tells one from another

`correlate` names the fields that tell which run an event belongs to. When an event the process includes is
appended, the engine reads those fields from it and files the event under the process's `id:` and their
values, in the same append as the event itself. Every included event carries the fields, required and not
personal, and as the same kind of identifier in every contract: `:id`, `{:id, entity}` or a domain value
resting on one ([`X6`](../contract.md#refusals-x)). An event may belong to the runs of more than one process.

So a process that correlates on `:loan_id` puts the loan's first event and its last in one run, and a fine
recorded in another contract with the same `loan_id` in that run too, since the process includes it. A run
is never named by the report: it counts runs and verdicts, and which loan is late is a question for the
application, which already knows.

Correlate on what the business means by "one case". A run keyed by too coarse a field, a member instead of a
loan, gathers unrelated loans into one and judges them together; one keyed by too fine a field splits a case
in two, and a promise that spans both halves is never kept. At most six fields make one key ([`F9`](../contract.md#refusals-f)).

## A process module

<!-- covers: entities process.correlate, process.stage, process.ends_on, process.promise, process.deadline -->

A library lends copies in one contract and charges for lost ones in another. The loan, as the library
answers for it, runs from the day the copy goes out until it comes back or the charge for it is settled:

```elixir
defmodule Concepts.Process.Domain do
  use EhOsContract.Domain, name: :process_example, language: :en

  subdomain :core, "Core", type: :core

  context :desk, "Lending desk", subdomain: :core

  actor :librarian, :human, "Librarian"
end

defmodule Concepts.Process.Contracts.Loans do
  use EhOsContract.Contract,
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
end

defmodule Concepts.Process.Contracts.Fines do
  use EhOsContract.Contract,
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
  use EhOsContract.Process,
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

The contracts know nothing of the run: they decide loans and fines, and declare their events. The module
decides nothing and declares no event of its own; nothing is dispatched to it. `loan_id` is the loan's
identity in `Loans` and an ordinary field in `Fines`; both are `:id`, so the module correlates on it
([`X6`](../contract.md#refusals-x)).

**Its `id:`** keys its runs, as a contract's `id:` keys its events: two processes of one system may not
share it ([`X7`](../contract.md#refusals-x)), and renaming it changes the key every run is filed under, so the report no longer
finds the runs already in the log.

**Stages** are the steps of a run, in order. Each names the events that belong to it with `include:`,
`{Contract, :event}` or `{Contract, [:event, …]}`, without a compile dependency on the contract. A module has
at least one stage, and every stage includes something ([`R3`](../contract.md#refusals-r)); a run with one step has one stage. The
events are ones the contract declares, not ones it consumes or receives ([`X5`](../contract.md#refusals-x)). Everywhere else in the
module an event is named by its name alone, so two included events of one name are refused, whichever
contracts they come from ([`N1`](../contract.md#refusals-n)). The engine does not hold a run to the order of its stages; the
report counts the runs that entered them out of order.

**`ends_on`** lists the events that end a run. Whichever comes first ends it, and a later event does not
reopen it. A run with none of them yet is open. The contracts do not mark their events as ending anything,
since a fine settled ends a loan only for this process.

**`accountable`** names the role that answers for the process: the actor a finding about it is addressed
to. The report prints the actor's label beside the process. It is an actor of the domain, of any of its
contexts, since a process may cross them ([`X2`](../contract.md#refusals-x)).

A run is filed at the append of each included event; an included event without a value for every
`correlate` field belongs to none of its runs.

The module compiles to a model `EhOsContract.Model.fetch/1` returns, of kind `:process`. Its keys are on
[the reference page](../dsl/process-dsl.md).

## Promises

A promise is what the process owner agreed happens in a run: after one event, another eventually follows.

- `from` opens it. A run in which `from` never happened is not judged at all: there is nothing to keep yet.
  The window opens at the **first** `from` of the run, so a run cannot put its deadline off by recording
  `from` again.
- `eventually` keeps it.
- `within` is the window, `{count, unit}` in seconds, minutes, hours or days. A calendar unit, a week or a
  month, does not compile ([`R6`](../contract.md#refusals-r)): the report measures elapsed time against the window, and a month has no
  fixed length.
- `or_else` is another event that keeps it the other way: the loan ended with the copy written off, which is
  a correct ending, just not the one wanted. `within` binds it as well, so a run that ends the other way
  three months late is not kept.
- `waits_on` names the external systems the promise waits on through an earlier step, when neither
  `eventually` nor `or_else` calls them itself. A subscription's invoice is issued, or the period is
  disputed, only after its usage is collected from the metering system; issuing the invoice does not call it:

  ```elixir
  promise :invoiced_within_two_days do
    from :period_closed
    eventually :invoice_issued
    within {2, :day}
    or_else :period_disputed
    waits_on [:metering]
  end
  ```

`from`, `eventually` and `or_else` are events the process includes ([`R5`](../contract.md#refusals-r)). Each system of `waits_on` is
an external of the domain, not one `eventually` or `or_else` already depends on, and one a contract the process
includes depends on or calls, since an outage is recorded only under such a contract ([`X4`](../contract.md#refusals-x)).

Each run gets one of four verdicts per promise:

| Verdict | When |
| --- | --- |
| kept | `eventually` or `or_else` happened inside the window; the report says which |
| broken | the window passed and neither happened |
| pending | the window has not passed yet; nothing is known |
| suspended | the window passed, and an external system the awaited events depend on (`depends_on:`), or one the promise `waits_on`, was seen unavailable inside it |

A suspended run is one the business is not answerable for, so it is counted apart and never as broken. Only
an outage of what `eventually` or `or_else` depends on, or of what the promise `waits_on`, suspends a run;
what `from` depended on was working, since `from` happened. An outage of a system the promise waits on
counts when any contract the process includes observed it.

**Recording an outage.** The adapter that calls the external system says when it was unavailable. Wrap its
call in `EhOsContract.Dependency.observe/3`, naming the contract and the external: an answer of
`{:error, :unavailable}` is recorded as an observation and handed back, and any other answer passes through
unrecorded, since an outage removes a finding from the report and nothing should be counted as one by guess.

```elixir
EhOsContract.Dependency.observe(MyApp.Contracts.Payments, :payment_gateway, fn ->
  MyApp.Gateway.charge(customer, amount)
end)
```

The observation is a moment, stamped with `EhOsContract.Clock.now/0`, so a test that moves the clock with
`EhOsContract.Clock.at/2` sees its outage where it happened. `EhOsContract.Dependency.unavailable!/4` records
one directly. The external has to be one the contract uses, through an event that `depends_on:` it or an
effect that `calls:` it.

When the unit of `from`'s event is finer than the run (a run of a loan in which each of several items is
lent), the promise is kept per item: each item's window opens at its own first `from`, an `eventually` or
`or_else` resolves the item its own identity fields name, and the run is broken if any item is.

A promise without `within` has no failing case: any `eventually` keeps it, and a run without one stays
pending for ever. That is honest when nobody agreed a number; `mix eh_os_contract.check` notes it, so it is
not read as a promise being kept.

## The deadline

`deadline {90, :day}` is how long a whole run may take, from its first event to the first event that ends
it. A run that ended inside the deadline was kept, one that ended outside it exceeded it, and one still open
past it is overdue: a finding of its own, since only a lower bound of its duration is known. An open run
inside its deadline is the normal case and is not mentioned. A deadline is declared once, in the same fixed
units as `within`, and needs `ends_on`, since it measures a run to its end ([`R6`](../contract.md#refusals-r)).

A run is reported in the period it **started**, and measured over its whole history, so a run started in June
and reported for July does not look as if it started in July.

## `unverified: true`

A promise or a deadline written before the process owner has confirmed its number is marked
`unverified: true`. Such a promise is still evaluated, and a test may ask for its verdicts, but the
conformance report leaves it out, and an unverified deadline with it: a number the client never agreed to,
printed beside the ones they did, reads as measured. `mix eh_os_contract.check` warns of each one until the
mark is removed.

## How the report reads a process

`mix eh_os_contract.report` asks four questions of each contract: which declared paths were never taken,
which transitions happened that were not declared, which promises were broken, and which version is
deployed. The first two are about the contract's steps and its units' lifecycles, which do not depend on a
process. The third is the process's: for each confirmed promise, how many runs kept it (and by which route),
broke it, are pending or suspended. Beside it the report prints the process's label, its accountable role,
the number of runs in the period, and the runs measured against a confirmed deadline: kept, exceeded,
overdue.

The report also counts the runs that entered a later stage before an earlier one, and names the pairs of
stages: a parcel booked with the carrier before it was picked. A stage is entered by its first event, and the order is
the log's, not the clock's: a process includes only contracts of its own application, so all its stages
are in one log. Only stages a run reached are compared, so a skipped stage, or one whose reaction still
waits in a queue, is no finding. A run belongs to the period by its first event, as its duration is measured, and is
judged on all of its events; the count of runs in the period takes every run with an event in it. The order
is judged by the stages declared today. The report says how many runs, never which: finding them is the
application's job (`EhOsContract.StageOrder`).

A process module gets a section of its own after the contracts': its deployment, runs, deadline,
promises and stage order, and no steps, lifecycles or scenarios, which are its contracts'. The JSON
document (`EhOsContract.Conformance.as_data/2`) carries it, keyed `process`, and the dashboard's status
screen shows it after the contracts, in the report's sentences.

When a deploy changes a promise, the runs whose `from` came before the change were held to a promise that
is no longer the one declared: the report counts them apart, not among the verdicts, and prints the date of
the change.

## Reading a process

`mix eh_os_contract.pages` writes a page for each process module, named after its `id:` without the domain's
name (`fulfilment.order` is `processes/order.md`): what tells its runs apart, the actor
accountable for it, its stages in order with each included event linked to its page in its contract, the
events that end a run, its promises and deadline, with an unconfirmed one said to be left out of the report,
the external systems its events rest on, and its scenarios. The domain's page and the page of each contract
whose events it includes link to it. Beside it, `graph/process/<id>.json` is its `graph.v1` document, the one
`mix eh_os_contract.graph --process <id>` prints. `mix eh_os_contract.view` lists the process modules under
the domain, each with its stages and the events each includes, and `mix eh_os_contract.glossary` lists one
under a term of a context whose events it includes when its id, a stage, a promise or a field of its
`correlate` is named with the term.

## What the compiler refuses

- An `id:` that is not the domain's `name:` then dotted snake_case segments ([`D11`](../contract.md#refusals-d)); a `domain:` that
  is not a compiled domain ([`X1`](../contract.md#refusals-x)).
- No `correlate`, an empty one, two, or one naming a field twice ([`R2`](../contract.md#refusals-r)); one of more than six fields
  ([`F9`](../contract.md#refusals-f)).
- A module without a stage, a stage including nothing, or an `include:` entry naming no event or no
  contract module ([`R3`](../contract.md#refusals-r)).
- An included event the contract does not declare ([`X5`](../contract.md#refusals-x)), or one whose `correlate` fields are missing,
  optional, personal or of another identifier ([`X6`](../contract.md#refusals-x)); two included events of one name ([`N1`](../contract.md#refusals-n)).
- A promise naming an event the process does not include, an `ends_on` event it does not include, or
  `ends_on` twice ([`R5`](../contract.md#refusals-r)).
- A `waits_on` naming no external of the domain, one the promise's `eventually` or `or_else` already
  depends on, or one no contract the process includes uses ([`X4`](../contract.md#refusals-x)).
- `within` or `deadline` in a calendar unit, negative, malformed or longer than 100 years; `deadline` twice, or
  without `ends_on`
  ([`R6`](../contract.md#refusals-r)).
- An `accountable` that is not an actor of the domain ([`X2`](../contract.md#refusals-x)); an `id:` another process of the system has
  ([`X7`](../contract.md#refusals-x)).

## What `mix eh_os_contract.check` reports

The [rules](../rules.md) about a process:

- **`process-without-accountable`** (warning): a finding about the process has nobody to go to. Name the
  role with `accountable`.
- **`unverified-declaration`** (warning): a deadline or a promise is marked `unverified: true`, so the
  report leaves it out. Remove the mark once the process owner confirms the number.
- **`promise-without-within`** (notice): the promise has no failing case. Add `within` when the owner
  agrees a window; leave it out while nobody has.
- **`owner-view-without-label`** (notice): a stage has no label, so a business owner reading the model
  would see its name in the code. Give it the words the business uses for that part of the run:
  `stage :departure, "Departure of the patient", include: …`.
