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
the structs and the behaviour that module implements. The structs live under the contract —
`Lending.Contracts.Loans.Commands.OpenLoan`, `Lending.Contracts.Loans.Events.LoanOpened` — and a module
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

`emit/1` takes the literal structs a command may produce, and refuses at compile time one outside its
`emits:`; `reject/1` names one of its `rejects:`. Implementations point at the contract, never the other
way round, so changing the code never recompiles the contract, and the engine finds them in the running
binary (`config :eh_os_contract, applications: [...]`).

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
| `N1` | L2 | a name not snake_case; a name twice among: declarations of one kind; a unit's invariants or stage groups; a command's or query's constraints; the process's stages or promises; a service's functions; a function's rules; commands, events, timers and consumed events together; a query named like a command |
| `N2` | L2 | a command, query, event, timer, consumed event or service function whose callback would be a reserved word, clash with `Kernel` or with `module_info`/`__info__`/`behaviour_info` at its arity, or take `evolve`; a command, query, event or consumed event named `state` or `row` |
| `F1` | L2 | a field named twice in one struct, or starting with `__` |
| `F2` | L2 | a malformed field type; an enum that is empty, has a member that is not an atom or `{atom, label}`, or repeats one; a domain service function without `returns`, or with a malformed return type |
| `F3` | L2 | `default:` on a field outside a `state`, including a domain value's field |
| `F4` | L2 | an `optional:` or `personal:` event field that the process's `correlate`, or the `correlate` of a process manager handling the event, names |
| `F5` | L2, L3 | `personal:` naming what is not a required, non-personal `:id` field with `subject:` in the same struct; a domain value's field naming an undeclared subject; a personal field whose type holds personal data of its own |
| `F6` | L2 | a unit's identity field declared again in its state, a command or an event |
| `F7` | L2, L3 | a process manager's state field, or a command's or query's scope field, that is `personal:` (L2) or of a domain value holding personal data (L3) |
| `A1` | L2 | a command with an empty `emits:`, or one naming an event of another unit |
| `A2` | L2 | an event no command of its unit emits and that declares no `recorded_by:` |
| `A3` | L2 | `rejects:` naming what is neither an invariant of the unit nor a constraint of the command |
| `A4` | L2 | a boundary consulting nothing; consulting an event neither local nor consumed, or one received from another application; a consult without `match:` or `where:`; `match:` on a field outside the boundary's identity, or one a local event lacks as a required, non-personal `:id` |
| `A5` | L2 | a unit or a process manager declaring `state` twice |
| `A6` | L2 | a generated identity of more than one field, or with no command that `creates:` it; `creates:` on a command whose unit's identity is not generated |
| `A7` | L2 | a command's constraint with the name of an invariant of its unit, or missing from the command's `rejects:` |
| `C1` | L2 | a command nobody can issue: no `by:`, and no policy or process manager of the contract issues it |
| `P1` | L2 | a policy or an effect handling an event neither local nor consumed; a policy issuing a command not of this contract |
| `P2` | L2 | an effect with `calls:` delivered `:in_transaction` |
| `P3` | L2 | a policy or an effect delivered `:at_least_once` without `idempotency` |
| `P4` | L2 | a process manager starting on nothing, with `correlate: []`, or `:in_transaction`; a trigger neither a local or consumed event nor (for `on`) its own timer; `sets`/`cancels` naming another timer; a timer without exactly one of `wait`/`at`, or `at` not a `:timestamp` state field; issuing a foreign command |
| `P5` | L2 | a read model projecting an event neither local nor consumed; a query reading what is not a read model of this contract |
| `R1` | L2 | a contract without exactly one `process` |
| `R2` | L2 | a process with `correlate: []`, or a local event missing a `correlate` field (the unit's identity counts) |
| `R3` | L2 | with stages declared: an event outside a stage group, a process-level `include` outside a stage, or a group naming an undeclared stage; with no stages, any stage group |
| `R4` | L2 | `include` naming a local event, an event received from another application, or one the contract does not consume |
| `R5` | L2 | a promise's `from`, `eventually` or `or_else` naming neither a local event nor an included consumed one |
| `R6` | L2 | a duration that is not `{count, unit}`, counts a negative or non-integer number, or has an unknown unit; a calendar unit in `within` or `deadline` (a timer's `wait` and `cadence` may use one); `cadence` or `deadline` declared twice |
| `K1` | L2 | a sibling `consumes` of the contract itself, naming no events, renaming an event it does not consume, giving `as:` other than `[old: :new]`, or declaring fields |
| `S1` | L2 | a scenario with no trigger or several; a trigger naming no command or query of the contract, or an event nothing handles; several handlers and no `scope:`, or a `scope:` that does not handle it; two scenarios with one description |
| `S2` | L2 | `given` outside the target's state: not the unit's own or consulted events, not a process manager's handled events, not events the query's read model projects; any `given` for a policy |
| `S3` | L2 | scenario data naming undeclared fields or of the wrong built-in type; a `given` or a trigger missing a required field (identity excepted) |
| `S4` | L2 | `rejected` naming what the command does not `rejects:` |
| `S5` | L2 | `expect` naming an event outside the command's `emits:` |
| `S6` | L2 | an outcome unfit for the target: a command without exactly one of `expect`/`rejected`; a reaction with no outcome, or issuing, setting, cancelling or ending what it does not; a query without one `answers` shaped as it returns; another kind's outcome; an effect or read model as target |
| `S7` | L2 | an `actor` outside the command's `by:`, or on a scenario whose trigger is not a command |
| `S8` | L2 | an invariant, or a command's constraint, that no `rejected` scenario (of that command, for a constraint) covers |
| `S9` | L2 | a domain service's rule without examples; an example not `{[argument, …], result}` of the function's arity, with an argument or result of the wrong built-in type or `nil` where not optional; an example given twice |
| `D1` | L2 | two subdomains, contexts, actors, subjects, values, entities or externals of one name; a term defined twice in a context; a relation declared twice; a name that is both a context and an external |
| `D2` | L2 | two translations of a term into one language, or one into the context's own |
| `D3` | L2 | a value with both or neither of a type and fields; `unit` on a value that is not numeric; an undeclared `context:`; a malformed or unknown type, or a bad enum; values in a cycle |
| `D4` | L2 | a human actor with `backed_by`; `backed_by` naming no external; an actor's `context:` the domain does not declare |
| `D5` | L2 | a relation whose roles do not fit its type (directed or symmetric); an end the domain does not declare; an external in a symmetric relation; a directed one with no context end; a context related to itself |
| `D6` | L2 | `{:id, entity}` naming an undeclared entity; an entity with an undeclared context, identified by what is not its own required, non-personal `:id` field, or with a field twice, malformed, of an undeclared subject, with `default:` or `personal:`, or holding personal data |
| `D7` | L2 | a context in a subdomain the domain does not declare |
| `D8` | L2 | a value's or entity's field `issued_by:` naming what is not an external of the domain |
| `D9` | L2 | a value invariant not snake_case, clashing with Elixir at arity 1, named `:required`/`:type`/`:generated`, or twice; no `violated_by:` or `satisfied_by:` example; an example `nil`, not of the value's type, in both lists or twice in one; a satisfying example another invariant lists as violating |
| `D10` | L2, L3 | a query without `by:`; a query scope not a same-typed read-model field and param; a command scope without `by:`, not its field or identity, optional, or a generated identity it creates; a list scope, or a value with fields; a `by:` actor not carrying the scope |
| `D11` | L2, L3 | a publication from no local event, with no fields, unknown, personal or personal-data fields, or `idempotent_on:` outside them; a name unversioned, shared, or outside the domain's `name:`; `consumes "<name>"` unversioned, without `as:`, listing events, or listing no fields |
| `D14` | L3 | two commands, queries or recorded events of one domain with the same name, and so the same capability |
| `X1` | L3 | `domain:` naming a module that is not a compiled domain, or `context:` naming none of its contexts |
| `X2` | L3 | `by:`, `recorded_by:`, `accountable` or a scenario's `actor` naming no actor of the domain, or an actor of another context |
| `X3` | L3 | a field or return type that is neither built in nor a value of the domain; `{:id, entity}` naming no entity of the domain; a `subject:` the domain does not declare |
| `X4` | L3 | `depends_on`, `calls` or a field's `issued_by` naming no external of the domain |
| `X5` | L3 | `consumes` naming what is not a compiled contract, a contract of another domain, or an event the sibling does not declare |
| `X6` | L3 | a sibling event's field that a `correlate` (on an include or a handled event) or a boundary's `match` relies on, missing there, of another type, optional or personal |
| `X7` | L3 | two processes of the system with one name, and so one event type |
| `X8` | L3 | a declaration with two implementations |
| `X9` | L3 | a scenario value or a rule example not fitting its domain type; a sibling event's scenario data with unknown fields, missing required ones (in `given` or the trigger) or ill-typed values |
| `I1` | L4 | `use` with an unknown kind, no declaration or several, or naming one that does not exist, is of another kind, or is a value without invariants; a module binding a second declaration |
| `I2` | L4 | a callback the declaration needs and the module does not define |
| `I3` | L4 | `evolve` without a clause for an event its state is kept from, and no unguarded catch-all |
| `I4` | L4 | `emit` or `issue` given anything but struct literals (a list, or a `for` without `into:`/`reduce:`); `emit` of an event the enclosing command, or outside a command any command of the unit, does not emit |
| `I5` | L4 | `reject` given no atom literal, or one the enclosing command (outside one, any command of the unit) does not `rejects:` |
| `I6` | L4 | `issue` of a command outside the `issues:` of the enclosing reaction, or outside a reaction of any |
| `I7` | L4 | a macro where its kind does not allow it: `emit` and `reject` outside a unit, `issue` outside a policy or process manager |

The longer reasons for each rule are in `docs/adr/contract-v2.md` §6, in the repository.
