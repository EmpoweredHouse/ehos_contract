# Write the code that decides

<!-- covers: rules emits-never-produced, declaration-without-implementation, contract-without-implementation -->

This page tells how to write the module of a unit and of a domain service. It is for a developer
who implements a contract. [The glossary](glossary.md) defines each word in italics.

A contract names no code. Each declaration that decides gets an *implementation*: a module that
points to the contract. Dispatch calls this module when a command arrives.

## Before you start

- A contract that declares the unit, its commands, events and invariants.
  [What are the units that decide?](units.md) tells about them.
- The application of the module is in `config :eh_os_contract, applications: [...]`.
  [Getting started](getting-started.md) tells how.

This page uses the workshop of [the units page](units.md), with one more command:

```elixir
defmodule Concepts.Deciding.Domain do
  use EhOsContract.Domain, name: :deciding_example, language: :en

  subdomain :core, "Core", type: :core
  context :workshops, "Workshops", subdomain: :core
  actor :organiser, :human, "Organiser"
end

defmodule Concepts.Deciding.Contracts.Workshops do
  use EhOsContract.Contract,
    domain: Concepts.Deciding.Domain,
    context: :workshops,
    id: "deciding_example.workshops"

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

    command :invite_speakers, "Invite speakers",
      by: :organiser,
      emits: :speaker_invited,
      rejects: [:only_an_open_workshop, :at_most_ten_speakers],
      from: :open,
      or_rejects: :only_an_open_workshop do
      field :speaker_ids, {:list, :id}
      constraint :at_most_ten_speakers, "A workshop invites at most 10 speakers at once"
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

  scenario "a workshop called off is not called off again" do
    given :places_offered, %{capacity: 10}
    given :called_off
    command :call_off
    rejected :only_an_open_workshop
  end

  scenario "no more than 10 speakers are invited at once" do
    given :places_offered, %{capacity: 20}
    command :invite_speakers, %{speaker_ids: Enum.map(1..11, &"speaker-#{&1}")}
    rejected :at_most_ten_speakers
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

## Write the module of an aggregate

1. Make a module that uses the contract, and name the unit:

   <!-- not compiled: the first line of the module below -->
   ```elixir
   use Concepts.Deciding.Contracts.Workshops, aggregate: :workshop
   ```

   **Result:** the module gets the behaviour of the unit, and the macros `emit/1` and `reject/1`.
   It can name the commands, the events and `State` of the unit by their short names.

2. Write one callback for each command. It takes the command and the state. It returns `emit/1`
   of the events that the command `emits:`, or `reject/1` of a rule that the command `rejects:`.

   ```elixir
   defmodule Concepts.Deciding.Workshop do
     use Concepts.Deciding.Contracts.Workshops, aggregate: :workshop

     @impl true
     def offer_places(%OfferPlaces{workshop_id: id, capacity: capacity}, _state),
       do: emit(%PlacesOffered{workshop_id: id, capacity: capacity})

     @impl true
     def invite_speakers(%InviteSpeakers{speaker_ids: speakers}, _state) when length(speakers) > 10,
       do: reject(:at_most_ten_speakers)

     def invite_speakers(%InviteSpeakers{workshop_id: workshop, speaker_ids: speakers}, _state),
       do: emit(for speaker <- speakers, do: %SpeakerInvited{workshop_id: workshop, speaker_id: speaker})

     @impl true
     def call_off(%CallOff{workshop_id: id}, _state), do: emit(%CalledOff{workshop_id: id})
   end
   ```

   **Result:** `mix compile` passes. The compiler refuses a missing callback
   ([`I2`](refusals.md#refusals-i)).

`call_off` does not refuse anything itself. Its `from: :open` makes dispatch refuse it in each
other status, before the callback runs.

### Emit one event for each item of a list

`invite_speakers` emits one event for each speaker in its data.

- Give `emit/1` a list of struct literals, or a `for` that makes them.
- A `for` with `into:` or `reduce:` makes something else. The compiler refuses it
  ([`I4`](refusals.md#refusals-i)).
- The number of events grows with the list. So give the command a constraint that limits the
  list, as `at_most_ten_speakers` does. A scenario shows the refusal.

## Write the module of a boundary

A boundary has the same callbacks as an aggregate. It also needs `evolve/2`, because it keeps a
state. Its module can name the events that it consults by their short names.

```elixir
defmodule Concepts.Deciding.Seat do
  use Concepts.Deciding.Contracts.Workshops, dcb: :seat

  alias Concepts.Deciding.Contracts.Workshops.DomainServices.Seating

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
```

Write `evolve/2` by these rules:

- A unit needs `evolve/2` only when its state has more than its identity.
- `evolve/2` folds each event into the state. It makes no decision.
- It runs over each event that the stream will ever hold. So it does not raise on data.
- Give it a clause for each event that the state is kept from. Otherwise, the compiler refuses it
  ([`I3`](refusals.md#refusals-i)).
- If you need a catch-all, write exactly `def evolve(state, _), do: state`. Then dispatch reads and
  decodes only the events that the other clauses name.

## Write the module of a domain service

Write one function for each function of the declaration:

```elixir
defmodule Concepts.Deciding.SeatingRules do
  use Concepts.Deciding.Contracts.Workshops, domain_service: :seating

  @impl true
  def free_places(capacity, taken), do: max(capacity - taken, 0)
