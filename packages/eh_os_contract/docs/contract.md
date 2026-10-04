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
description, is in the generated reference: [the domain](dsl/domain-dsl.md) and [the contract](dsl/contract-dsl.md).
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
`lending.<actor>`, and every name its contracts publish begins with `lending.`. So it is one segment of a
namespace — lowercase letters, digits, `_` and `-`, starting with a letter and not ending with a dash, like
`:"my-shop"` — and a domain named otherwise does not compile (`D11`). `language:` is the language the labels
are written in — labels are the words of the people in the process, in their language, and the engine prints
them as written.

An actor may name what it answers for, `responsibility :overdue_reports, "…", source: "P-25"`, prose a page
shows and nothing runs. A relation between contexts may pair the words each side uses for the same thing,
`terms: [{"Visit", "Encounter"}]`, the first end's word and the second's, each a term of its context's
glossary; the glossary shows, under a term, what the other end calls it.

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
- **An aggregate may declare its lifecycle**: the statuses its decisions depend on, in the client's words,
  the `initial` one each first event starts it in, and the `transition`s events make between them —
  `transition :booked, :patient_arrived, :in_progress`. A transition names an event type and nothing about
  its fields, so the graph is checked as it compiles: every status reached, only a `terminal:` one final.
  A command may name the statuses it is issued in, `from: :booked`, with the invariant it is refused on in
  any other, `or_rejects: :only_a_booked_visit`. **The engine computes the status** from the names of the
  stream's events and puts it into the state as `status`, which `evolve/2` reads and never sets. Dispatch
  refuses a command outside its `from:` before the decision; an event the decision emits that the graph does
  not allow from where the aggregate stands raises, as one outside `emits:` does, and nothing is appended.
  An event no transition names is allowed in every status that is not terminal, once an initial event has
  started the aggregate; a recorded event that does not fit is appended and moves nothing. A boundary has no
  lifecycle: it spans streams.
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

- **The implementation reads the contract where it is written.** Each callback of a generated behaviour
  carries what the contract says of it: the declaration's label and source, what it may emit or issue,
  the rules that hold there — each with the scenario that refuses on it or illustrates it, or marked
  prose alone — and its scenarios. `b Lending.Contracts.Loans.Aggregates.Loan.open_loan` in IEx prints it.

What reacts to events is declared beside the units: a `policy` issues a command of this contract, an
`effect` calls an external system — naming one of its `operation`s, `calls: {:p1, :submit_report}`, when
the domain says what the system does — a `process_manager` steers a run with its own state and timers, and a
`read_model` projects rows that a `query` reads. A reaction names its rules as a command does, with
`constraint`, and a process manager its `invariant`s too; a scenario that names one in `illustrates:`
is the test that it holds, and `mix eh_os_contract.check` warns of one no scenario illustrates. An
effect's constraint stays prose, since no scenario runs an effect. A process manager's scenario may also
say the `state` its run holds after the trigger — `state %{check_at: "2026-02-01T00:00:00Z"}` — which
`ScenarioCase` compares after folding the delivered event, as the engine does. A reaction delivered
`:at_least_once` names what makes a second delivery harmless and who keeps it so, `idempotency: [key:
:event_id, owner: :downstream]`: its own code (`:self`), the system an effect calls, given the key
(`:downstream`), or the engine (`:infrastructure`), which keys the commands a policy issues. `consumes` takes a sibling contract's events, and
`publish` lets one leave the application: its relay (`EhOsContract.Relay`) hands it to the configured
`EhOsContract.Bus`, from the first deploy of the `publish` on.

If `Loans` publishes its loans — `publish :loan_opened, as: "lending.loan.opened.v1", from: :loan_opened,
fields: [:loan_id, :copy_id], idempotent_on: [:loan_id]` — a contract of **another application**, a
reservations service say, takes the event by that name, with the fields it reads:

```elixir
consumes "lending.loan.opened.v1", as: :copy_lent do
  field :loan_id, :id
  field :copy_id, :id
end

policy :release_hold, "Release the hold on a lent copy", handles: :copy_lent, issues: :release_hold
```

