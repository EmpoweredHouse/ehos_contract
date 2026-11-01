# The conformance report

This page tells what the conformance report gives: each section, and each sentence of a process
module. It also tells which period each number reads, and gives the JSON document. It is for a developer or an operator who
reads the report, and for a person who builds a screen on its JSON. [The glossary](glossary.md)
defines each word in italics.

*Conformance* is the comparison of the log with what the contracts and the process modules
declare. The report answers [the four questions](glossary.md#four-questions), and nothing more:

1. Which declared paths were never taken?
2. Which transitions occurred that the contract does not declare?
3. Which promises were broken?
4. Which version of the contract is deployed, and since when?

The report counts runs and paths. It never names a run. Which runs are late is a question for the
application, which keeps the state of the business.

![The application runs on the contracts and appends events, and conformance compares the log with what the contracts and process modules declare.](img/conformance-flow.svg)

## The command

```bash
mix eh_os_contract.report --since 2026-07-01T00:00:00Z --until 2026-07-31T23:59:59Z
```

| Option | Value | If you leave it out |
| --- | --- | --- |
| `--since` | the start of the period, ISO 8601 with an offset (`Z`) | the period has no start |
| `--until` | the end of the period, ISO 8601 with an offset | the period has no end |
| `--output` | a file | the report goes to the terminal |

- A time without an offset stops the task with an error.
- The task starts the application, because it reads the log through the repo.
- The report has a section for each contract, then a section for each process module.
- The moment of judgement is always the current time. The task has no option to change it.

[The tasks](cli.md) give the task in full.

## Which events does each number read?

The numbers of one process module do not all count the same runs:

| Number | Which runs | Which events of a run |
| --- | --- | --- |
| Runs in this period | each run with an included event in the period | — |
| The deadline | each run whose first event is in the period | all its events, also after the period |
| Stages out of order | each run whose first event is in the period | all its events, also after the period |
| The verdicts of a promise | each run with a `from` in the period | only the events in the period |

So a report with a period judges a promise only on the events inside the period:

- If the first `from` of a run is before the period, a later `from` in the period opens the window.
- The report does not read an `eventually` or an `or_else` after the end of the period. A run kept
  after the period can show as violated.
- Outages are not limited to the period. An outage in the window counts, also if it was before the
  period.

To judge each promise over the whole log, leave out `--since` and `--until`.

## The section of a contract

The section of a contract has these parts, in this order:

| Part | What it says | Question |
| --- | --- | --- |
| `CONTRACT: <id>` | the version that is deployed, since when, the wiring version, what changed since the previous version, and the events of earlier versions | 4 |
| `STEPS` | the events and commands in the period; the agreed steps that were never carried out, that are in progress, and that are attempted and fail | 1 |
| `LIFECYCLE: <label>` | for each aggregate with a lifecycle: the declared transitions never taken, those not taken yet, and those that occurred though the lifecycle does not allow them | 1, 2 |
| `SCENARIOS` | how many scenarios the log shows; the scenarios never observed; the outcomes that no scenario declares | — |
| `DRIFT` | the events that occurred though the contract does not agree them | 2 |

[What are the units that decide?](units.md) tells about a lifecycle.

## The section of a process module

This page uses this process module:

```elixir
defmodule Concepts.Conformance.Domain do
  use EhOsContract.Domain, name: :conformance_example, language: :en

  subdomain :core, "Core", type: :core

  context :desk, "Lending desk", subdomain: :core

  actor :librarian, :human, "Librarian"
end

defmodule Concepts.Conformance.Contracts.Loans do
  use EhOsContract.Contract,
    domain: Concepts.Conformance.Domain,
    context: :desk,
    id: "conformance_example.loans"

  aggregate :loan, "Loan of a copy" do
    identity :loan_id

    command :lend_copy, "Lend a copy", by: :librarian, emits: :copy_lent
    command :take_back, "Take a copy back", by: :librarian, emits: :copy_returned
    command :write_off, "Write a copy off as lost", by: :librarian, emits: :copy_written_off

    event :copy_lent, "Copy lent"
    event :copy_returned, "Copy returned"
    event :copy_written_off, "Copy written off as lost"
  end
end

defmodule Concepts.Conformance.Processes.Loan do
  use EhOsContract.Process,
    id: "conformance_example.loan",
    domain: Concepts.Conformance.Domain,
    label: "A loan, until the copy is back",
    accountable: :librarian

  correlate :loan_id

  stage :lending, "Lending", include: [{Concepts.Conformance.Contracts.Loans, :copy_lent}]

  stage :return, "Return",
    include: [{Concepts.Conformance.Contracts.Loans, [:copy_returned, :copy_written_off]}]

  ends_on [:copy_returned, :copy_written_off]

  deadline {60, :day}

  promise :back_within_a_month do
    from :copy_lent
    eventually :copy_returned
    within {30, :day}
    or_else :copy_written_off
  end
end
```

For July, its section can read like this. The numbers are an example:

```text
PROCESS MODULE: conformance_example.loan
  Version <version>, deployed since 2026-06-12.

PROCESS: A loan, until the copy is back
  Accountable: Librarian.
  Runs in this period: 41, one per loan_id.
  Deadline: 60 days from the start.
  The agreed duration was exceeded in 2 of 35 runs that finished.
    3 runs still open and already past it.
  Stages out of order in 1 run:
    · Return before Lending: 1 run
  Rule: after "Copy lent" within 30 days, "Copy returned" follows, or else "Copy written off as lost".
    BREACHED in 2 of 38 runs. Of those that were met, 4 runs reached the fallback ending, which conforms to the rule.
```

Each line, in order:

| Line | What it says |
| --- | --- |
| `PROCESS MODULE: <id>` | the `id:` of the process module |
| `Version …` | a hash of the declarations, and the day that a deployment with this version was first recorded. Without a recorded deployment: "not recorded as deployed". Then what changed since the previous version. |
| `PROCESS: <label>` | the `label:` of the process module |
| `Accountable: …` | the label of the actor in `accountable`. No line without one. |
| `Runs in this period: …` | the count of runs, and the correlation fields |
| `Deadline: …` | the confirmed deadline. No line for an unverified deadline. |
| the duration | "The agreed duration was kept in all N runs that finished", "…was exceeded in X of N runs that finished", or "No run finished in this period, so the agreed duration cannot be judged". Then the overdue runs: "N runs still open and already past it." |
| `Stages out of order in N runs:` | each pair of stages, as "Later before Earlier: N runs". No line if each run kept the order. |
| `Rule: …` | one confirmed promise, in the labels of its events |
| the verdict | see the next table, and then the qualifications |

The verdict of a promise is one sentence:

| Case | Sentence |
| --- | --- |
| a run is violated | `BREACHED in V of N runs.` |
| no run is violated, a run is pending | `Met in S of N, P still in progress.` |
| each run is satisfied | `Met in all N runs.` |
| no run to judge | `There was no run in this period on which this could be judged.` |
| each run started before the promise changed | `No run in this period was judged under the rule as it now stands.` |

The qualifications follow the verdict, each as one sentence:

| Qualification | Sentence |
| --- | --- |
| the satisfied runs that took the route `or_else` | `Of those that were met, N runs reached the fallback ending, which conforms to the rule.` |
| the suspended runs | `Suspended: N runs — an external dependency was unavailable within the rule's window, so this is not a breach on the client's side.` |
| the runs that started under an earlier version of the promise | `N runs began before this rule was last changed (2026-06-12) and are not counted here — they were judged under a different promise.` |

The section leaves out each unverified promise, and an unverified deadline. It has no steps, no
lifecycle and no scenarios: these belong to the contracts. [What is a process module?](process.md)
tells how the engine gets each verdict.

## How does the report count the stages out of order?

A run is out of order if it entered a later stage before an earlier one:

- A run enters a stage at the first event of that stage.
- The order is the order in the log, not the order of the clock. A process module includes only
  contracts of its own application, so all its stages are in one log.
- The report compares only the stages that the run reached. A stage that the run skipped is not a
  finding. Neither is a stage whose reaction still waits in a queue.
- The report judges the stages that the process module declares today.
- If fewer than 2 stages have events that the report can read, it compares nothing.

The report gives each pair of stages, with the count of runs. It never names a run.
`EhOsContract.StageOrder.evaluate/2` gives the same counts.

## What does the report do when a promise changes?

A deploy can change the declaration of a promise. Then a run that started before the change was held
to a promise that is no longer declared:

- The boundary is the last deploy that changed the promise, ever. It is the moment at which the
  engine first recorded that deployment.
- A run whose first `from` is before the boundary is not counted among the verdicts. The report
  gives a count of these runs, with the date of the boundary.
- A run whose first `from` is at or after the boundary gets a verdict under the new promise.
- A promise that a deploy adds is not a change.
- A changed deadline has no boundary. The report measures each run against the deadline of today.

## The JSON document

`EhOsContract.Conformance.as_data/2` gives the same report as values that JSON can carry. The
document of a process module has this shape:

```json
{
  "schema": "eh_os_contract.conformance.v3",
  "generated_at": "2026-08-01T06:00:00Z",
  "report": {
    "process": "conformance_example.loan",
    "module": "Concepts.Conformance.Processes.Loan",
    "engine": "0.13.2",
    "period": {"since": "2026-07-01T00:00:00Z", "until": "2026-07-31T23:59:59Z"},
    "deployment": {"process": "…", "deployed": {"version": "…", "wiring_version": "…", "since": "…"}, "changed": null},
    "processes": [
      {
        "process": "conformance_example.loan",
        "label": "A loan, until the copy is back",
        "accountable": "Librarian",
        "correlate": ["loan_id"],
        "runs": 41,
        "declarations": [{"key": "deadline", "value": {"count": 60, "unit": "day"}}],
        "duration": {"runs": 38, "within": 33, "exceeded": 2, "overdue": 3, "open": 0, "deadline": {"count": 60, "unit": "day"}},
        "promises": [
          {
            "promise": "back_within_a_month",
            "from_label": "Copy lent",
            "eventually_label": "Copy returned",
            "or_else_label": "Copy written off as lost",
            "within": {"count": 30, "unit": "day"},
            "declaration_changed_at": null,
            "under_earlier_declaration": 0,
            "instances": 38,
            "satisfied": 36,
            "satisfied_via_eventually": 32,
            "satisfied_via_or_else": 4,
            "violated": 2,
            "pending": 0,
            "suspended": 0
          }
        ],
        "out_of_order": {"runs": 1, "pairs": [{"earlier": "lending", "later": "return", "runs": 1, "earlier_label": "Lending", "later_label": "Return"}]}
      }
    ]
  }
}
```

- The report of a contract has `"contract"` in the place of `"process"`. Each report has one of the
  two keys.
- `"duration"` is `null` if the process module has no confirmed deadline.
- `"duration"` counts each run that started in the period: `within`, `exceeded`, `overdue` and
  `open` add up to `runs`.

## The dashboard

The dashboard (`eh_os_contract_web`) shows the same sentences. Its status screen shows the
contracts, then the process modules. It reads the whole log, with no period.

Its JSON API, which the host mounts with `eh_os_contract_api`, gives the document above:
`GET <path>/conformance?process=<id>`, with `since` and `until` if necessary. A request that names
both `contract` and `process` is refused as a bad request.

## The functions

| Function | Gives |
| --- | --- |
| `EhOsContract.Conformance.report/2` | the report of one contract or process module, as Elixir data |
| `EhOsContract.Conformance.as_data/2` | the same report, as values for JSON |
| `EhOsContract.Conformance.promise_verdicts/2` | the counts of each confirmed promise |
| `EhOsContract.Trace.evaluate/3` | the verdict of each run for one promise, also an unverified one |
| `EhOsContract.Trace.judge/3` | the verdicts for events that you give, with no database |
| `EhOsContract.StageOrder.evaluate/2` | the count of runs out of order, and the pairs of stages |

Each function except `Trace.judge/3` takes `since:` and `until:`. `report/2`, `promise_verdicts/2`
and `Trace.evaluate/3` also take `now:`, the moment of judgement. `Trace.judge/3` requires `now:`.

## Next steps

- [What is a process module?](process.md): runs, promises, verdicts and the deadline.
- [Record an outage of an external system](outages.md): how a run gets the verdict `suspended`.
- [What are the units that decide?](units.md): the lifecycles that the report reads.
- [The tasks](cli.md): each option of `mix eh_os_contract.report`.
