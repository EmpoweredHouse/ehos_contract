# Actors, values, entities and external systems

This page tells what a domain declares besides its contexts, and what the engine does with each
declaration. It is for a developer who writes the domain of an application. [The
glossary](glossary.md) defines each word of the contract language.

<!-- covers: entities domain.actor, domain.value, domain.entity, domain.external; rules orphan-actor, orphan-external-system, operation-never-called, external-direction-contradicted, value-without-implementation, scoped-actor-with-unscoped-command -->

[The domain](domain.md) tells how a domain divides a business into contexts.
[Personal data and erasure](personal-data.md) tells how a domain declares the subjects of personal
data. [The domain reference](dsl/domain-dsl.md) gives each key of this page.

## What is an actor?

An actor is a kind of person or a system that issues commands, asks queries or records events. A
contract names its actors in the `by:` of a command or a query, and in the `recorded_by:` of an
event. Dispatch refuses an actor that the declaration does not name. It does this before it does
anything else.

<!-- in: Concepts.DomainData.Domain -->
```elixir
actor :mechanic, :human, "Mechanic", context: :workshop, scope: [:shop_id]
actor :payment_terminal, :system, "Payment terminal", backed_by: :card_terminal
```

- **A human actor is a role.** The platform that issues credentials grants roles to people. The role
  of `:mechanic` in the domain `:shop` is `shop.mechanic`. A credential carries the capabilities of its
  roles. The engine does not know the person: it sees an opaque subject.
  [Authorization](authorization.md) tells how a credential becomes an actor.
- **A system actor is code of the application** that acts as itself, such as a job or an import:
  `EhOsContract.Actor.system(:payment_terminal)`. It needs no credential. It can do what the
  declarations that name it allow.
