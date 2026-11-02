# Record an outage of an external system

<!-- covers: keys process.promise.waits_on -->

This page tells how to record that an external system was unavailable. A promise that waits for
the system then gets the verdict `suspended`, not `violated`. It is for a developer who writes the
adapter that calls an external system. [The glossary](glossary.md) defines each word in italics.

An *external system* is a system that the application exchanges data with. If it does not answer,
a run cannot go on, but the business did not break its promise. The engine cannot see an outage in
the log. Your adapter must record it. [What is a process module?](process.md) tells how the engine
then judges the run.

## Before you start

- The domain declares the external system. [What are actors, values, entities and external
  systems?](domain-data.md) tells how.
- A contract uses the system: an event of the contract `depends_on:` it, or an effect `calls:` it.
- A process module has a promise that waits for the system. Step 1 tells how.

This page uses these modules. The librarian charges for a lost copy only after the catalogue gives
the price of the copy. An effect asks the catalogue. The event `fine_charged` does not call the
catalogue itself:

```elixir
defmodule Concepts.Outages.Domain do
  use EhOsContract.Domain, name: :outages_example, language: :en

  subdomain :core, "Core", type: :core

  context :desk, "Lending desk", subdomain: :core

  actor :librarian, :human, "Librarian"

  external :catalogue, "Catalogue",
    direction: :outbound,
    unavailable_looks_like: "Lost copies are not charged" do
    operation :look_up_price, "Look up the price of a copy"
  end
end

defmodule Concepts.Outages.Contracts.Loans do
  use EhOsContract.Contract,
    domain: Concepts.Outages.Domain,
    context: :desk,
    id: "outages_example.loans"

  aggregate :loan, "Loan of a copy" do
    identity :loan_id

    command :write_off, "Write a copy off as lost", by: :librarian, emits: :copy_written_off do
      field :copy_id, :id
    end

    event :copy_written_off, "Copy written off as lost" do
      field :copy_id, :id
    end
  end

  effect :ask_price, "Ask the catalogue the price of a lost copy",
    handles: :copy_written_off,
    calls: {:catalogue, :look_up_price},
    idempotency: [key: :event_id, owner: :downstream]
end

defmodule Concepts.Outages.Contracts.Fines do
  use EhOsContract.Contract,
    domain: Concepts.Outages.Domain,
    context: :desk,
    id: "outages_example.fines"

  aggregate :fine, "Charge for a lost copy" do
    identity :fine_id

    command :charge_fine, "Charge for a lost copy", by: :librarian, emits: :fine_charged do
      field :loan_id, :id
      field :amount, :decimal
    end

    event :fine_charged, "Lost copy charged" do
      field :loan_id, :id
      field :amount, :decimal
    end
  end
end

defmodule Concepts.Outages.Processes.LostCopy do
  use EhOsContract.Process,
    id: "outages_example.lost_copy",
    domain: Concepts.Outages.Domain,
    label: "A lost copy, until it is charged",
    accountable: :librarian

  correlate :loan_id

  stage :loss, "Loss", include: [{Concepts.Outages.Contracts.Loans, :copy_written_off}]
  stage :charge, "Charge", include: [{Concepts.Outages.Contracts.Fines, :fine_charged}]

  promise :charged_within_a_week do
    from :copy_written_off
    eventually :fine_charged
    within {7, :day}
    waits_on [:catalogue]
  end
end
```

## 1. Make the promise wait for the system

A promise waits for a system in one of two ways:

- **`depends_on:`** If the `eventually` or the `or_else` event needs the answer of the system,
  declare `depends_on:` on that event. The promise then waits for the system with no more keys.
- **`waits_on`** If an earlier step calls the system, name the system in `waits_on` of the promise.
  In the example, the effect `ask_price` calls the catalogue before the charge.

