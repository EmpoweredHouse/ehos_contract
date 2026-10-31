# What are actors, values, entities and external systems?

<!-- covers: entities domain.actor, domain.value, domain.entity, domain.external; rules orphan-actor, orphan-external-system, operation-never-called, external-direction-contradicted, value-without-implementation, scoped-actor-with-unscoped-command -->

This page tells what a domain declares besides its contexts. It covers who acts, the types of the
data, the things that the application points to, and the systems that it uses. It is for a developer who
writes a domain. [The glossary](../glossary.md) defines each word in italics.

[How does a domain divide a business into contexts?](domain.md) tells about the subdomains, the
contexts and their relations. [Personal data and erasure](personal-data.md) tells about the
subjects. [The domain reference](../dsl/domain-dsl.md) lists each key of this page.

## What is an actor?

An *actor* issues commands, asks queries or records events. It is a kind of person (`:human`) or a
system (`:system`). A contract names its actors in the `by:` of a command or a query, and in the
`recorded_by:` of an event. Dispatch first refuses an actor that the declaration does not name.

<!-- in: Concepts.DomainData.Domain -->
```elixir
actor :mechanic, :human, "Mechanic", context: :workshop, scope: [:shop_id]
actor :payment_terminal, :system, "Payment terminal", backed_by: :card_terminal
```

- **A human actor is a role.** The platform that issues the credentials grants roles to people. The
  role of `:mechanic` in the domain `:shop` is `shop.mechanic`. A credential carries the capabilities
  of its roles. The engine does not know who is behind a credential: it sees an opaque subject.
  [Authorization](../authorization.md) tells how a credential becomes an actor.
- **A system actor is code of the application** that acts as itself, for example a job or an
  import: `EhOsContract.Actor.system(:payment_terminal)`. It needs no credential. It can do what the
  declarations that name it permit.
