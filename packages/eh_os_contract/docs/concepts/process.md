# Processes: runs, stages, promises and deadlines

What a process adds to the units that decide: runs that group their events, the stages a run goes through,
how a run ends, what the process owner promised about it, and how the conformance report holds the log to
those promises.

<!-- covers: entities contract.process, contract.process.stage, contract.process.include, contract.process.promise, contract.process.deadline, process.correlate, process.stage, process.ends_on, process.promise, process.deadline; rules process-without-accountable, promise-without-within, deadline-without-terminal-event, unverified-declaration -->

A unit decides over its own stream: one loan, one fine. A business is usually accountable for something
longer (a loan from the day the copy goes out to the day it comes back, or is paid for) and that is a
**run** of a process. The units do not need a process to decide; the process is what the engine measures.
Its events are the units' events, and nothing is dispatched to a process. What it adds is a way to file
those events into runs, and a set of claims about runs that the report can check against the log.

There are two places to write one. **A contract's `process`** describes a run made of that contract's own
events, and of the sibling events it includes. **A process module**, `use EhOsContract.Process`, describes a
run that crosses several contracts, naming each contract's events it takes. [The guide](../contract.md)
introduces both; this page is how they behave.

## A run, and what tells one from another

`correlate` names the fields that tell which run an event belongs to. When an event is appended, the engine
reads those fields from it and files the event under the process's name and their values, in the same
append as the event itself. Every local event of a contract with a process carries the fields: a field the
process correlates on is required in every one of them (the unit's identity counts), never optional and
never personal (`R2`, `F4`), and it is an identifier, `:id`, `{:id, entity}` or a domain value resting on
one (`F8`). An event may belong to more than one run: its own contract's, and the run of every process that
includes it.

So a process that correlates on `:loan_id` puts the loan's first event and its last in one run, and a fine
recorded in another contract with the same `loan_id` in that run too, if the process includes it. A run is
never named by the report: it counts runs and verdicts, and which loan is late is a question for the
application, which already knows.

Correlate on what the business means by "one case". A run keyed by too coarse a field, a member instead of a
loan, gathers unrelated loans into one and judges them together; one keyed by too fine a field splits a case
in two, and a promise that spans both halves is never kept. At most six fields make one key (`F9`).

## A process in a contract

<!-- covers: entities contract.process -->

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

    stage :lending do
      event :copy_lent, "Copy lent" do
        field :copy_id, :id
      end
    end

    stage :return do
      event :copy_returned, "Copy returned", terminal: true
      event :copy_written_off, "Copy written off as lost", terminal: true
    end
  end

  process :borrowing, "A loan, from lending to return" do
    correlate :loan_id
    accountable :librarian

    stage :lending, "Lending"
    stage :return, "Return"

    deadline {90, :day}, unverified: true

    promise :back_within_a_month do
      from :copy_lent
      eventually :copy_returned
      within {30, :day}
      or_else :copy_written_off
      source "Lending rules, section 4"
    end
  end
end
```

A contract holds at most one process (`R1`), and the process's name keys its runs: two processes of one
system may not share it (`X7`). Renaming it changes the key every run is filed under, so the report no
longer finds the runs already in the log.

**Stages** are the steps of a run, in order. The process lists them; each unit places its events in them with
a `stage` group. Stages are all or nothing: once the process declares one, every local event sits in a group,
and a group names a stage the process declares (`R3`). A process without stages is legal and common: a
run with one step has nothing to divide. Stages are what the graph and the pages draw; the engine does not
hold a run to their order.

**A run ends** on an event marked `terminal: true`. Whichever terminal event comes first ends it, and a later
event does not reopen it. A run with no terminal event yet is open. A contract without a process has no
runs, so it may have neither stage groups nor terminal events (`R1`).

**An event of a sibling contract** joins the run with `include`, inside the stage it belongs to, and may end
the run with `include :fine_settled, terminal: true`. Only an event the contract consumes from a sibling may
be included; a local event is placed by its unit's stage group, and an event received from another
application never enters this log (`R4`). How a contract consumes a sibling's events is in
[between contracts](between-contracts.md).

**`accountable`** names the role that answers for the process: the actor a finding about it is addressed
to. The report prints the actor's label beside the process. It is an actor of the domain, and not one of
another context (`X2`).

The keys of each entity are on [the reference page](../dsl/contract-process.md).

## Promises

A promise is what the process owner agreed happens in a run: after one event, another eventually follows.

- `from` opens it. A run in which `from` never happened is not judged at all: there is nothing to keep yet.
  The window opens at the **first** `from` of the run, so a run cannot put its deadline off by recording
  `from` again.
- `eventually` keeps it.
- `within` is the window, `{count, unit}` in seconds, minutes, hours or days. A calendar unit, a week or a
  month, does not compile (`R6`): the report measures elapsed time against the window, and a month has no
  fixed length.
- `or_else` is another event that keeps it the other way: the loan ended with the copy written off, which is
  a correct ending, just not the one wanted. `within` binds it as well, so a run that ends the other way
  three months late is not kept.

`from`, `eventually` and `or_else` are events of the run: local events, or included ones (`R5`).

Each run gets one of four verdicts per promise:

| Verdict | When |
| --- | --- |
| kept | `eventually` or `or_else` happened inside the window; the report says which |
| broken | the window passed and neither happened |
| pending | the window has not passed yet; nothing is known |
| suspended | the window passed, and an external system the awaited events depend on (`depends_on:`) was seen unavailable inside it |

A suspended run is one the business is not answerable for, so it is counted apart and never as broken. Only
an outage of what `eventually` or `or_else` depends on suspends a run; what `from` depended on was working,
since `from` happened.

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
inside its deadline is the normal case and is not mentioned. A deadline is declared once (`R6`), in the same
fixed units as `within`.

A run is reported in the period it **started**, and measured over its whole history, so a run started in June
and reported for July does not look as if it started in July.

## `unverified: true`

A promise or a deadline written before the process owner has confirmed its number is marked
`unverified: true`. Such a promise is still evaluated, and a test may ask for its verdicts, but the
conformance report leaves it out, and an unverified deadline with it: a number the client never agreed to,
printed beside the ones they did, reads as measured. `mix eh_os_contract.check` warns of each one until the
mark is removed.

## A process across contracts

<!-- covers: entities process.correlate, process.stage, process.ends_on, process.promise, process.deadline -->

When one run crosses contracts that each decide a part of it, the run is a module of its own. Here a lost
copy is charged for in a second contract, and the loan ends when the copy comes back or the charge is
settled:

```elixir
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

  stage :lending, include: [{Concepts.Process.Contracts.Loans, :copy_lent}]

  stage :return, "Return",
    include: [{Concepts.Process.Contracts.Loans, [:copy_returned, :copy_written_off]}]

  stage :charge, "Charge",
    include: [{Concepts.Process.Contracts.Fines, [:fine_charged, :fine_settled]}]

  ends_on [:copy_returned, :fine_settled]

  promise :lost_copy_charged_within_a_week do
    from :copy_written_off
    eventually :fine_charged
    within {7, :day}
  end

  deadline {120, :day}
end
```

The module reads like a contract's process, with these differences:

- **It decides nothing and declares no event.** Each stage's `include:` names a contract and its events,
  `{Contract, :event}` or `{Contract, [:event, …]}`, without a compile dependency on the contract. The
  events are ones the contract declares, not ones it consumes or receives (`X5`). Everywhere else in the
  module an event is named by its name alone, so two included events of one name are refused, whichever
  contracts they come from (`N1`).
- **`correlate` is checked in every included event**: each carries the fields, required and not personal,
  as the same kind of identifier in every contract (`X6`). Here `loan_id` is the loan's identity in `Loans`
  and an ordinary field in `Fines`; both are `:id`.
- **`ends_on` lists the events that end a run**, instead of `terminal:` on the events, since the contracts
  are not this module's to mark. A `deadline` needs `ends_on`, because it measures a run to its end (`R6`).
- **`accountable` is an option of the `use`**, and may name an actor of any context of the domain, since
  the module crosses them (`X2`).
- **Its runs are filed under its `id:`**, at the append of each included event, beside the event's own
  contract's run. An included event without a value for every `correlate` field belongs to none of its runs.

The module compiles to a model `EhOsContract.Model.fetch/1` returns, of kind `:process`. Its keys are on
[the reference page](../dsl/process-dsl.md).

## How the report reads a process

`mix eh_os_contract.report` asks four questions of each contract: which declared paths were never taken,
which transitions happened that were not declared, which promises were broken, and which version is
deployed. The first two are about the contract's steps and its units' lifecycles, which do not depend on a
process. The third is the process's: for each confirmed promise, how many runs kept it (and by which route),
broke it, are pending or suspended. Beside it the report prints the process's label, its accountable role,
the number of runs in the period, and the runs measured against a confirmed deadline: kept, exceeded,
overdue.

A process module gets a section of its own after the contracts': its deployment, runs, deadline and
promises, and no steps, lifecycles or scenarios, which are its contracts'. It is not yet in the JSON the
dashboard reads.

When a deploy changes a promise, the runs whose `from` came before the change were held to a promise that
is no longer the one declared: the report counts them apart, not among the verdicts, and prints the date of
the change.

## What the compiler refuses

- A second `process` in a contract, or with none, a stage group or a `terminal:` event (`R1`): add the
  process, or take the run-only markings out.
- A process correlating on nothing, or a local event missing a correlated field (`R2`); a correlated field
  that is optional or personal (`F4`), or not an identifier (`F8`).
- With stages, an event outside every stage group, or a group naming a stage the process does not declare
  (`R3`); a process module without a stage, or a stage including nothing (`R3`).
- `include` of a local event, or of one the contract does not consume (`R4`).
- A promise naming an event that is not in the run, or in a process module an `ends_on` event it does not
  include, or `ends_on` twice (`R5`).
- `within` or `deadline` in a calendar unit, negative, or malformed; `deadline` twice; in a process module, a
  `deadline` without `ends_on` (`R6`).
- In a process module, an included event the contract does not declare (`X5`), or one whose `correlate`
  fields are missing, optional, personal or of another identifier (`X6`).

## What `mix eh_os_contract.check` reports

The [rules](../rules.md) about a process apply to a contract's and a module's alike, except where noted:

- **`process-without-accountable`** (warning): a finding about the process has nobody to go to. Name the
  role with `accountable`.
- **`unverified-declaration`** (warning): a deadline or a promise is marked `unverified: true`, so the
  report leaves it out. Remove the mark once the process owner confirms the number.
- **`promise-without-within`** (notice): the promise has no failing case. Add `within` when the owner
  agrees a window; leave it out while nobody has.
- **`deadline-without-terminal-event`** (notice, a contract's process only): no event ends a run, so no
  duration can be measured. Mark the events that end a run `terminal: true`. A process module cannot get
  here, since its `deadline` does not compile without `ends_on`.