Each system in `waits_on` is an external system of the domain. A contract of the process module
must use it. The `eventually` and the `or_else` event must not already depend on it
([`X4`](refusals.md#refusals-x)).

The result: the promise has a system that it waits for. An outage of that system inside the window
can suspend the run.

## 2. Wrap the call of the adapter in `observe/3`

Name the contract that uses the system, and the system:

```elixir
defmodule Concepts.Outages.CatalogueAdapter do
  def look_up_price(copy_id) do
    EhOsContract.Dependency.observe(Concepts.Outages.Contracts.Loans, :catalogue, fn ->
      Concepts.Outages.CatalogueClient.price(copy_id)
    end)
  end
end
```

- If the function returns `{:error, :unavailable}`, `EhOsContract.Dependency.observe/3` records
  one observation. Then it returns the same result.
- Any other result passes through, and the engine records nothing. This includes other errors,
  such as `{:error, :timeout}`.

An outage removes a violation from the report. So the engine records only an outage that your
adapter states.

> **One observation can suspend many runs.**
> Return `{:error, :unavailable}` only for an outage that you know of. An observation belongs to the
> contract and the system, not to one run. It suspends each run whose window holds its moment, for
> each customer. One short timeout that you record as an outage can hide a week of real violations.

The result: each `{:error, :unavailable}` adds one observation, at one moment, for the contract
and the system.

## 3. Record an outage without a call, if necessary

If your code learns of an outage in another way, record it directly:

<!-- not compiled: a call in the host's code -->
```elixir
EhOsContract.Dependency.unavailable!(Concepts.Outages.Contracts.Loans, :catalogue, "status page: down")
```

The third argument is the reason, and it is optional. Write a fixed description in it, never an
error or a response of the system. The engine keeps the reason as plain text, and an erasure does
not reach it.

A fourth argument gives the moment of the outage. Without it, the moment is
`EhOsContract.Clock.now/0`. A moment in the past changes the verdicts of runs that a report already
judged.

The result: the engine records one observation, as in step 2.

## 4. Record the outage under the correct contract

Which observations a promise reads depends on how it waits:

| The promise waits for the system through | The observation counts if it is recorded under |
| --- | --- |
| `depends_on:` of its `eventually` or `or_else` event | the contract that declares that event |
| `waits_on` | any contract that the process module includes |

The moment of the observation must be at or after the first `from` of the run. It must also be at
or before the end of the window. An outage of a system that only an effect calls suspends a promise
only through `waits_on`. The engine records it all the same.

## 5. Test the outage

- **In a scenario of the process module**, give the moment of the outage: `outage :catalogue, at:
  "2026-09-10T08:00:00Z"`. [Write a domain, a contract and a process module](contract.md) shows a
  scenario of a process module.
- **In a test that uses the log**, run the code in `EhOsContract.Clock.at/2`. `observe/3` stamps
  the observation with `EhOsContract.Clock.now/0`, so the outage is at the moment that the test
  sets, as the events are. `Clock.at/2` applies only in the process that calls it. An adapter that
  runs in another process stamps the current time. `Clock.at/2` accepts only a time in UTC.

The result: the verdict of the promise is `:suspended` for a run whose window ended empty with the
outage inside it.

## What can go wrong

**`<contract> uses no external <name>`.** The contract has no event that `depends_on:` the system,
and no effect that `calls:` it. Name a contract that uses it. `observe/3` checks this only when the
call returns `{:error, :unavailable}`. So a wrong name raises an error only during an outage.
Test the outage path once.

**`<module> is a domain, not a contract`**, or another kind. The engine records an observation
under a contract. Name the contract whose event or effect uses the system.

**The run is `violated`, not `suspended`.** Make sure of these:

- The observation is under the correct contract: see step 4.
- The moment of the outage is inside the window of the run.
- The system is one that the `eventually` or the `or_else` event depends on, or one in `waits_on`.
  An outage of a system that only `from` depends on suspends nothing.
- The promise has `within`. A promise without `within` is never `suspended`.

## Next steps

- [What is a process module?](process.md): the verdicts of a promise, and what moves each one.
- [The conformance report](conformance.md): how the report prints the suspended runs.
- [What are actors, values, entities and external systems?](domain-data.md):
  how to declare an external system.
- [The compile refusals](refusals.md#refusals-x): the refusal of a `waits_on`, in the family X.
