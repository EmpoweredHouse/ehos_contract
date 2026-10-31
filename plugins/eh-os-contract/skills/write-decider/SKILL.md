---
name: write-decider
description: Before writing the module that implements an aggregate or a dynamic consistency boundary of a contract (`use <Contract>, aggregate:` or `dcb:`) — the callback per command that decides with `emit/1` and `reject/1`, and the `evolve/2` that folds the stream — keep the decision pure and replayable, tell a business refusal from a defect, and make `evolve/2` survive every event history will ever hold. Use once the unit, its commands, events and invariants are declared in the contract; not for declaring them (see `add-event`, or `change-contract` for a unit that has history), and not for what reacts to the events it decides (see `write-reaction`).
---

# Writing the code that decides

Checked on 30 September 2026 (plan E11e) against
`packages/eh_os_contract/docs/contract.md`, the generated reference in `packages/eh_os_contract/docs/dsl/`,
and the engine's source (`EhOsContract.Dispatcher`, `EhOsContract.Contract.Callbacks`,
`EhOsContract.Implementation`). Not yet run on a real change: read what it says against those
before trusting it.

**In an application.** This skill is also the `eh-os-contract` Claude Code plugin's, which an
application built on EHOS enables. There, the engine's paths below are under `deps/eh_os_contract/`,
at the version the application pins: `packages/eh_os_contract/docs/contract.md` is
`deps/eh_os_contract/packages/eh_os_contract/docs/contract.md`. `CLAUDE.md`, `docs/` and `sandbox/`
are eh-os-contract's, on [GitHub](https://github.com/EmpoweredHouse/eh-os-contract): where
a step names `sandbox/lib/…`, read the application's own `lib/<app>/`, and where it runs the gate
from `sandbox/`, run the application's `mix precommit`.

## Where this sits

`module-boundary-check` decided that the action is a command to a unit. The contract already
declares the unit (`aggregate` over one stream, `dcb` over the events it `consults`), its `state`,
its invariants and constraints, its commands with `emits:` and `rejects:`, and its events. This
skill writes the module that binds to the unit. It does not change the declaration: when the code
wants an event the command does not `emits:`, or a refusal it does not `rejects:`, that is a change
to the contract, and `change-contract` comes first if the unit already has history.

## What binds, and what the compiler already checks

An excerpt of `Lending.Circulation.Loan`, in the sandbox's invented lending case, with a catch-all
`evolve/2` clause the real module does not need — the module has a callback for every command of the
unit:

```elixir
defmodule Lending.Circulation.Loan do
  use Lending.Contracts.Circulation, aggregate: :loan

  @impl true
  def return_copy(_command, %State{lent: false}), do: reject(:only_a_copy_out_comes_back)
  def return_copy(_command, %State{returned: true}), do: reject(:only_a_copy_out_comes_back)

  def return_copy(%ReturnCopy{loan_id: id, late_fee: 0}, _state),
    do: emit(%CopyReturned{loan_id: id})

  def return_copy(%ReturnCopy{loan_id: id, late_fee: fee}, _state),
    do: emit([%CopyReturned{loan_id: id}, %LateFeeCharged{loan_id: id, fee: fee}])

  @impl true
  def evolve(state, %CopyLent{}), do: %{state | lent: true}
  def evolve(state, %CopyReturned{}), do: %{state | returned: true}
  def evolve(state, %LateFeeCharged{}), do: %{state | fee_owed: true}
  def evolve(state, _changes_nothing), do: state
end
```

`late_fee` is declared `supplied_by: :host` in the contract: the desk's tariff gives it, and a caller
that sends one is refused, so the decision can charge it without trusting the caller.

The `use` gives the module the behaviour the contract generated (`C.Aggregates.<Name>` or
`C.Dcbs.<Name>`), the commands, events and `State` by their short names, and `emit/1` and
`reject/1`. One callback per command, `(command, state) :: {:ok, [event]} | {:error,
%EhOsContract.Rejection{}}`. `evolve/2` only when the state declares more than the unit's
identity.

Everything below is refused at compile time, with its code (`packages/eh_os_contract/docs/refusals.md`; an engine
released before that page has the list in `packages/eh_os_contract/docs/contract.md`, "What will not compile"), so do not spend attention on
it:

- `I1` — the `use` names no declaration, the wrong kind, or a second one for the same module;
- `I2` — a command's callback is missing, or the function an event's `upcast from: n, function:
  :name` names (the error shows the clause to add);
- `I3` — `evolve/2` has no clause for an event its state is kept from, and no catch-all;
- `I4` — `emit/1` given something other than a struct literal, a list of them, or a `for` producing
  them (one event per item of the data is `emit(for item <- items, do: %Event{...})`; a `for` with
  `into:` or `reduce:` is refused), or an event the enclosing command does not emit (outside a
  command callback, one no command of the unit emits);
- `I5` — `reject/1` given anything but an atom literal the command `rejects:`;
- `I7` — `issue/1` in a unit;
- `X8` — two modules implementing one unit.

`mix eh_os_contract.check` adds `emits-never-produced` (`packages/eh_os_contract/docs/rules.md`): the contract lets a command
emit an event no `emit/1` of the module names. Either the declaration is wider than the decision,
or the event is returned around `emit/1`. Both are worth a look, and neither fails the gate.

## The part no check expresses: the decision is pure

A decision may read four things: the command, including its `__meta__` (actor, `occurred_at`,
correlation); the state `evolve/2` folded from the stream, and for a boundary also from what it
consults; a domain service's function (`C.DomainServices.<Name>`, which holds its arguments and
result to their types); and constants. **Nothing else**: no `Repo`, no HTTP, no
`DateTime.utc_now/0`, no process dictionary, no ETS. The reasons are mechanical, not stylistic:

- **Dispatch may decide more than once.** On a stream or boundary conflict it rolls back, reads
  again and decides again, up to three times (`EhOsContract.dispatch/3`, "Conflicts"). A side
  effect in a decision happens up to three times and is never rolled back with the append.
- **A scenario is the decision's test**, and it gives only events and a command
  (`EhOsContract.ScenarioCase`). A decision that reads the database is not what its scenarios test.
- **The log is the truth.** A decision that depends on a table outside the log decides differently
  on replay, and nothing records why.

When the decision seems to need something outside those four, it is one of these, and the fix is in
the model, not in the module:

| What the decision wants | Where it belongs |
| --- | --- |
| Something the unit learned earlier | a field of `state`, folded from the event that taught it |
| Another unit's events, under one consistency rule | a `dcb` that `consults` them, narrowed with `match:` |
| An external system's answer | an `effect` that asks, and records the answer as an event with `EhOsContract.record/3` (see `write-reaction`) |
| The current time | `command.__meta__.occurred_at`, set by dispatch |
| A value the caller looked up | a field of the command; the caller answers for it |

## Refusal or defect

- `reject(:name)` is a business "no": an invariant of the unit or a constraint of the command,
  named in its `rejects:`. Dispatch writes a `rejected` row, appends nothing, and the caller gets
  `{:error, %EhOsContract.Rejection{}}` naming the invariant and nothing else — no details, since a
  rejection travels to logs and callers.
- Anything else that goes wrong is a defect: an exception, an event outside `emits:`, an event whose
  fields do not fit their types or their values' invariants. Dispatch raises, appends nothing, and
  writes a `failed` row naming the decider. Do not catch it to turn it into a rejection, and do not
  return `{:error, reason}` of your own: only `reject/1` makes a rejection.
- Data that breaks an invariant of a domain value one of the command's fields holds — its unit's key
  too, when the identity is typed by a value — never reaches the decider: dispatch refuses it first,
  `{:error, {:invalid, [{field, {:invariant, name}}]}}`, and writes no row. Do not check it again in
  the callback. Show it with a scenario `rejected` on the value's invariant (`S4`), such as a period
  that is no month refused on `:named_by_month`; it counts toward no invariant of the unit (`S8`).
- A refusal the contract has no name for is a missing invariant or constraint. Declaring one needs a
  `rejected` scenario that shows it (`S8`), and that scenario is the case to ask the process owner
  for.

## `evolve/2` folds history for ever

The state is rebuilt from the stream on every command. So `evolve/2` runs over every event the
stream will ever hold, written under every version of the code:

- **It only folds.** No decision, no validation, no raising on data: a raise there fails every later
  command on that stream (`failed` in `evolve`), and there is no event to fix it with.
- **A personal field may read back as `%EhOsContract.Erased{}`** once its subject is erased
  (`docs/adr/contract-v2.md` §14).
  Fold it without matching on the value, or keep personal data out of the state altogether.
- **A catch-all satisfies `I3` and hides the event you forgot.** Write the clauses that change state
  explicitly, and name the catch-all for what it lets through, as `_changes_nothing` above.
- **Keep the catch-all exactly `def evolve(state, _), do: state`.** Then dispatch reads and decodes only
  the events the other clauses name, and a boundary conflicts only on them. Any other catch-all, or a
  guard on the event, makes it read everything the unit could see — for a boundary over a month's
  bank statements, every statement of the month on every match.
- Time for the state comes from the event, `event.__meta__.occurred_at`: a `returned_on` folded
  from `CopyReturned`, never `Date.utc_today/0`.

## A boundary (`dcb`)

The same callbacks, over a query instead of a stream: its own events carrying its identity, and
every event it `consults`, folded in the log's order. Two things differ:

- The append is conditional on nothing it read having been appended since, so a busy boundary
  conflicts more often and decides again more often — one more reason for purity.
- A `consults … where: "…"` with no `match:` reads every event of that type
  (`consults-without-match`): under load most decisions are retried or refused with `:conflict`.
  Narrowing it is a contract change, not something the module can do.

## Procedure

1. Read the unit's declaration: its `state`, every command's `emits:` and `rejects:`, the
   invariants' labels and their `rejected` scenarios. The scenarios are the specification the
   callbacks are written against. The generated behaviour says the same per callback (plan EP3):
   `b <Contract>.Aggregates.<Name>.<command>` in IEx prints the command's label and source, what it emits,
   every rule it refuses on with the scenario that refuses on it, and its scenarios. Write from the
   named rules, not from the label: a rule is a clause, and its scenario is the test of that clause.
2. Write `use <Contract>, aggregate: :name` (or `dcb:`), and compile: `I2` lists every callback to
   add.
3. Write each callback as clauses, one per outcome: the refusals first, each on the state that makes
   it, then the emit. Branch to different `emit/1` literals rather than computing the list of events
   (`I4`). A field holding a value made of fields takes its struct, `%Billing.Domain.Values.UsageRecord{…}`,
   or the command's own, passed on: a map with its keys is not the value, and the event raises as a
   defect.
4. Write `evolve/2` for every event that changes the state, and a named catch-all for the rest.
   Write each function an event's `upcast … function:` names — a unit that only records needs a
   module for it too, with nothing else in it: it takes an old row's
   payload as the log stores it, a map with string keys, and gives the next version's. Keep it pure,
   and leave every sealed value (`%{"$eh" => …}`) where it is, every field the log tags rows with as
   it is, every list holding personal data in its order, and no personal field in the clear: a row
   that breaks one is refused when it is read, and with it every decision folding that stream.
5. Put `use EhOsContract.ScenarioCase, contract: <Contract>` in a test module, if the contract has
   none, and run it. Every scenario of the unit is a test of this module.
6. Put the module under the context that owns it, as its siblings are, never reaching another
   context's tables. Where the project compiles with `boundary`, that place is its context module's
   `use Boundary` (`sandbox/lib/lending/circulation.ex`); where it does not, as in an application
   `ehos_app` generates, there is no `use Boundary` to add (`module-boundary-check`).
7. Run the gate from `sandbox/` (`CLAUDE.md`, "The gate") and read any new `emits-never-produced` line.
8. If a clause encodes an assumption nobody stated — a partial payment refused rather than modelled
   — say so in the moduledoc. That clause is where the
   reviewer's attention goes. A rule the contract names is not restated there: the contract says it,
   and the generated docs carry it to the callback. Restated, it drifts from the contract.

## Not this skill

Declaring the unit, a command, an event or an invariant — `add-event`, or `change-contract` when
the unit already has history. What reacts to the events it decides — `write-reaction`. Whether the
action should be a command at all — `module-boundary-check`.