- **`backed_by:`** names the external system that a system actor stands for. The compiler refuses
  `backed_by:` on a human actor ([`D4`](refusals.md#refusals-d)).
- **`context:`** puts the actor in one context. A contract of another context cannot name it
  ([`X2`](refusals.md#refusals-x)). An actor without `context:` can act in each context.
- **`responsibility`**, in the block of the actor, names what the actor answers for. A page shows it.
  Nothing runs it.

The check warns about an actor that no declaration names (`orphan-actor`). The actor of a scenario
does not count.

## What does the scope of an actor do?

`scope:` lists the dimensions that can narrow a grant to this actor. Examples: a shop, a clinic, a
region. A command or a query declared with `scope: :shop_id` then works like this:

1. Dispatch asks the `EhOsContract.Authorizer` about the value of the field `shop_id`.
2. If the grant of the credential holds other shops, the authorizer refuses.
3. If the grant holds no values, the authorizer refuses too. Empty does not mean "all".

Each actor in the `by:` of a scoped declaration must have the dimension
([`D10`](refusals.md#refusals-d)). [Authorization](authorization.md) tells what the checks do
before and after a query runs.

The check warns when an actor with a scope is in the `by:` of a command without `scope`
(`scoped-actor-with-unscoped-command`). Then the capability of that command is valid for each shop.
Declare the `scope` of the command, or name another actor if this is what you want.

<a id="who-may-let-whom-in"></a>

## Who can let whom in?

Some people come to an application through its own work, not through a decision of the company.
Example: an accountant adds a client company and its representative. The representative then signs in
to see that company. `may_grant:` tells which roles a person of this actor can grant through the
application:

<!-- in: Concepts.DomainData.Domain -->
```elixir
actor :office_employee, :human, "Office employee", may_grant: [:client]
actor :client, :human, "Client"
```

- The rule goes into the manifest, beside the role. The person who approves a deployment sees it. A
  new rule widens what the application asks for.
- Only a human actor grants a role or gets one.
- A rule cannot name its own actor. Rules cannot lead back to an actor: if `a` grants `b` and `b`
  grants `a`, a holder of `a` can grant `a` ([`D4`](refusals.md#refusals-d)).
- An actor in a rule, and an actor with a rule, must hold a capability. Otherwise it is no role in
  the manifest, and the generator of the manifest tells you.

## What is a value?

A value is a name that the domain gives to a type of data. A field of a contract can use it as its
type: `field :quote, :money`. A value is one of these:

- a built-in type: `:id`, `:string`, `:integer`, `:decimal`, `:boolean`, `:date`, `:timestamp`, an
  enum or a list. A number can have a `unit`;
- a set of fields.

<!-- in: Concepts.DomainData.Domain -->
```elixir
value :money, :integer, unit: :cents, label: "Amount"
value :bike_kind, {:enum, [city: "City bike", road: "Road bike"]}, label: "Kind of bike"

value :address, label: "Address" do
  field :street, :string
  field :city, :string
end
```

The compiler refuses a value with both a type and fields, or with neither. It refuses a `unit` on a
value that is not an `:integer` or a `:decimal` ([`D3`](refusals.md#refusals-d)).

A field of a value can be personal. Then the field holds personal data in each place that uses the
value. [Personal data and erasure](personal-data.md) tells how to mark it.

## What does the engine do with a value of fields?

The domain generates a struct for each value of fields, such as `<Domain>.Values.Address`. The
struct enforces the required fields. So `%Address{street: "Main 1"}` without a `city` does not
compile.

The engine gives this struct in each place where the value occurs. Examples: a command, an event,
the state of a unit, the rows of a form, the `Row` of a read model. Build the value as its struct in a decision
or a reaction. A map with the same keys is not the value:

- Dispatch refuses a command that carries a map, with the field and `:type`.
- Dispatch raises an exception for an event that a decision returns with a map.
- The same is true for the row of an entity, the answer of a supplier, and the arguments and the
  result of a domain service.

A scenario writes the value as a map, and the engine casts it. The reason is that a contract does
not depend on its domain when it compiles. For the same reason, the `default:` of a state field
with such a value is a map, until `evolve/2` sets the field.

To read the members of an enum, ask the domain. Do not copy them:
`Lending.Domain.members(:bike_kind)` gives `[city: "City bike", road: "Road bike"]`. A member written
as a bare atom has the label `nil`. A name that is not an enum value raises `ArgumentError`.

<a id="what-is-an-invariant-of-a-value"></a>

## What is an invariant of a value?

An invariant of a value is a rule that is true for each value of the type. Each invariant has
examples that break it and examples that keep it:

<!-- and in: Concepts.DomainData.Domain -->
```elixir
value :money, :integer, unit: :cents do
  invariant :not_negative, "An amount is not negative",
    violated_by: [-1],
    satisfied_by: [0, 4_500]
end
```

1. The domain generates a behaviour, `<Domain>.Values.Money`.
2. You write a module with `use <Domain>, value: :money`. It defines one function for each
   invariant, with the name of the invariant. The function gives `true` or `false`.
3. Dispatch holds each value of the type to the invariants. If a command or a recorded event
   carries a value that breaks one, dispatch refuses it. The error names the field with
   `{:invariant, :not_negative}`.
4. If a decision returns an event with such a value, dispatch raises an exception.
5. `use EhOsContract.ScenarioCase, domain: <Domain>` makes a test of each example.

The engine does not hold the events that it reads back from the log to the invariants. So an
invariant that you add today does not make the events of yesterday unreadable.

The check warns about a value with invariants and no module that checks them
(`value-without-implementation`). Dispatch raises an exception for each value of it. The check
reports this only after some contract of the domain has an implementation.

## What is an entity?

An entity is a thing with an identity, such as a shop, an item of a catalogue or an accounting
period. The code of the application, or another system, keeps its lifecycle outside the log. A
contract points to it by its identity, with a field of the type `{:id, :shop}`.

<!-- in: Concepts.DomainData.Domain -->
```elixir
entity :shop, "Shop", context: :workshop, identity: :shop_id
```

- An entity belongs to one context. `context:` is required.
- The engine adds its `identity` to its fields, as a required `:id` that is not personal.
- `issued_by:` names the external system that gives the identity, if a system gives it.
- The fields of an entity cannot be personal ([`D6`](refusals.md#refusals-d)).
- A contract that names an entity of another context depends on that context. [The
  domain](domain.md#which-context-depends-on-which) tells how to declare this.

If commands of this application decide the lifecycle of a thing, it is not an entity. It is a unit
of a contract: an aggregate or a dynamic consistency boundary.

## What is an external system?

An external system is a system that the application exchanges data with. Its name tells what it
does for the business, not the name of its vendor: `:card_terminal`, not the brand of the terminal.

<!-- in: Concepts.DomainData.Domain -->
```elixir
external :sms_gateway, "Text message gateway",
  direction: :outbound,
  unavailable_looks_like: "Customers are not told their bike is ready",
  expected_latency: {5, :second} do
  operation :send_text, "Send a text message"
end
```

`direction:` tells which way the data goes:

| Direction | What it tells |
| --- | --- |
| `:inbound` | The system only sends to the application. |
| `:outbound` | The application only sends to the system. |
| `:bidirectional` | Both send. |

`unavailable_looks_like` tells what an outage looks like to the business. `expected_latency` tells
how long an answer usually takes. Pages show both.

A contract uses an external system in four ways:

| Declaration | When |
| --- | --- |
| An effect `calls:` it: `calls: {:sms_gateway, :send_text}` | The effect sends to the system. |
| An event `depends_on:` it | The event needs the answer of the system. |
| A field is `issued_by:` it | The system gives the value, such as an invoice number. |
| A system actor is `backed_by:` it | The system acts in the application. |

If an external system declares an `operation`, each call to it names one
([`X4`](refusals.md#refusals-x)). An external system can also be the upstream end of a directed
relation, as [the domain](domain.md#how-do-two-contexts-relate) tells.

The check warns about these:

- No declaration and no relation uses an external system (`orphan-external-system`).
- No effect calls an operation (`operation-never-called`).
- An `:outbound` system gives the value of a field or the identity of an entity, or backs an actor
  (`external-direction-contradicted`). Each brings data from the system into the application, so
  declare it `:bidirectional`. A call tells nothing about the direction, because an effect calls a
  system to send and to fetch.

## An example

A bike workshop: a mechanic accepts a bike for repair with a quote. A text message tells the
customer. The card terminal records the payment.

```elixir
defmodule Concepts.DomainData.Domain do
  use EhOsContract.Domain, name: :domain_data_page, language: :en

  subdomain :repairs, "Repairs", type: :core
  context :workshop, "Workshop", subdomain: :repairs

  actor :mechanic, :human, "Mechanic", context: :workshop, scope: [:shop_id]
  actor :payment_terminal, :system, "Payment terminal", backed_by: :card_terminal

  value :money, :integer, unit: :cents, label: "Amount" do
    invariant :not_negative, "An amount is not negative",
      violated_by: [-1],
      satisfied_by: [0, 4_500]
  end

  entity :shop, "Shop", context: :workshop, identity: :shop_id

  external :card_terminal, "Card terminal", direction: :inbound

  external :sms_gateway, "Text message gateway",
    direction: :outbound,
    unavailable_looks_like: "Customers are not told their bike is ready" do
    operation :send_text, "Send a text message"
  end
end

defmodule Concepts.DomainData.Money do
  use Concepts.DomainData.Domain, value: :money

  @impl true
  def not_negative(amount), do: amount >= 0
end

defmodule Concepts.DomainData.Contracts.Repairs do
  use EhOsContract.Contract,
    domain: Concepts.DomainData.Domain,
    context: :workshop,
    id: "domain_data_page.repairs"

  aggregate :repair, "Repair of a bike" do
    identity :repair_id

    command :accept_bike, "Accept a bike for repair",
      by: :mechanic,
      scope: :shop_id,
      emits: :bike_accepted do
      field :shop_id, {:id, :shop}
      field :quote, :money
    end

    event :bike_accepted, "Bike accepted" do
      field :shop_id, {:id, :shop}
      field :quote, :money
    end

    event :payment_taken, "Payment taken",
      recorded_by: :payment_terminal,
      depends_on: :card_terminal do
      field :amount, :money
    end
  end

  effect :tell_customer, "Text the customer that the bike was accepted",
    handles: :bike_accepted,
    calls: {:sms_gateway, :send_text},
    idempotency: [key: :event_id, owner: :downstream]

  scenario "a bike is accepted" do
    command :accept_bike, %{shop_id: "s-1", quote: 4_500}
    expect :bike_accepted
  end
end
```

- The mechanic has the scope of a shop, and `accept_bike` has it too. A grant of a mechanic for one
  shop does not accept bikes for another shop.
- `Money` checks each amount that dispatch gets. Dispatch refuses a quote of `-1` before the decision.
- The card terminal is `:inbound`: it backs the actor that records payments.
- The text gateway is `:outbound`: the effect only sends to it.
- The effect runs after the transaction, which is the default for an effect (`:at_least_once`). So
  it names who makes a second delivery harmless: the gateway, which gets the id of the event.

## Next steps

- [Personal data and erasure](personal-data.md): subjects, personal fields and erasure.
- [Units](units.md): the aggregates and boundaries that use these declarations.
- [Authorization](authorization.md): how a credential becomes an actor.
- [The compile refusals](refusals.md), families D and X: each refusal of a domain, with its code.
- [The rules of the check](rules.md): each warning and notice, with its fix.
