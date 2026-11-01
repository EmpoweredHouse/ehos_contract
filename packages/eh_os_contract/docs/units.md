# What are the units that decide?

<!-- covers: entities contract.aggregate, contract.dcb, contract.domain_service; rules aggregate-without-events, event-name-with-aggregate-prefix, consults-without-match, core-command-never-refuses, core-unit-records-only -->

This page tells what an aggregate, a dynamic consistency boundary and a domain service are, and
how the engine decides with them. It is for a developer who declares them in a contract, and for a
person who reads the rules of a business in a contract. [The glossary](glossary.md) defines each
word in italics.

## What is a unit?

A *unit* is the thing that a command goes to. It keeps the rules of the business that must stay
true. It reads the events that it decided before. It answers each command with events or with a
refusal.

The engine has two kinds of unit:

- An *aggregate* decides over one *stream*: the events that carry its identity, and no other
  events.
- A *dynamic consistency boundary* (`dcb`) decides over a query of the log: its own events, and the
  events of other units that it consults.

The two kinds have the same declarations: `identity`, `state`, `invariant`, `command` and `event`.
You write the code of both in the same way. [Write the code that decides](deciding.md) tells how.

A *domain service* is logic that belongs to no unit. A unit calls it while it decides.

The references list each key: [`aggregate`](dsl/contract-aggregate.md),
[`dcb`](dsl/contract-dcb.md) and [`domain_service`](dsl/contract-domain_service.md).

## An example

A workshop offers a number of places. An organiser can call the workshop off. Each attendee takes
one seat. A workshop never has more attendees than places.

- The workshop is an aggregate.
- A seat is a dynamic consistency boundary. It reads the events of the workshop, and each seat that
  an attendee took on it.
- The number of free places is a domain service.

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

    invariant :only_an_open_workshop, "Only an open workshop is changed"

    command :offer_places, "Offer places on a workshop",
      by: :organiser,
      emits: :places_offered do
      field :capacity, :integer
    end

    command :invite_speaker, "Invite a speaker",
      by: :organiser,
      emits: :speaker_invited,
      rejects: :only_an_open_workshop,
      from: :open,
      or_rejects: :only_an_open_workshop do
      field :speaker_id, :id
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

    event :speaker_invited, "Speaker invited" do
      field :speaker_id, :id
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

  scenario "an open workshop invites a speaker" do
    given :places_offered, %{capacity: 10}
    command :invite_speaker, %{speaker_id: "speaker-1"}
    expect :speaker_invited
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

## What does an aggregate declare?

An aggregate is one thing with an identity that lasts: a workshop, a loan, a visit. It holds the
rules that apply to that thing alone.

- **Its identity.** `identity` names the fields that tell one aggregate from another. The library
  adds them to the state, the commands and the events of the aggregate. So `workshop_id` is in each
  of them, and you do not declare it there.
