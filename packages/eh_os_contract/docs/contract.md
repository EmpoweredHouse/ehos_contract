# Writing a domain and a contract

A business process is written down twice over: once as a **domain** — the words its people use, the
contexts it is split into, who acts in it and which systems it depends on — and once per process as a
**contract**: what is decided, what happened, what reacts to it, what is read, and what was promised.
Both are Elixir modules on [Spark](https://hexdocs.pm/spark), in the manner of
[ESDM](https://www.esdm.io): the model is code, and there is nothing beside it.

The engine reads them twice. At compile time it refuses a model that contradicts itself and code that
contradicts the model. At run time it dispatches commands through the model, appends what they decide to
its own log, and compares what the log holds with what the contract promised.

This page is how to start and what will not compile. Every key of both DSLs, with its type, default and
description, is in the generated reference: [the domain](dsl/domain.md) and [the contract](dsl/contract.md).
What `mix eh_os_contract.check` reports about a model that compiles is in [its rules](rules.md).

## A domain

```elixir
defmodule Lending.Domain do
  use EhOsContract.Domain, name: :lending, language: :en

  subdomain :core, "Core", type: :core

  context :loans, "Loans", subdomain: :core

  actor :librarian, :human, "Librarian"
end
```

`name:` is the application's name towards EHOS: capabilities are `lending.<command>` and roles
`lending.<actor>`. `language:` is the language the labels are written in — labels are the words of the
people in the process, in their language, and the engine prints them as written.

## A contract

A contract belongs to one context of one domain, and holds one process.

```elixir
defmodule Lending.Contracts.Loans do
  use EhOsContract.Contract, domain: Lending.Domain, context: :loans

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

    event :copy_returned, "Copy returned", terminal: true
  end

  process :lending, "A loan, from lending to return" do
    correlate :loan_id

    promise :returned_within_a_month do
      from :loan_opened
      eventually :copy_returned
      within {30, :day}
    end
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
- **A command names who may issue it** (`by:`), what it may emit, and which invariants it may refuse on.
  Dispatch refuses an actor outside `by:` before anything else. An event outside `emits:` after the
  decision raises: it is a defect in the code, never a business outcome, and nothing is appended.
- **The process is the run**: `correlate` names the fields that make one run, `stage` groups its events
  when it has stages, and a `promise` is what the process owner agreed happens — from one event, eventually
  another, within a time, or else a third. `deadline` and `cadence` bound the whole run.
- **A scenario is a test the contract carries** — given events, when a command, then events or a
  rejection. Every invariant needs a `rejected` scenario (S8). `EhOsContract.ScenarioCase` turns each into
  an ExUnit test against the implementation:

  ```elixir
  use EhOsContract.ScenarioCase, contract: Lending.Contracts.Loans
  ```

What reacts to events is declared beside the units: a `policy` issues a command of this contract, an
`effect` calls an external system, a `process_manager` steers a run with its own state and timers, and a
`read_model` projects rows that a `query` reads. `consumes` takes a sibling contract's events, and
`publish` lets one leave the application.

## The code that decides

A contract names no implementation. A module binds to one of its declarations, and the contract generates
the structs and the behaviour that module implements:

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

`emit/1` takes the literal structs a command may produce, and refuses at compile time one outside its
`emits:`; `reject/1` names one of its `rejects:`. Implementations point at the contract, never the other
way round, so changing the code never recompiles the contract, and the engine finds them in the running
binary (`config :eh_os_contract, applications: [...]`).

A command goes through `EhOsContract.dispatch/3`, with the actor the host authenticated:

```elixir
EhOsContract.dispatch(Lending.Contracts.Loans, %OpenLoan{loan_id: id, copy_id: copy, member_id: member},
  actor: actor
)
```

Who the actor is, and how the credential EHOS issues becomes one, is in [authorization](authorization.md).

## What will not compile

A model is checked in five layers. The first four refuse; the fifth reports.

| Layer | When | What it is |
| --- | --- | --- |
| L1 | compile | Spark's schema: an unknown key or entity, a missing required one, a wrong type |
| L2 | compile | the rules of one module, a domain's or a contract's, each with its file and line |
| L3 | compile | `compile.eh_os_contract`, the rules between modules: a contract against its domain and its siblings |
| L4 | compile | the implementation macros, at the `use` or the call that breaks them |
| L5 | `mix eh_os_contract.check` | what a model may legally say and a reader should still hear about ([rules](rules.md)) |

L3 is a Mix compiler, because references between the modules record no compile dependency. A host
registers it after Elixir's:

```elixir
compilers: Mix.compilers() ++ [:eh_os_contract]
```

Every refusal of L2–L4 starts with its code. The codes do not change between versions; the sentences may.

| Code | Layer | What is refused |
| --- | --- | --- |
| `N1` | L2 | a name that is not snake_case, or not unique where it has to be: units; a unit's commands, events, timers and consumed aliases together; invariants per unit; stages; promises |
| `N2` | L2 | a reserved word, or a name that clashes with a Kernel function at its callback's arity |
| `F1` | L2 | a field named twice in one struct, or starting with `__` |
| `F2` | L2 | a malformed type; an enum that is empty or repeats a member |
| `F3` | L2 | `default:` outside a `state` |
| `F4` | L2 | an optional or personal field used as identity, correlation, `match` or a tag |
| `F5` | L2 | `personal:` naming anything but a required, non-personal `:id` field of the same struct that declares `subject:` |
| `F6` | L2 | an injected identity field declared again |
| `F7` | L2, L3 | a personal field where the library keeps the value outside the log: a process manager's state, a query's scope |
| `A1` | L2 | an empty `emits:`, or one naming an event of another unit |
| `A2` | L2 | an event no command of its unit emits and that declares no `recorded_by:` |
| `A3` | L2 | `rejects:` naming what is neither an invariant of the unit nor a constraint of the command |
| `A4` | L2 | a boundary without `consults`, or one naming an unknown event, without `match` or `where`, or matching outside its identity |
| `A5` | L2 | `state` declared twice |
| `A6` | L2 | a generated identity with no command that `creates:` it, or `creates:` on a unit whose identity is not generated |
| `A7` | L2 | a command's constraint named twice, as an invariant of its unit, or missing from its `rejects:` |
| `C1` | L2 | a command nobody can issue: no `by:`, and no policy or process manager of the contract issues it |
| `P1` | L2 | a policy handling events that are neither local nor consumed, or issuing a command of another contract |
| `P2` | L2 | an effect with `calls:` delivered `:in_transaction` |
| `P3` | L2 | a policy or an effect delivered `:at_least_once` without `idempotency` |
| `P4` | L2 | a process manager reacting to anything but events and its own timers; a timer without exactly one of `wait` and `at`; `at` naming anything but a timestamp of its state; `sets` or `cancels` naming a timer it does not have; `correlate: []` |
| `P5` | L2 | `projects` naming an event that is neither local nor consumed; `reads` naming a read model of another contract |
| `R1` | L2 | a contract without exactly one `process` |
| `R2` | L2 | a `correlate` field missing from a local event, or no `correlate` field at all |
| `R3` | L2 | stages declared and an event outside every stage, or an `include` without one; no stages and a group |
| `R4` | L2 | `include` naming an event that is not consumed |
| `R5` | L2 | a promise's `from`, `eventually` or `or_else` naming an event outside the run |
| `R6` | L2 | a `within`, `deadline` or `wait` in a calendar unit, or with a negative count |
| `K1` | L2 | a contract consuming itself, naming no events, or renaming one it does not consume |
| `S1` | L2 | a scenario without exactly one trigger, or one naming what does not exist |
| `S2` | L2 | `given` or `expect` naming an event outside the unit, what it consults, or what the query's read model projects |
| `S3` | L2 | scenario data naming undeclared fields, missing required ones, or of the wrong built-in type |
| `S4` | L2 | `rejected` naming what the command does not `rejects:` |
| `S5` | L2 | `expect` naming an event outside the command's `emits:` |
| `S6` | L2 | a trigger and an outcome that do not fit the kind of what is triggered |
| `S7` | L2 | a scenario's `actor` outside the command's `by:` |
| `S8` | L2 | an invariant or a constraint that no `rejected` scenario covers |
| `S9` | L2 | a domain service's rule without examples, or with an example of the wrong arity or type, or given twice |
| `D1` | L2 | a domain name given twice within its kind |
| `D2` | L2 | two translations into one language, or one into the context's own |
| `D3` | L2 | a value with both or neither of a type and fields; `unit` on a type that is not numeric; values in a cycle |
| `D4` | L2 | a human actor `backed_by` a system |
| `D5` | L2 | a relation whose roles do not fit its type, whose ends do not exist, or which relates a context to itself |
| `D6` | L2 | `{:id, entity}` naming an entity the domain does not declare |
| `D7` | L2 | a context in a subdomain the domain does not declare |
| `D8` | L2 | `issued_by:` naming what is not an external of the domain |
| `D9` | L2 | a value's invariant misnamed, or without both a `violated_by:` and a `satisfied_by:` example |
| `D10` | L2, L3 | a scope that is not one required, non-personal field, or an actor in `by:` that does not carry its dimension |
| `D11` | L2, L3 | a publication named outside the domain's `name:`, unversioned, or carrying a field that is not plain data |
| `D14` | L3 | two commands or queries of one domain with the same name, and so the same capability |
| `X1` | L3 | `domain:` naming a module that is not a domain declaring `context:` |
| `X2` | L3 | `by:`, `recorded_by:`, `accountable` or a scenario's `actor` naming no actor of this context |
| `X3` | L3 | a field type that is not built in and not a value of the domain; a `subject:` the domain does not declare |
| `X4` | L3 | `depends_on` or `calls` naming no external of the domain |
| `X5` | L3 | `consumes` naming what is not a compiled contract of the same domain, or an event it does not declare |
| `X6` | L3 | a field a subscriber relies on — in `correlate`, `match` or `include` — missing from the publisher, or of another type |
| `X7` | L3 | two processes of the system with one name, and so one event type |
| `X8` | L3 | a declaration with two implementations |
| `X9` | L3 | a scenario value that does not fit its domain type, or data of a consumed event that does not fit it |
| `I1` | L4 | `use` naming no declaration, or one of another kind |
| `I2` | L4 | a callback the declaration needs and the module does not define |
| `I3` | L4 | `evolve` without a clause for an event of the unit |
| `I4` | L4 | `emit` given anything but literal structs the command may emit |
| `I5` | L4 | `reject` naming what the command does not `rejects:` |
| `I6` | L4 | `issue` naming a command outside `issues:` |
| `I7` | L4 | a macro where its kind does not allow it: `emit` and `reject` outside a unit, `issue` outside a policy or process manager |

The longer reasons for each rule are in `docs/adr/contract-v2.md` §6, in the repository.
