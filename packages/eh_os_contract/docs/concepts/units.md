# Units that decide: aggregates, consistency boundaries and domain services

This page covers the declarations that decide (an aggregate over one stream, a dynamic consistency
boundary over a query of the log, the domain services both may call) and the module each one needs.

<!-- covers: entities contract.aggregate, contract.dcb, contract.domain_service, contract.aggregate.event.upcast; rules aggregate-without-events, emits-never-produced, event-name-with-aggregate-prefix, consults-without-match, contract-without-implementation, declaration-without-implementation, transition-without-scenario, core-command-never-refuses, core-unit-records-only -->

A **unit** is what a command is sent to. It holds the rules that must stay true, reads what it has
decided before, and answers each command with events or a refusal. The engine knows two kinds:

- an **aggregate** decides over one stream: the events that carry its identity, and nothing else;
- a **dynamic consistency boundary** (`dcb`) decides over a query of the log: its own events, and
  the events of other units it `consults`.

Otherwise both are declared with the same `identity`, `state`, `invariant`, `command` and `event`,
and both are implemented the same way. Every key is in the reference:
[`aggregate`](../dsl/contract-aggregate.md), [`dcb`](../dsl/contract-dcb.md) and
[`domain_service`](../dsl/contract-domain_service.md).

## An example

A workshop offers a number of places, and may be called off. A place on it is taken one attendee at a
time, and never more places than were offered. The workshop is an aggregate; a seat is a boundary that
reads the workshop's events and every seat taken on it; how many places are left is a domain service.

```elixir
defmodule Concepts.Units.Domain do
  use EhOsContract.Domain, name: :units_example, language: :en

  subdomain :core, "Core", type: :core
  context :workshops, "Workshops", subdomain: :core
  actor :organiser, :human, "Organiser"
end
```

```elixir
defmodule Concepts.Units.Contracts.Workshops do
  use EhOsContract.Contract,
    domain: Concepts.Units.Domain,
    context: :workshops,
    id: "units_example.workshops"

  aggregate :workshop, "Workshop" do
    identity :workshop_id

    lifecycle do
      status :open, "Open"
      status :closed, "Called off", final: true
      initial :open, on: :places_offered
      transition :open, :called_off, :closed
    end

    invariant :only_an_open_workshop, "Only an open workshop is called off"

    command :offer_places, "Offer places on a workshop",
      by: :organiser,
      emits: :places_offered do
      field :capacity, :integer
    end

    command :call_off, "Call a workshop off",
      by: :organiser,
      emits: :called_off,
      rejects: :only_an_open_workshop,
      from: :open,
      or_rejects: :only_an_open_workshop

    event :places_offered, "Places offered" do
      field :capacity, :integer
    end

    event :called_off, "Workshop called off"
  end

  dcb :seat, "Seat on a workshop" do
    identity [:workshop_id, :attendee_id]

    consults :places_offered, match: :workshop_id
    consults :seat_taken, match: :workshop_id
    consults :called_off, match: :workshop_id

    state do
      field :capacity, :integer, optional: true
      field :taken, :integer, default: 0
      field :called_off, :boolean, default: false
    end

    invariant :a_place_is_free, "A workshop never has more attendees than places"
    invariant :the_workshop_is_on, "Nobody takes a seat on a workshop called off"

    command :take_seat, "Take a seat",
      by: :organiser,
      emits: :seat_taken,
      rejects: [:a_place_is_free, :the_workshop_is_on]

    event :seat_taken, "Seat taken"
  end

  domain_service :seating, "Seating" do
    function :free_places, "Places still free on a workshop" do
      argument :capacity, :integer
      argument :taken, :integer
      returns :integer

      rule :never_below_zero, "A workshop never has fewer than no free places",
        examples: [{[1, 3], 0}, {[3, 1], 2}]
    end
  end

  scenario "an open workshop is called off" do
    given :places_offered, %{capacity: 10}
    command :call_off
    expect :called_off
  end

  scenario "a workshop called off is not called off again" do
    given :places_offered, %{capacity: 10}
    given :called_off
    command :call_off
    rejected :only_an_open_workshop
  end

  scenario "a place is free: the seat is taken" do
    given :places_offered, %{capacity: 2}
    command :take_seat, %{attendee_id: "attendee-ben"}
    expect :seat_taken
  end

  scenario "every place is taken: refused" do
    given :places_offered, %{capacity: 1}
    given :seat_taken, %{attendee_id: "attendee-anna"}
    command :take_seat, %{attendee_id: "attendee-ben"}
    rejected :a_place_is_free
  end

  scenario "the workshop is called off: refused, though a place is free" do
    given :places_offered, %{capacity: 5}
    given :called_off
    command :take_seat, %{attendee_id: "attendee-ben"}
    rejected :the_workshop_is_on
  end
end
```

