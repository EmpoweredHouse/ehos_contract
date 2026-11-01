# Change an event that already has rows

<!-- covers: entities contract.aggregate.event.upcast -->

This page tells how to change the fields of an event when the log already holds rows of it. It is
for a developer who changes a contract that runs in production. [The glossary](glossary.md) defines
each word in italics.

The log keeps each event as it was written. The engine reads each row again with the declaration
of today. It does this to fold the state of a unit, to give the event to a reaction, and to publish
it. The rows never change. So a change to an event that has rows needs two things:

- a new *schema version* of the event: `schema_version: 2`;
- an *upcast*: a step that tells how a row of the version before reads in the new version.

## Before you start

- The contract declares the event, and the log holds rows of it.
- The host has `eh_os_contract.lock` beside `mix.lock`. `mix eh_os_contract.schema` writes it.

This page uses this contract. An organiser records the places of a workshop. Version 1 of
`places_offered` has the field `places`. The unit needs a module only for a step by a function, so
its module is empty until then:

```elixir
defmodule Concepts.EventVersions.Domain do
  use EhOsContract.Domain, name: :event_versions_example, language: :en

  subdomain :events, "Events", type: :supporting
  context :workshops, "Workshops", subdomain: :events
  actor :organiser, :human, "Organiser"
end

defmodule Concepts.EventVersions.Contracts.Workshops do
  use EhOsContract.Contract,
    domain: Concepts.EventVersions.Domain,
    context: :workshops,
    id: "event_versions_example.workshops"

  aggregate :workshop, "Workshop" do
    identity :workshop_id

    event :places_offered, "Places offered", recorded_by: :organiser do
      field :places, :integer
    end
  end
end

defmodule Concepts.EventVersions.Workshop do
  use Concepts.EventVersions.Contracts.Workshops, aggregate: :workshop
end
```

## Know what a step cannot carry

The log keeps some fields beside the payload of a row, by their names. A step cannot carry them to
a new name or a new value:

- the identity of the unit;
- each field that the log tags each row with: a required `:id`, `:date` or `:timestamp` that is
  not personal. A boundary, a process and the report find rows by these fields.