- **`backed_by:`** names the external system that a system actor stands for. The compiler refuses
  `backed_by:` on a human actor ([`D4`](../refusals.md#refusals-d)).
- **`context:`** puts the actor in one context. The compiler refuses the actor in a contract of
  another context ([`X2`](../refusals.md#refusals-x)). An actor without `context:` can act in each
  context.
- **`responsibility`**, in the block of the actor, names what the actor answers for, in the words of
  the workshop material. A page shows it. No code reads it.

If no `by:`, no `recorded_by:` and no `accountable` of a process module names an actor, the check
warns `orphan-actor`. The actor of a scenario does not count. Remove the actor, or write the
contract that gives it work.

### How does a scope narrow a grant?

`scope:` lists the dimensions that can narrow a grant to the actor, for example a shop, a clinic or a
region. Example: a command declares `scope: :shop_id`. Then dispatch gives the value of `shop_id` to
the `EhOsContract.Authorizer`, with the capability.

- If the grant of the credential holds other shops, the authorizer refuses the command.
- If the grant of a scoped capability holds no values, the authorizer refuses it too. An empty
  grant does not mean "all shops".
- Each actor in the `by:` of a scoped declaration must have the dimension
  ([`D10`](../refusals.md#refusals-d)).

[Authorization](../authorization.md) tells what the checks do before and after a query runs.

If an actor with a scope is in the `by:` of a command without `scope`, the check warns
`scoped-actor-with-unscoped-command`. For this actor, the capability of that command is then valid
in the whole application. Declare the `scope` of the command if it acts on one of the dimensions.
If you want the authority in the whole application, name a different actor.

<a id="who-may-let-whom-in"></a>

### Who can let whom in?

Some people come to an application through its own work, not through a decision of the company.
Example: an accountant adds a client company and its representative. The representative then signs
in to see that company. `may_grant:` names the roles of other human actors that a person in this
role can grant through the application:

<!-- in: Concepts.DomainData.Domain -->
```elixir
actor :office_employee, :human, "Office employee", may_grant: [:client]
actor :client, :human, "Client"
```

The rule goes into the manifest of the application, beside the role. The platform shows it to the
person who approves a deployment, because a new rule makes the application ask for more.

The compiler refuses these rules ([`D4`](../refusals.md#refusals-d)):

- a rule on a system actor, or a rule that names a system actor: only a person grants and gets a
  role;
- a rule that names the actor itself, an actor that the domain does not declare, or one actor two
  times;
- rules that lead back to an actor. If `a` grants `b` and `b` grants `a`, a person with `a` can grant
  `a` through `b`.

An actor that a rule names, and an actor that has a rule, must have a capability. Otherwise the
actor is no role in the manifest, and the generator of the manifest says so.

## What is a value?

A *value* is a name that the domain gives to a type of data. It is one of two things:

- one built-in type: `:id`, `:string`, `:integer`, `:decimal`, `:boolean`, `:date`, `:timestamp`, an
  enum or a list. A number can have a `unit`.
- a set of fields.

A field of a contract uses the value as its type, for example `field :quote, :money`.

<!-- in: Concepts.DomainData.Domain -->
```elixir
value :money, :integer, unit: :cents, label: "Amount"
value :bike_kind, {:enum, [city: "City bike", road: "Road bike"]}, label: "Kind of bike"

value :address, label: "Address" do
  field :street, :string
  field :city, :string
end
```

A value has a type or fields. The compiler refuses a value with both, or with neither, and a `unit`
on a value that is not an `:integer` or a `:decimal` ([`D3`](../refusals.md#refusals-d)). A field
of a value with fields can be personal: [Personal data and erasure](personal-data.md#personal-data-in-a-value)
tells how.

If a value, or a member of its enum written as a bare atom, has no label, the check gives the notice
`owner-view-without-label`. A business owner then reads the name in the code. Write the member as
`card: "Card"`, and give the value `label:`.

### What does the code get for a value with fields?

The domain generates a struct for each value with fields, for example `<Domain>.Values.Address`. The
struct requires its required fields: `%Address{street: "Main 1"}` without `city` does not compile.

The engine gives this struct in each place where the value occurs:

- in a command and in an event;
- in the state of a unit;
- in the rows of a form;
- in the `Row` of a read model.

Build the value as its struct in a decider or in a reaction. A map with the same keys is not the
value:

- dispatch refuses a command that carries a map in place of the struct, with the field and `:type`;
- the engine raises when a decision returns an event with a map in place of the struct;
- the engine also raises for a map in the row of an entity, or in the answer of a supplier;
- the engine also raises for a map in an argument or a result of a domain service.

A scenario writes the value as a map, and the engine casts it. A contract does not depend on its
domain at compile time, so it cannot build the struct. For the same reason, the `default:` of a
state field that holds such a value is a map, until `evolve/2` sets the field.

### Where do the members of an enum come from?

Code that needs the members of an enum reads them from the domain. Do not copy them. Example: the
options of a select, or a check of your own.

`Lending.Domain.members(:bike_kind)` returns `[city: "City bike", road: "Road bike"]`: each member
with its label, or with `nil` for a member written as a bare atom. The function knows only the
names of enum values. For each other name, it raises `ArgumentError`.

### What does an invariant of a value check?

A value can declare an *invariant*: a rule that is true of each value of the type. Each invariant
gives values that break it and values that keep it:

<!-- and in: Concepts.DomainData.Domain -->
```elixir
value :money, :integer, unit: :cents do
  invariant :not_negative, "An amount is not negative",
    violated_by: [-1],
    satisfied_by: [0, 4_500]
end
```

The domain then generates a behaviour, `<Domain>.Values.Money`. A module with
`use <Domain>, value: :money` defines one function for each invariant, with the name of the
invariant. The function returns `true` or `false`.

Dispatch holds each value of the type to these functions:

- It refuses a command or a recorded event with a value that breaks an invariant. The refusal names
  the field, with `{:invariant, :not_negative}`.
- It raises when a decision returns an event with such a value.
- It does not check what it reads back from the log. So an invariant that you declare today does not
  make the events of yesterday unreadable.

`use EhOsContract.ScenarioCase, domain: <Domain>` makes each example a test.

If a value declares invariants and no module checks them, the check warns
`value-without-implementation`: dispatch raises on each value of the type. Add a module with
`use <Domain>, value: <name>`. The check gives this warning only when a contract of the domain has
an implementation.

## What is an entity?

An *entity* is a thing with an identity, whose lifecycle the code of the application or another
system keeps, outside the log. Examples: a shop, an item of a catalogue, an accounting period. A
contract points to an entity by its identity, with a field of type `{:id, :shop}`.

<!-- in: Concepts.DomainData.Domain -->
```elixir
entity :shop, "Shop", context: :workshop, identity: :shop_id
```

- `context:` is required. An entity belongs to one context.
- `identity` becomes a field of the entity: a required `:id` that is not personal.
- `issued_by:` names the external system that gives the identity, if one does.
- The compiler refuses a personal field in an entity ([`D6`](../refusals.md#refusals-d)).

A contract that names an entity of another context depends on that context.
[Which context depends on which?](domain.md#which-context-depends-on-which) tells how the domain
declares this dependency.

If commands of this application decide the lifecycle of a thing, the thing is not an entity of the
domain. It is a unit of a contract: an aggregate or a dynamic consistency boundary.

## What is an external system?

An *external system* is a system that the application exchanges data with. Its name tells what it
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

- `direction:` tells which way the data goes. `:inbound`: only the system sends to the application.
  `:outbound`: only the application sends to the system. `:bidirectional`: both.
- `unavailable_looks_like` tells what an outage looks like to the business.
- `expected_latency` tells how long an answer usually takes.
- The pages of the model show these two keys. No code reads them.

A contract uses an external system in four ways:

| Declaration | Key | When |
| --- | --- | --- |
| an effect | `calls: {:sms_gateway, :send_text}` | The effect calls the system. If the system declares an `operation`, each call names one ([`X4`](../refusals.md#refusals-x)). |
| an event | `depends_on:` | The event needs the answer of the system. |
| a field | `issued_by:` | The system gives the value, for example the number of an invoice or the tracking number of a parcel. |
| a system actor | `backed_by:` | The system acts in the application. |

An external system can also be one end of a directed relation. The other end is then a context. The
compiler refuses a name that is both a context and an external system
([`D1`](../refusals.md#refusals-d)).

The check warns about external systems in three cases:

- `orphan-external-system`: nothing uses the system. No actor is backed by it, and no relation ends
  at it. No field or entity is issued by it, no effect calls it, and no event depends on it.
- `operation-never-called`: no effect names the operation in `calls:`. The check asks this only for
  a system that an effect calls. For a system that no effect calls, `orphan-external-system` warns
  instead, if nothing else uses the system.
- `external-direction-contradicted`: a system with `direction: :outbound` issues the value of a
  field or the identity of an entity, or backs an actor. Each of these brings data from the system
  into the application. Declare the system `:bidirectional` if it also answers. A call does not
  count, because an effect calls a system to send and to fetch.

## An example

A bike workshop. A mechanic accepts a bike for repair, with a quote. A text message tells the
customer. The card terminal records the payment.

```elixir
defmodule Concepts.DomainData.Domain do
  use EhOsContract.Domain, name: :domain_data_page, language: :en

  subdomain :repairs, "Repairs", type: :core
  context :workshop, "Workshop", subdomain: :repairs

  actor :mechanic, :human, "Mechanic", context: :workshop, scope: [:shop_id]
  actor :payment_terminal, :system, "Payment terminal", backed_by: :card_terminal

  subject :customer, "Customer"

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
      field :customer_id, :id, subject: :customer
      field :customer_phone, :string, personal: :customer_id
      field :quote, :money
    end

    event :bike_accepted, "Bike accepted" do
      field :shop_id, {:id, :shop}
      field :customer_id, :id, subject: :customer
      field :customer_phone, :string, personal: :customer_id
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
    command :accept_bike, %{
      shop_id: "s-1",
      customer_id: "c-17",
      customer_phone: "+1 555 0100",
      quote: 4_500
    }

    expect :bike_accepted
  end
end
```

- The mechanic has the scope of a shop, and so does `accept_bike`. A mechanic with a grant for one
  shop cannot accept a bike for another shop.
- The phone of the customer is personal. [Personal data and erasure](personal-data.md) tells what
  the engine does with it.
- `Money` checks each amount that dispatch gets. Dispatch refuses a quote of `-1` before the decision
  runs.
- The card terminal is `:inbound`: it backs the actor that records the payments.
- The text message gateway is `:outbound`: the effect only sends to it. The effect runs after the
  transaction (`:at_least_once`, the default for an effect). So it names who makes a second delivery
  harmless: the gateway, which gets the id of the event.

## Next steps

- [Personal data and erasure](personal-data.md): the subjects, and the personal fields of this
  example.
- [Authorization](../authorization.md): how a credential becomes an actor, and how a scope is
  checked.
- [Reactions](reactions.md): the effects that call an external system.
- [The compile refusals](../refusals.md#refusals-d): each refusal of a domain, and of a contract
  against its domain ([`X`](../refusals.md#refusals-x)).
- [The rules of the check](../rules.md): each warning and notice of `mix eh_os_contract.check`.