## An aggregate

An aggregate is one thing with an identity that lasts (a workshop, a loan, a visit) and the rules
that hold for it alone. `identity` names the fields that tell one from another, and the library
injects them into its state, its commands and its events, so `workshop_id` is in every one of them
without being declared there. `identity :booking_id, generated: :uuid` lets the library give a new one
its identity, a UUIDv7, when a command declared `creates: true` arrives without it. Such a command is
refused when it brings an identity of its own (`{field, :generated}`), and without an idempotency key
(`{:error, :idempotency_key_required}`), since a retry would otherwise create a second unit.

- **Its commands** say who may issue them (`by:`), the events they may produce (`emits:`) and the
  rules they may refuse on (`rejects:`). A command with no `by:` must be issued by a policy or a
  process manager of the contract, or nobody could issue it ([`C1`](../contract.md#refusals-c)).
- **Its events** are what it decided. An event no command emits is a fact recorded without a
  decision, and says who records it, `recorded_by: :front_desk`; it enters through
  `EhOsContract.record/3`. An event that is neither is refused ([`A2`](../contract.md#refusals-a)).
- **Its state** is what it remembers between decisions, folded from its own events. It holds only
  what a decision reads.
- **Its invariants** are the rules every command keeps, as the business states them. A command may
  also name a rule of its own, a `constraint`, for a rule about its data alone. Every invariant and
  every constraint needs a scenario that refuses on it ([`S8`](../contract.md#refusals-s)).
- **Its lifecycle**, when it has one, names the statuses its decisions depend on, the status its
  first event starts it in, and the events that move it between them. The engine computes `status`
  from the stream and puts it into the state; a command's `from:` names the statuses it is issued in,
  and dispatch refuses it in any other, on its `or_rejects:` invariant, before the decision runs. The
  rules of the graph are in [the guide](../contract.md).
- **Not its run.** Which run its events belong to, in which stage, and which of them ends it, is a
  [process module](process.md)'s to say.

## A dynamic consistency boundary

Some rules span facts that belong to different things. "A workshop never has more attendees than
places" reads the workshop's offer and every seat taken on it, and each seat is an attendee's. An
aggregate could hold them (every seat taken on the workshop's own stream) at the price of one
stream that every attendee's decision goes through. A boundary decides over exactly the events the
rule reads instead.

A `dcb` declares what it reads with `consults`:

- `consults :seat_taken, match: :workshop_id` reads every `seat_taken` whose `workshop_id` is the
  boundary's. `match:` names fields of the boundary's identity, and every event of this contract
  consulted that way has to carry them as a required, non-personal `:id` ([`A4`](../contract.md#refusals-a)).
- `consults :enrolment_closed, where: "enrolment closed for every course"` reads every event of that
  type, whoever it is about, with the criterion in prose. Use it only when no field can say it
  (`consults-without-match`, below).

A consulted event may be one of another unit of the same contract, or one the contract `consumes`
from a sibling; one received from another application is refused ([`A4`](../contract.md#refusals-a)). A boundary has no lifecycle
and no generated identity: it spans streams, and its identity is what the command names.

At run time the boundary reads its own events carrying its identity and every event it consults, in
the log's order, folds them through `evolve/2`, and decides. The append is conditional: if anything it
read was appended in between, the decision is taken again.

**Which one.** Reach for an aggregate when the rule is about one thing and the facts it reads are
that thing's own. Reach for a boundary when the rule reads facts that belong to several things, and
narrow it with `match:` to the ones the decision is about. A boundary that reads more than it needs
conflicts with every decision that touches what it read.

## A domain service

Logic that belongs to no unit (the places left on a workshop, a price from a tariff) is a
`domain_service`: pure functions, each with its typed arguments and result, and the rules it follows,
each with examples. A decision calls it through the module the contract generates,
`Concepts.Units.Contracts.Workshops.DomainServices.Seating.free_places(3, 1)`, never the
implementation directly. That module checks the arguments against their declared types, runs the
implementation, and checks the result, and the values' invariants too; a mismatch raises, since it is a
defect in the code, never a business outcome.

Every example of a rule, `{[1, 3], 0}`, is a test: `use EhOsContract.ScenarioCase, contract:
Concepts.Units.Contracts.Workshops` calls the function with the arguments and compares the result. A
rule without examples does not compile ([`S9`](../contract.md#refusals-s)).

## The code that decides

A contract names no implementation. A module binds to one declaration with `use <Contract>,
aggregate: :name`, `dcb: :name` or `domain_service: :name`, and gets the generated behaviour, the
unit's commands, events and `State` by their short names (a boundary's consulted events too) and
`emit/1` and `reject/1`:

```elixir
defmodule Concepts.Units.Workshop do
  use Concepts.Units.Contracts.Workshops, aggregate: :workshop

  @impl true
  def offer_places(%OfferPlaces{workshop_id: id, capacity: capacity}, _state),
    do: emit(%PlacesOffered{workshop_id: id, capacity: capacity})

  @impl true
  def call_off(%CallOff{workshop_id: id}, _state), do: emit(%CalledOff{workshop_id: id})
end

defmodule Concepts.Units.Seat do
  use Concepts.Units.Contracts.Workshops, dcb: :seat

  alias Concepts.Units.Contracts.Workshops.DomainServices.Seating

  @impl true
  def take_seat(_command, %State{called_off: true}), do: reject(:the_workshop_is_on)
  def take_seat(_command, %State{capacity: nil}), do: reject(:a_place_is_free)

  def take_seat(%TakeSeat{workshop_id: workshop, attendee_id: attendee}, state) do
    if Seating.free_places(state.capacity, state.taken) == 0,
      do: reject(:a_place_is_free),
      else: emit(%SeatTaken{workshop_id: workshop, attendee_id: attendee})
  end

  @impl true
  def evolve(state, %PlacesOffered{capacity: capacity}), do: %{state | capacity: capacity}
  def evolve(state, %SeatTaken{}), do: %{state | taken: state.taken + 1}
  def evolve(state, %CalledOff{}), do: %{state | called_off: true}
end

defmodule Concepts.Units.SeatingRules do
  use Concepts.Units.Contracts.Workshops, domain_service: :seating

  @impl true
  def free_places(capacity, taken), do: max(capacity - taken, 0)
end
```

- **One callback per command**, `(command, state)`, answering with `emit/1`: the literal structs of
  events the command `emits:`, or `reject/1` with an invariant or constraint it `rejects:`. The
  workshop's `call_off` needs no refusal of its own: dispatch refuses it outside `:open` before it
  runs.
- **`evolve/2`** folds each event into the state, only when the unit declares a state beyond its
  identity. It runs over every event the stream will ever hold, so it only folds: no decision, no
  raise on data. Keep a catch-all, when one is needed, exactly `def evolve(state, _), do: state`, so
  dispatch reads and decodes only the events the other clauses name.
- **The decision is pure.** It reads the command, its `__meta__` (the actor, `occurred_at`), the
  state and the domain services, and nothing else: on a conflict dispatch decides again, up to three
  times, and a scenario gives a decision only events and a command.
- **A refusal is a business answer; anything else is a defect.** `reject/1` makes `{:error,
  %EhOsContract.Rejection{}}` naming the rule, writes a `rejected` row and appends nothing. An
  exception, an event outside `emits:` or an event whose fields do not fit raises, and nothing is
  appended.

The engine finds implementations in the running binary of the applications it is configured with,
and each declaration takes at most one ([`X8`](../contract.md#refusals-x)). A unit whose events are all `recorded_by:` and whose
state is only its identity needs no module.

## An event that already has rows

The log keeps every event as it was written, and the engine reads each one again with today's
declaration: to fold a unit's state, to feed a reaction, to publish it. So an event that has rows
changes only with a new version of its fields, `schema_version`, and a step, `upcast`, that says how
a row of the version before reads in the new one. The rows themselves never change.

```elixir
event :demand_opened, "Demand opened", schema_version: 2 do
  field :demand_reason, :demand_reason
  field :priority, :string

  upcast from: 1, rename: [reason: :demand_reason], default: [priority: "normal"]
end
```

A row written at version 1 is read with `reason` under its new name, `demand_reason`, and with
`priority` as `"normal"`; a row of version 2 is read as it is. Version 3 adds `upcast from: 2`, and a
row of version 1 goes through both steps in turn.

- **`rename:`** moves a field of the older version to its name in the next. A personal field may be
  renamed: the engine opens its sealed value under the name it was sealed with.
- **`default:`** gives a value to a field the older version did not have, written as the log stores
  one (an enum's member as its name, a date as text). A row that holds the field keeps its own.
  A rename onto a name an old row already holds replaces that row's own value: say both, or neither.
- **A step with neither** says the fields kept their shape: a version raised for their meaning alone.
- **`function:`** names a function of the unit's implementation, for a change a rename and a default
  cannot say: amounts stored in grosze read as a decimal, one field split in two. It is a step on its
  own.

```elixir
event :fee_charged, "Fee charged", schema_version: 2 do
  field :amount, :decimal

  upcast from: 1, function: :amount_from_minor
end
```

```elixir
@impl true
def amount_from_minor(%{"amount_minor" => minor} = data),
  do: data |> Map.delete("amount_minor") |> Map.put("amount", Decimal.div(minor, 100))
```

The function takes the row's payload at that version as the log stores it, with string keys, and
gives the next version's; what it gives is read as the log stores a value, so a decimal, a date or an
atom key reads as an old row's own would. The implementation does not compile without it
([`I2`](../contract.md#refusals-i)), and it is pure: it reads nothing but the row. The engine cannot
see what it did, so it refuses the row, naming the step and never a value, when the function:

- moved a sealed personal value, made one, or reordered a list holding one: a seal opens only under
  the field it was sealed in, so a personal field is renamed with `rename:`, and its value, which the
  function sees sealed, cannot be converted at all;
- left a field the log tags rows with other than the row was written with, a new required `:id`
  among them: that change is a new event;
- raised, threw, exited, or gave no map.

A step covers what it can say in words. What the log keeps beside a row's payload by a field's name
cannot be carried across: the unit's identity, and every field the log tags each row with — a
required, non-personal `:id`, date or timestamp, by which a boundary, a process and the report find
rows. A change to one of those is a new event. The compiler refuses a version without its step, a step
to a field the event will not have, a step that renames onto or defaults a field the log keeps, a
default for personal data, and a default that is not a value of its field
([`U1`](../contract.md#refusals-u)–[`U4`](../contract.md#refusals-u)).

A compile sees only today's declaration, so it cannot tell a field added to version 1 from version 1
as it always was. `mix eh_os_contract.schema` keeps that record: `eh_os_contract.lock`, beside
`mix.lock`, holds the fields of every event by its type in the log and its version, as a row holds
them. A change old rows still read is recorded in place: a field added as optional, a field removed, a
required field made optional, an enum given members, an `:integer` made a `:decimal`, an `:id` made a
`:string`, and the same inside a list or a domain value. A field removed stays in the file, marked
`removed: true`, since old rows still hold it and rows written since do not: a field declared again
under its name is held to what both hold. `--check` fails when a recorded version changed otherwise,
when the steps from a recorded version to the declared one do not cover what changed, when the file
records a version newer than the declared one or an event no contract declares any more, or when the
file is behind the contracts:

```
** (Mix) eh_os_contract.lock and the contracts disagree:

  * shop.orders.order_placed at schema_version 1: courier was added, [type: :string], and is
    required: give it a `default:`, or make it optional. A row written at version 1 holds the fields
    the lock records, and would not read: raise its schema_version with a step `upcast from: 1` that
    covers the change, or, if no log holds rows of it, run
    `mix eh_os_contract.schema --forget shop.orders.order_placed`
```

Run it beside `mix eh_os_contract.check`, and commit the file: a new version shows in a pull request
as the fields it records. A field's type there is what the log stores, so a domain value given another
field changes every event that holds it, while renaming the value, relabelling a field or reordering
the fields changes nothing.

A raised version's steps are held to what changed from every earlier version the file records, each
read as the declared one through the steps between them, as the engine reads an old row: `rename:`
carries a field to its new name, `default:` gives a new required field its value where an old row
lacks it, and a step by a function covers every change a step could carry. A field renamed without
`rename:`, a required field added without a default, a field that was optional made required (old rows
hold an explicit `nil`, which a default does not fill), or a type changed otherwise than above, with no
step a function, is refused, naming the field and the steps. Some changes are refused even with a
step, since rows already written keep what they were written with:

- a field that becomes personal, stops being, or is sealed by another identifier;
- a personal field whose type changes, or a value holding personal data whose shape changes, since a
  sealed value cannot be converted or its seal moved;
- a personal field made required where old rows may lack it, since a default would be clear text and
  a function makes no seal;
- an identifier that seals a field given another `subject:`;
- a field the log tags rows with that the version before did not tag under that name.

Each is a new event. `--forget TYPE` drops the event's versions from the declared one up, or every
version of an event no contract declares, and records what is declared: it is for versions no log
holds rows of, as one added on a branch never deployed.

## What the compiler refuses

The full table is in [the guide](../contract.md). The refusals a unit meets most:

- a command whose `emits:` is empty or names another unit's event ([`A1`](../contract.md#refusals-a)), or an event nothing emits
  and nobody records ([`A2`](../contract.md#refusals-a)): declare who decides or records it;
- `rejects:` naming neither an invariant of the unit nor a constraint of the command ([`A3`](../contract.md#refusals-a));
- a boundary that consults nothing, consults an event it cannot read, or consults without `match:` or
  `where:` ([`A4`](../contract.md#refusals-a));
- an invariant or constraint with no scenario that refuses on it ([`S8`](../contract.md#refusals-s)): the scenario is the case to
  ask the process owner for;
- a lifecycle whose graph does not hold ([`T1`](../contract.md#refusals-t)–[`T4`](../contract.md#refusals-t));
- an event above version 1 without a step from each version below it ([`U1`](../contract.md#refusals-u));
- in the module: a missing callback ([`I2`](../contract.md#refusals-i)), `evolve/2` without a clause for an event the state is
  kept from ([`I3`](../contract.md#refusals-i)), `emit/1` of anything but the literal events the command emits ([`I4`](../contract.md#refusals-i)), `reject/1`
  of a rule it does not reject on ([`I5`](../contract.md#refusals-i)).

## What `mix eh_os_contract.check` reports

From [its rules](../rules.md):

- `aggregate-without-events` (warning): a unit declares no event, so it has no command either and
  decides nothing. Declare what it decides, or remove it.
- `event-name-with-aggregate-prefix` (warning): `workshop_offered` in the unit `workshop` says the unit
  twice. Name what happened: `places_offered`.
- `consults-without-match` (warning): a boundary consults an event by `where:` alone, so it reads
  every event of that type, and under load most decisions are retried or refused with `:conflict`.
  Name the identity fields that narrow it.
- `transition-without-scenario` (warning): no scenario takes a transition of the lifecycle. Add a
  scenario of a command whose `given` leaves the unit in the transition's `from` status and which
  expects the event, as "an open workshop is called off" does above.
- `emits-never-produced` (warning): a command may emit an event no `emit/1` of its module names.
  Either narrow `emits:` to what the code decides, or decide the event with `emit/1`.
- `declaration-without-implementation` (warning): some declarations of a contract have modules and
  this one has none, so dispatch refuses to run it. Add the module.
- `contract-without-implementation` (notice): nothing implements the contract at all. Legal (a
  contract may be written before its code) but nothing of it can be dispatched yet.
- `core-unit-records-only` (warning): the unit's context belongs to a subdomain of `type: :core`, it has
  events, and no command of the unit can be refused: none has `rejects:`, or it has no commands and its
  events are only `recorded_by:`. The core is where the business decides; a unit that only records keeps a log.
  Its page says "Records only", in any context, so a reader sees which units decide nothing.
- `core-command-never-refuses` (notice): a command of a core context rejects nothing, so no rule of
  its unit refuses a request; only its fields' types and values can. A command only a policy or a
  process manager issues, with no `by:`, is left out, since it follows from an event already decided. Either the command has a rule not declared yet, or it records a
  fact, which an event `recorded_by:` an actor says more plainly; some core commands legitimately
  always succeed.