- **Its commands.** A command says who can issue it (`by:`), which events it can produce
  (`emits:`), and which rules can refuse it (`rejects:`). A command without `by:` must have a
  policy or a process manager of the contract that issues it ([`C1`](refusals.md#refusals-c)).
- **Its events.** An event is what the aggregate decided. If no command emits an event, an actor
  records it without a decision: `recorded_by: :front_desk`. Such an event enters the log through
  `EhOsContract.record/3`. The compiler refuses an event that is neither
  ([`A2`](refusals.md#refusals-a)).
- **Its state.** The state is what the aggregate keeps between two decisions. The engine folds it
  from the events of the aggregate. It holds only what a decision reads.
- **Its invariants.** An *invariant* is a rule that each command keeps, in the words of the
  business. A *constraint* is a rule of one command, about the data of that command. Each invariant
  and each constraint needs a scenario that refuses on it ([`S8`](refusals.md#refusals-s)).
- **Its lifecycle**, if it has one. The next section tells about it.

An aggregate does not say which run of a process its events belong to, in which stage, or which
event ends the run. A [process module](process.md) says that.

### What does a generated identity do?

`identity :booking_id, generated: :uuid` tells the library to give each new aggregate its identity,
a UUIDv7. The library gives it when a command with `creates: true` arrives without an identity.

Dispatch refuses such a command in two cases:

- The command brings its own identity: `{:error, {:invalid, [booking_id: :generated]}}`.
- The command has no idempotency key: `{:error, :idempotency_key_required}`. Without the key, a
  retry of the command makes a second aggregate.

### What does a key with rules of its own do?

An identity can name a domain value, for example `identity [:company_id, period_id: :period]`.
Dispatch holds the key to the invariants of the value.

- If the key of a command or of a recorded event breaks an invariant, dispatch refuses it. It
  does not read a stream. It returns `{:error, {:invalid, [period_id: {:invariant, name}]}}`.
- The type of the value must be `:id`, because the key names the stream
  ([`F1`](refusals.md#refusals-f)).

## What is a lifecycle?

A *lifecycle* names the statuses that the decisions of an aggregate depend on. It says which status
the first event starts the aggregate in, and which events move it from one status to another.

- The engine calculates the *status* from the names of the events in the stream, and puts it in the
  state.
- `from:` on a command names the statuses in which the command can be issued.
- In another status, dispatch refuses the command with its `or_rejects:` invariant. Your code does
  not run.

![The event places_offered starts the workshop in Open; speaker_invited keeps it there; called_off moves it to Called off, where call_off is refused.](img/units-lifecycle.svg)

1. The event `places_offered` starts the workshop in the status Open.
2. No transition names the event `speaker_invited`, so the workshop stays Open.
3. The event `called_off` moves the workshop to Called off. This status is final.
4. In Called off, dispatch refuses `call_off` with a rejection on `only_an_open_workshop`.

### What does the lifecycle allow at run time?

Dispatch holds each decision to the lifecycle, one event at a time.

- If a decision emits an event that the lifecycle does not allow from the current status, dispatch
  raises. It appends nothing.
- Before the first event, the lifecycle allows only an event that `initial` names.
- After the first event, it allows an event that no transition names, in each status that is not
  final. The status does not change. An `initial` event is not allowed again.
- In a final status, it allows no event.
- A recorded event that does not fit the lifecycle is appended. It does not change the status.

[The compile refusals](refusals.md#refusals-t) list what the compiler refuses in a lifecycle.

## What is a dynamic consistency boundary?

Some rules read events that belong to different things. Example: "A workshop never has more
attendees than places". This rule reads the places of the workshop, and each seat on it. Each seat
belongs to an attendee.

An aggregate can hold this rule: each seat goes into the stream of the workshop. Then the decision
of each attendee goes through that one stream. A dynamic consistency boundary reads only the events
that the rule reads.

A `dcb` declares what it reads with `consults`:

- `consults :seat_taken, match: :workshop_id` reads each `seat_taken` that has the `workshop_id` of
  the boundary. `match:` names fields of the identity of the boundary.
- Each event of the contract that a boundary consults with `match:` must have these fields. Each
  field is a required `:id` that is not personal, or a domain value on an `:id`, such as a period
  "2026-07" ([`A4`](refusals.md#refusals-a)).
- `consults :enrolment_closed, where: "enrolment closed for every course"` reads each event of
  that type, about any thing. The prose gives the rule. Use it only when no field can say it.

A boundary can consult an event of another unit of its contract. It can also consult an event that
the contract `consumes` from a sibling contract. The compiler refuses an event that another
application sends ([`A4`](refusals.md#refusals-a)).

A boundary has no lifecycle and no generated identity. It reads more than one stream, and the
command gives its identity.

### Which events does each unit read?

![An aggregate folds its own stream; a boundary folds the events that its consults match; dispatch appends each decision only if what it read did not change.](img/units-reads.svg)

1. The engine selects the stream of the workshop: the events with its name and its identity.
2. The aggregate folds its stream through `evolve/2`, and decides.
3. The engine matches the consulted events: each type that `consults` names, with the same
   `workshop_id`. It adds the own events of the seat.
4. The boundary folds these events in the order of the log, and decides.
5. Dispatch appends the decision of the aggregate if no event was added to its stream after step 1.
6. Dispatch appends the decision of the boundary if no event that it read was appended after step 3.

If the condition of step 5 or 6 fails, dispatch reads and decides again. It decides at most 3
times in all. Then it returns `{:error, :conflict}`.

A boundary reads, and conflicts on, only the types of event that its `evolve/2` names. This is true
when each other clause is exactly `def evolve(state, _), do: state`.
[Write the code that decides](deciding.md) tells the rule.

### Which one do I choose?

- Choose an aggregate when the rule is about one thing, and the events that it reads are of that
  thing.
- Choose a boundary when the rule reads events of more than one thing. Use `match:` to read only the
  events of the decision.

A boundary that reads more than it needs conflicts with each decision that changes what it read. If
a boundary consults with `where:` alone, the check gives the warning `consults-without-match`.

## What is a domain service?

A domain service holds logic that belongs to no unit. Examples: the free places of a workshop, a
price from a tariff.

- A domain service has pure functions. Each function has typed arguments, a typed result and its
  rules.
- Each rule has examples. Each example is a test: the function gets the arguments, and must return
  the result. `{[1, 3], 0}` means that `free_places(1, 3)` returns `0`.
- The compiler refuses a rule without examples ([`S9`](refusals.md#refusals-s)).
- A decision calls the function through the module that the contract makes:
  `Concepts.Units.Contracts.Workshops.DomainServices.Seating.free_places(3, 1)`. It does not call
  the implementation directly.
- That module checks the arguments against their types, runs the implementation, and checks the
  result. It also checks the invariants of the values.
- If a check fails, the module raises. A wrong argument or result is a defect in the code. It is
  never an answer of the business.

## What does the check say about a unit?

`mix eh_os_contract.check` reads the units of each contract. [The rules of the check](rules.md)
give each rule. These rules are about the declaration of a unit:

- `aggregate-without-events`: a unit has no event, so it decides nothing.
- `event-name-with-aggregate-prefix`: the name of an event starts with the name of its unit, for
  example `workshop_offered`. Name what occurred: `places_offered`.
- `consults-without-match`: a boundary reads each event of a type. Under load, most of its
  decisions are tried again, or refused with `:conflict`.
- `core-unit-records-only`: a unit of a core subdomain has no command that can be refused. Its page
  shows "Records only", in any context.
- `core-command-never-refuses` (a notice): a command of a core subdomain rejects nothing.

## Next steps

- [Write the code that decides](deciding.md): the module of each unit and domain service.
- [Change an event that already has rows](event-versions.md): a new version of an event, and how
  old rows read in it.
- [What is a scenario?](scenarios.md): the examples that prove each rule.
- [Write a domain, a contract and a process module](contract.md): the full task.
- [The compile refusals](refusals.md#refusals-a): each refusal of a unit, and of a lifecycle
  ([`T`](refusals.md#refusals-t)).