A change to one of these fields is a new event, not a new version. The compiler refuses a step that
renames the identity, or that renames onto a tagged field or gives it a default
([`U3`](refusals.md#refusals-u)).

[The lock](#record-the-versions-in-the-lock) refuses the changes below, even with a step. The rows
keep what they were written with:

- a field that becomes personal, stops being personal, or is sealed by another identifier;
- a personal field whose type changes, or a value with personal data whose shape changes. A sealed
  value cannot be converted, and its seal cannot move;
- a required personal field that old rows can lack: added, made required, or added or changed
  inside a value. A default is clear text, and a function makes no seal;
- an identifier that seals a field, given another `subject:`;
- a field that the log tags rows with, which the version before did not tag under that name.

Each of these is a new event.

## Raise the version, and write the step

1. Raise `schema_version`, change the fields, and add `upcast from:` the version before:

   <!-- in: Concepts.EventVersions.Contracts.Workshops, aggregate :workshop -->
   ```elixir
   event :places_offered, "Places offered", schema_version: 2, recorded_by: :organiser do
     field :capacity, :integer
     field :room, :string, optional: true

     upcast from: 1, rename: [places: :capacity], default: [room: "Main hall"]
   end
   ```

   **Result:** the engine reads a row of version 1 with `places` under its new name, `capacity`,
   and with `room` as `"Main hall"`. It reads a row of version 2 as it is.

2. For each later version, add one more step. Version 3 adds `upcast from: 2`. A row of version 1
   then goes through both steps, in order. The compiler refuses a version without one step from
   each version below it ([`U1`](refusals.md#refusals-u)).

A step can say these things:

- **`rename:`** moves a field of the older version to its name in the next version. You can rename
  a personal field: the engine opens its sealed value under the name it was sealed with.
- **`default:`** gives a value to a field that the older version did not have. Write it as the log
  stores it: an enum member as its name, a date as text. A row that holds the field keeps its own
  value.
- If a rename goes onto a name that an old row already holds, it replaces the value of that row.
  So give both the rename and the default, or neither.
- **A step with neither** says that the fields kept their shape. You raise the version only for
  their meaning.
- **`function:`** names a function of the implementation, for a change that a rename and a default
  cannot say. A function is a step of its own. The next section tells how.

The compiler refuses these steps:

- a step to a field that the event will not have ([`U2`](refusals.md#refusals-u)).
- a default for a personal field, or for a value that holds personal data
  ([`U3`](refusals.md#refusals-u)).
- a default that is not a value of its field ([`U4`](refusals.md#refusals-u)).

## Change the data of a row with a function

A function can say these changes:

- amounts in cents that now read as a decimal;
- one field split in two;
- two fields joined in one.

In this example, version 1 of `places_offered` had the fields `rows` and `seats_per_row`, not
`places`. Version 2 has `capacity`, their product.

1. Name the function in the step:

   <!-- in: Concepts.EventVersions.Contracts.Workshops, aggregate :workshop -->
   ```elixir
   event :places_offered, "Places offered", schema_version: 2, recorded_by: :organiser do
     field :capacity, :integer

     upcast from: 1, function: :capacity_from_rows
   end
   ```

2. Write the function in the implementation of the unit:

   <!-- and in: Concepts.EventVersions.Workshop -->
   ```elixir
   @impl true
   def capacity_from_rows(%{"rows" => rows, "seats_per_row" => seats} = data),
     do: data |> Map.drop(["rows", "seats_per_row"]) |> Map.put("capacity", rows * seats)
   ```

   **Result:** the module compiles. Without the function, the compiler refuses it
   ([`I2`](refusals.md#refusals-i)).

The function gets the payload of the row at its version, as the log stores it, with string keys. It
returns the payload of the next version. The engine reads what it returns as the log stores a
value. So a decimal, a date or an atom key reads as in an old row.

The function is pure: it reads only the row. The engine cannot see what it did. So the engine
refuses the row, and names the step but never a value, when the function did one of these things:

- It moved a sealed personal value, made one, or changed the order of a list that holds one. A seal
  opens only under the field it was sealed in. So rename a personal field with `rename:`. The
  function sees its value sealed, and cannot convert it.
- It left a field that the log tags rows with different from the field the row was written with.
  A new required `:id` is such a field. That change is a new event.
- It raised, threw or exited, or returned something that is not a map.

So write the function for each row of its version, also a row that lacks a field. A row that the
engine refuses stops each read of its stream: each command to that unit fails. The relay stops at
the event too, and after 3 failures it waits for a person to decide.

<a id="record-the-versions-in-the-lock"></a>

## Record the versions in the lock

A compile sees only the declaration of today. It cannot tell a field added to version 1 from
version 1 as it always was. `eh_os_contract.lock` keeps that record: the fields of each event, by
its type in the log and its version, as a row holds them.

1. Run the task, and commit the file:

   ```bash
   mix eh_os_contract.schema
   ```

   **Result:** a pull request shows the new version as the fields that the lock records.

2. Run the check beside `mix eh_os_contract.check`, in the gate of the application:

   ```bash
   mix eh_os_contract.schema --check
   ```

   **Result:** the check passes when the lock and the contracts agree.

The lock records a change in place when old rows still read:

- a field added as optional, or a field removed;
- a required field made optional;
- an enum given more members;
- an `:integer` made a `:decimal`, or an `:id` made a `:string`;
- the same changes inside a list or a domain value.

A field removed stays in the file, with `removed: true`. Old rows still hold it, and new rows do
not. If you declare a field with that name again, the lock holds it to what both hold.

The type of a field in the lock is what the log stores. So if a domain value gets another field,
each event that holds the value changes. A new name for the value, a new label for a field, or a new
order of the fields changes nothing.

### What does the lock refuse?

`--check` fails in these cases:

- A recorded version changed in another way than the list above.
- The steps from a recorded version to the declared version do not cover what changed.
- The file records a version newer than the declared version.
- The file records an event that no contract declares now.
- The file is behind the contracts.

The lock holds the steps of a raised version to what changed from each earlier version in the file.
It reads each one as the engine reads an old row, through the steps between them:

- `rename:` carries a field to its new name.
- `default:` gives a new required field its value where an old row does not have it.
- A step with a function covers each change that a step can carry.

So the lock refuses these changes without a step, and names the field and the steps:

- a field renamed without `rename:`;
- a required field added without a default;
- an optional field made required. Old rows hold an explicit `nil`, which a default does not fill;
- a type changed in another way than the list above, with no function step.

The message looks like this:

```
** (Mix) eh_os_contract.lock and the contracts disagree:

  * shop.orders.order_placed at schema_version 1: courier was added, [type: :string], and is
    required: give it a `default:`, or make it optional. A row written at version 1 holds the fields
    the lock records, and would not read: raise its schema_version with a step `upcast from: 1` that
    covers the change, or, if no log holds rows of it, run
    `mix eh_os_contract.schema --forget shop.orders.order_placed`
```

## What can go wrong

**A version that no log holds rows of.** For example, you added a version on a branch that you
never deployed. `mix eh_os_contract.schema --forget TYPE` drops the versions of the event from the
declared version up, and records what is declared. For an event that no contract declares, it
drops each version. Do not use it for a version that a log holds rows of.

**A seal goes to the subscribers.** A `publish` cannot name a personal field
([`D11`](refusals.md#refusals-d)). But rows written while a field was personal hold its value
sealed. The relay publishes a row in the current shape of the event, with its values as stored. So
a field that stops being personal, or a field that a personal field is renamed onto, sends those
seals to each subscriber. The lock refuses both changes. Without the lock, or after `--forget` of
a version that the log holds rows of, the relay publishes them (`EhOsContract.Relay`).

## Next steps

- [Write the code that decides](deciding.md): `evolve/2`, which reads each version through the
  steps.
- [How does the engine keep and erase personal data?](personal-data.md): personal fields and their
  seals.
- [The compile refusals](refusals.md#refusals-u): each refusal of a version and its steps.
- [The Mix tasks](cli.md): `mix eh_os_contract.schema` and its options.