The event never enters the subscriber's log: it arrives in an inbox (`EhOsContract.Inbox`), which commits its
row with what the policy dispatched and only then acknowledges. Since a read model, an effect and a process
manager read the log, **only a policy takes it** (`D12`); they react to what the policy's command records
instead. A second delivery finds the inbox row and is dropped, and so does the same fact published again
under a new id when the publisher declares `idempotent_on:`, whose values make the message's key. The
subscriber asks for the capability `lending.loan.opened.subscribe`, the application's, which EHOS grants
and the transport delivers by.

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
| `N1` | L2 | a name not snake_case; a name twice among: declarations of one kind; a unit's invariants or stage groups; a command's, query's, policy's or effect's constraints; a process manager's constraints and invariants together; the process's stages or promises; a service's functions; a function's rules; commands, events, timers and consumed events together; a query named like a command; two names that camelize alike among units, reactions, read models, queries or services of one kind, or among commands, events and consumed events |
| `N2` | L2 | a command, query, event, timer, consumed event or service function whose callback would be a reserved word, clash with `Kernel` or with `module_info`/`__info__`/`behaviour_info` at its arity, or take `evolve`; a command, query, event or consumed event named `state` or `row` |
| `F1` | L2 | a field named twice in one struct, starting with `__`, or otherwise not snake_case |
| `F2` | L2 | a malformed field type; an enum that is empty, has a member that is not an atom or `{atom, label}`, or repeats one; a domain service function without `returns`, or with a malformed return type |
| `F3` | L2 | `default:` on a field outside a `state`, including a domain value's field |
| `F4` | L2 | an `optional:` or `personal:` event field that the process's `correlate`, or the `correlate` of a process manager handling the event, names |
| `F5` | L2, L3 | `personal:` naming what is not a required, non-personal `:id` field with `subject:` in the same struct; a domain value's field naming an undeclared subject; a personal field whose type holds personal data of its own |
| `F6` | L2 | a unit's identity field declared again in its state, a command or an event |
| `F7` | L2, L3 | a process manager's state field, or a command's or query's scope field, that is `personal:` (L2) or of a domain value holding personal data (L3) |
| `F8` | L2, L3 | a field a run or a process manager's record is told by — an event's field a `correlate` names, a process manager's state field its `correlate` names, or the first local event's field an undeclared one takes its type from — that is not an `:id`, `{:id, entity}` or a domain value resting on `:id` (L3) |
| `F9` | L2 | a unit's identity, a process's `correlate` or a process manager's `correlate` of more than six fields |
| `A1` | L2 | a command with an empty `emits:`, or one naming an event of another unit |
| `A2` | L2 | an event no command of its unit emits and that declares no `recorded_by:` |
| `A3` | L2 | `rejects:` naming what is neither an invariant of the unit nor a constraint of the command |
| `A4` | L2 | a boundary consulting nothing; consulting an event neither local nor consumed, or one received from another application; a consult without `match:` or `where:`; `match:` on a field outside the boundary's identity, or one a local event lacks as a required, non-personal `:id` |
| `A5` | L2 | a unit or a process manager declaring `state` twice |
| `A6` | L2 | a generated identity of more than one field, or with no command that `creates:` it; `creates:` on a command whose unit's identity is not generated |
| `A7` | L2 | a command's constraint with the name of an invariant of its unit, or missing from the command's `rejects:` |
| `T1` | L2 | an aggregate declaring `lifecycle` twice; a lifecycle without a status or an `initial`; a status named twice or not snake_case |
| `T2` | L2 | a `transition` leaving no status; `initial` or `transition` naming a status the lifecycle does not declare or an event not of the aggregate; one event starting the aggregate in two statuses; one status and one event moving it twice |
| `T3` | L2 | a status no `initial` reaches; a `terminal:` status a transition leaves; a status that is not terminal with no transition out |
| `T4` | L2 | `from:` without `or_rejects:` or the other way round; `from:` naming an undeclared or terminal status, on an aggregate without a lifecycle, or on a command that `creates:` its aggregate; a command that `creates:` its aggregate and emits none of its initial events; `or_rejects:` naming what is not an invariant of the unit, or missing from `rejects:`; an emitted event no transition moves out of a status in `from:`; a status in `from:` none of the command's events leaves, when `rejects:` names no rule but `or_rejects:` |
| `C1` | L2 | a command nobody can issue: no `by:`, and no policy or process manager of the contract issues it |
| `P1` | L2 | a policy or an effect handling an event neither local nor consumed; a policy issuing a command not of this contract |
| `P2` | L2 | an effect with `calls:` delivered `:in_transaction` |
| `P3` | L2 | a policy or an effect delivered `:at_least_once` without `idempotency`; an `idempotency` owned `:downstream` outside an effect, owned `:infrastructure` by an effect or on a key other than `:event_id` |
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
| `S6` | L2 | an outcome unfit for the target: a command without exactly one of `expect`/`rejected`; a reaction with no outcome, or issuing, setting, cancelling or ending what it does not; a `state` said twice, or of anything but a process manager; a query without one `answers` shaped as it returns; another kind's outcome; an effect or read model as target |
| `S7` | L2 | an `actor` outside the command's `by:`, or on a scenario whose trigger is not a command |
| `S8` | L2 | an invariant, or a command's constraint, that no `rejected` scenario (of that command, for a constraint) covers |
| `S9` | L2 | a domain service's rule without examples; an example not `{[argument, …], result}` of the function's arity, with an argument or result of the wrong built-in type or `nil` where not optional; an example given twice |
| `S10` | L2 | `illustrates:` naming what is not a constraint of the scenario's policy, process manager or query, nor an invariant of its process manager, or naming one twice; any `illustrates:` on a command's scenario, which shows its rules with `rejected` |
| `D1` | L2 | a subdomain's, context's, subject's, value's, entity's or external's name not snake_case; two values that camelize alike; a value named after a type Elixir builds in or a built-in field type; two subdomains, contexts, actors, subjects, values, entities or externals of one name; an external's operation or an actor's responsibility not snake_case or declared twice; a term defined twice in a context; a relation declared twice; a name that is both a context and an external |
| `D2` | L2 | two translations of a term into one language, or one into the context's own |
| `D3` | L2 | a value with both or neither of a type and fields; `unit` on a value that is not numeric; an undeclared `context:`; a malformed or unknown type, or a bad enum; values in a cycle; a value's field not snake_case, or named twice |
| `D4` | L2 | an actor's name not snake_case; a human actor with `backed_by`; `backed_by` naming no external; an actor's `context:` the domain does not declare |
| `D5` | L2 | a relation whose roles do not fit its type (directed or symmetric); an end the domain does not declare; an external in a symmetric relation; a directed one with no context end; a context related to itself; a word of a relation's `terms` pair that its context's glossary does not define |
| `D6` | L2 | `{:id, entity}` naming an undeclared entity; an entity with an undeclared context, identified by what is not its own required, non-personal `:id` field, or with a field twice, not snake_case, malformed, of an undeclared subject, with `default:` or `personal:`, or holding personal data |
| `D7` | L2 | a context in a subdomain the domain does not declare |
| `D8` | L2 | a value's or entity's field `issued_by:` naming what is not an external of the domain |
| `D9` | L2 | a value invariant not snake_case, clashing with Elixir at arity 1, named `:required`/`:type`/`:generated`, or twice; no `violated_by:` or `satisfied_by:` example; an example `nil`, not of the value's type, in both lists or twice in one; a satisfying example another invariant lists as violating |
| `D10` | L2, L3 | a query without `by:`; a query scope not a same-typed read-model field and param; a command scope without `by:`, not its field or identity, optional, or a generated identity it creates; a list scope, or a value with fields; a `by:` actor not carrying the scope |
| `D11` | L2, L3 | a domain's `name:` that is not one lowercase segment of letters, digits, `_` and `-`, starting with a letter and not ending with a dash; a publication from no local event, with no fields, unknown, personal or personal-data fields, or `idempotent_on:` outside them; a name unversioned, shared, or outside the domain's `name:`; `consumes "<name>"` unversioned, without `as:`, listing events, or listing no fields |
| `D12` | L2 | a read model, an effect or a process manager taking an event received from another application, which only a policy takes, in its inbox |
| `D14` | L3 | two commands, queries or recorded events of one domain with the same name, and so the same capability |
| `X1` | L3 | `domain:` naming a module that is not a compiled domain, or `context:` naming none of its contexts |
| `X2` | L3 | `by:`, `recorded_by:`, `accountable` or a scenario's `actor` naming no actor of the domain, or an actor of another context |
| `X3` | L3 | a field or return type that is neither built in nor a value of the domain; `{:id, entity}` naming no entity of the domain; a `subject:` the domain does not declare |
| `X4` | L3 | `depends_on`, `calls` or a field's `issued_by` naming no external of the domain; a call naming an operation its external does not declare, or naming none of an external that declares some |
| `X5` | L3 | `consumes` naming what is not a compiled contract, a contract of another domain, or an event the sibling does not declare |
| `X6` | L3 | a sibling event's field that a `correlate` (on an include or a handled event) or a boundary's `match` relies on, missing there, of another type (an `:id` where no local event types it), optional or personal |
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