end
```

A decision calls it through the module that the contract makes, `Seating.free_places/2` above. That
module checks the arguments and the result.

## Keep the decision pure

A decision reads only these things:

- the command;
- its `__meta__`: the actor and `occurred_at`;
- the state;
- the domain services.

Do not read the database, the clock or another service in a callback. On a conflict, dispatch
decides again, at most 3 times in all. A scenario gives a decision only events and a command.

## Refuse with a rule, and let a defect raise

A refusal is an answer of the business. Anything else is a defect.

- `reject/1` names the rule. Dispatch returns `{:error, %EhOsContract.Rejection{}}`. It writes a
  row with the outcome `rejected` in `eh_os_contract_commands`, and appends nothing.
- The compiler refuses `reject/1` of a rule that the command does not `rejects:`
  ([`I5`](refusals.md#refusals-i)).
- An exception raises. Nothing is appended.
- An event outside `emits:`, or an event with fields that do not fit their types, raises. Nothing
  is appended.

## Check that each declaration has its module

The engine finds the implementations in the running code of the applications in its
configuration. Each declaration has one module or none ([`X8`](refusals.md#refusals-x)).

A unit needs no module when each of its events is `recorded_by:` and its state is only its
identity. If it keeps more state, its module has only `evolve/2`, to fold the recorded events.

`mix eh_os_contract.check` tells what is missing. [The rules of the check](rules.md) give each
rule:

- `declaration-without-implementation`: some declarations of the contract have a module, and this
  one has none. Dispatch refuses to run it. Add the module.
- `contract-without-implementation` (a notice): no module implements the contract. A contract can
  exist before its code, but nothing of it can be dispatched.
- `emits-never-produced`: a command can emit an event that no `emit/1` of its module names. Make
  `emits:` match what the code decides, or decide the event with `emit/1`.

## What can go wrong

**Dispatch raises on an event that the lifecycle does not allow.** The lifecycle does not allow
the event from the status of the aggregate. Nothing is appended. Give the
command a `from:`, or change what the callback emits.
[What does the lifecycle allow at run time?](units.md) tells the rules.

**Dispatch returns `{:error, :conflict}`.** Each time that dispatch tried, another command appended
to what the unit read. Dispatch tries at most 3 times.

- If the caller dispatches inside its own transaction, dispatch does not decide again. It returns
  the conflict after the first try. The caller decides if it tries again.
- A boundary that reads more than its rule needs conflicts often. Narrow its `consults` with
  `match:`.

**A scenario fails with no implementation.** A scenario runs the module of its target. A contract
without code is valid. A scenario of it is not.

## Next steps

- [What is a scenario?](scenarios.md): how the scenarios test the code.
- [Change an event that already has rows](event-versions.md): what `evolve/2` reads when an event
  changes.
- [Reactions](reactions.md): the code that takes the events.
- [The compile refusals](refusals.md#refusals-i): each refusal of an implementation.
