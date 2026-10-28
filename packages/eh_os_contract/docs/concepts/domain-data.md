# Actors, personal data, values, entities and external systems

What a domain declares besides its contexts, and what the engine does with each: who acts, whose personal
data is kept and how it is erased, the value types fields are made of, the entities contracts point at, and the
systems the application depends on.

<!-- covers: entities domain.actor, domain.subject, domain.value, domain.entity, domain.external; rules orphan-actor, orphan-external-system, operation-never-called, external-direction-contradicted, value-without-implementation, free-text-not-personal, scoped-actor-with-unscoped-command -->

How a domain is divided into subdomains and contexts, and how they relate, is in [the domain](domain.md).
Every key named here is in [the domain's reference](../dsl/domain-dsl.md).

## Actors

An actor is who issues commands, asks queries or records events: a kind of person (`:human`) or a system
(`:system`). A contract names its actors in a command's or query's `by:` and an event's `recorded_by:`, and
dispatch refuses an actor the declaration does not name before anything else.

```elixir
actor :mechanic, :human, "Mechanic", context: :workshop, scope: [:shop_id]
actor :payment_terminal, :system, "Payment terminal", backed_by: :card_terminal
```

- **A human actor is a role.** EHOS grants roles to people; the role of `:mechanic` in the domain `:shop` is
  `shop.mechanic`, and a credential carries the capabilities its roles hold. Knowing who is behind a credential is
EHOS's job; the engine sees an opaque subject. [Authorization](../authorization.md) is how a credential
  becomes an actor.
- **A system actor is the application's own code**, a job or an import, acting as itself:
  `EhOsContract.Actor.system(:payment_terminal)`. It needs no credential, and may do what the declarations
  naming it allow. `backed_by:` names the external system it stands for; a human actor with `backed_by:` does
  not compile ([`D4`](../contract.md#refusals-d)).
- **`context:`** places the actor in one context. A contract of another context may not name it ([`X2`](../contract.md#refusals-x)). An
  actor without `context:` may act in any.
- **`responsibility`** inside the actor's block names what it answers for, as the material says it: prose a
  page shows and nothing runs.

### Scoped actors

`scope:` lists the dimensions a grant to this actor can be narrowed by, such as a shop, a clinic or a region. A query
or a command declared with `scope: :shop_id` is then asked of the `EhOsContract.Authorizer` with the value of
that field, and a credential whose grant holds other shops is refused; a scoped capability granted with no
values is refused too, since empty is not "all". Every actor in a scoped declaration's `by:` has to carry the
dimension ([`D10`](../contract.md#refusals-d)). What the checks do, before and after a query runs, is in
[authorization](../authorization.md).

<a id="who-may-let-whom-in"></a>

### Who may let whom in

Some people come to an application by its own work, not by a decision of the company: an accountant adds a
client company and its representative, who then signs in to see that company. `may_grant:` says which other
person actors' roles a person in this one may grant through the application:

```elixir
actor :office_employee, :human, "Office employee", may_grant: [:client]
actor :client, :human, "Client"
```

The rule goes into the manifest beside the role, and EHOS shows it to whoever approves a deployment: adding one
widens what the application asks for. Only a person grants and is granted; a rule never names the
actor itself, and rules never lead back to an actor, since `a` granting `b` while `b` grants `a` lets a holder
of `a` grant `a` through another ([`D4`](../contract.md#refusals-d)). An actor named in a rule, and one that has a
rule, has to hold a capability, or it is no role in the manifest; the manifest's generator says so.

## Subjects and personal data

A subject is a kind of person whose personal data the application keeps and may have to erase: a customer, a
patient, an employee.

```elixir
subject :customer, "Customer"
```

A contract marks which fields are personal, and whose. An identifier field names the subject it identifies
with `subject:`; a personal field names that identifier with `personal:`:

```elixir
field :customer_id, :id, subject: :customer
field :customer_phone, :string, personal: :customer_id
```

The identifier must be a required, non-personal `:id` field of the same struct, with `subject:`, and the
subject must be declared in the domain ([`F5`](../contract.md#refusals-f), [`X3`](../contract.md#refusals-x)).

**What the engine does with it.** Each subject gets a data key, 32 random bytes, the first time an event
carries its personal data. Every personal field of an event is encrypted with that key before it is
appended; the subject's id stays in the clear in its own field, so the log still says whose data it was. The
data key is stored only wrapped by a master key, which the `EhOsContract.Vault` holds: by default
`EhOsContract.Vault.Local`, which takes its master keys from configuration
(`config :eh_os_contract, EhOsContract.Vault, keys: [...]`). A node whose contracts declare personal fields
does not start without a vault that can wrap and unwrap.

**Erasing a subject** destroys its data key, so every personal field sealed with it is unreadable for good
(crypto-shredding). Nothing in the log is rewritten.

```elixir
EhOsContract.erase(:customer, "c-17", actor: actor)
```

It answers `{:ok, :erased}`, `{:ok, :no_data}` when no key was there for that id (a mistyped id, or nothing
personal was ever written for it), or `{:ok, :already_erased}`. In the first 2 cases, `erase/3` appends
`eh_os_contract.subject_erased`, with the subject's type and id and nothing personal; an erasure repeated
appends nothing. From then on:

- a personal field of that subject reads back as `%EhOsContract.Erased{subject: :customer, id: "c-17"}`, so
  `evolve/2` and every reaction have to accept one in place of the value;
- a read model that projects personal data forgets the subject;
- a command whose events would carry the subject's personal data again is refused with
  `{:error, :subject_erased}`.

The host decides who may erase: `erase/3` asks no `Authorizer`.

Personal data stays where it can be erased. A field that tells runs apart (a `correlate` field) may not be
personal ([`F4`](../contract.md#refusals-f)), nor a process manager's state field or a scope field ([`F7`](../contract.md#refusals-f)), and a publication carries none
([`D11`](../contract.md#refusals-d)): a copy on a broker cannot be erased.

## Values

A value type is a name the domain gives to data: one built-in type (`:id`, `:string`, `:integer`,
`:decimal`, `:boolean`, `:date`, `:timestamp`, an enum, a list), with a `unit` when it is a number, or a set of
fields. A contract's field takes it as its type, `field :quote, :money`.

```elixir
value :money, :integer, unit: :cents, label: "Amount"
value :bike_kind, {:enum, [city: "City bike", road: "Road bike"]}, label: "Kind of bike"

value :address, label: "Address" do
  field :street, :string
  field :city, :string
end
```

A value has a type or fields, never both and never neither ([`D3`](../contract.md#refusals-d)), and a `unit` only on an `:integer` or a
`:decimal`. A field of a value made of fields may be `personal:`, naming an identifier field of the value with
its `subject:`; a field of such a value then holds personal data wherever it is used.

Code that needs an enum's members, a select's options or a check of its own, reads them from the domain
instead of copying them: `Lending.Domain.members(:bike_kind)` is `[city: "City bike", road: "Road bike"]`,
each member with its label, or `nil` for a member written as a bare atom. A value named after an enum value
has its members; any other name raises `ArgumentError`.

### Invariants of a value

A value may declare what is true of every value of the type, each invariant with values that break it and
values that keep it:

```elixir
value :money, :integer, unit: :cents do
  invariant :not_negative, "An amount is not negative",
    violated_by: [-1],
    satisfied_by: [0, 4_500]
end
```

The domain then generates a behaviour, `<Domain>.Values.Money`, and a module bound with
`use <Domain>, value: :money` defines one function per invariant, named after it, that answers `true` or
`false`. Dispatch holds every value of the type to them: a command, or a recorded event, carrying a value that
breaks one is refused, the field named with `{:invariant, :not_negative}`; an event that a decision returns with such a value
raises. What is read back from the log is never held to them, so an invariant declared today does not make
yesterday's events unreadable. `use EhOsContract.ScenarioCase, domain: <Domain>` turns each example into a
test.

## Entities

An entity is a thing with an identity whose lifecycle the application's code or another system keeps,
outside this log: a shop, a catalogue item, an accounting period. A contract points at it by its identity, a
field of type `{:id, :shop}`.

```elixir
entity :shop, "Shop", context: :workshop, identity: :shop_id
```

It belongs to one context (required), and its `identity` is injected into its fields as a required,
non-personal `:id`. `issued_by:` names the external system that gives the identity, when one does. An
entity's fields may not be personal ([`D6`](../contract.md#refusals-d)). A contract naming an entity of another context depends on that
context. [The domain](domain.md) page shows how to declare that dependency.

When a thing's lifecycle is decided by commands of this application, it is not an entity of the domain but a
unit of a contract: an aggregate or a consistency boundary.

## External systems

An external system is one the application exchanges data with, named after the business fact it stands for
rather than after its vendor: `:card_terminal`, not the terminal's brand.

```elixir
external :sms_gateway, "Text message gateway",
  direction: :outbound,
  unavailable_looks_like: "Customers are not told their bike is ready",
  expected_latency: {5, :second} do
  operation :send_text, "Send a text message"
end
```

`direction:` is which way data flows: `:inbound` (the system only sends to the application), `:outbound` (the
application only sends to it) or `:bidirectional`. `unavailable_looks_like` and `expected_latency` are what an
outage looks like to the business and how long an answer usually takes; pages print them.

A contract uses an external in 4 ways:

- an **effect** `calls:` it, `calls: {:sms_gateway, :send_text}`. Once an external declares an `operation`,
  every call to it names one ([`X4`](../contract.md#refusals-x));
- an **event** `depends_on:` it, when the fact needs the system's answer;
- a **field** is `issued_by:` it, when the system gives its value, such as an invoice number or a parcel's
  tracking number;
- a **system actor** is `backed_by:` it, when the system acts in the application.

An external may also be one end of a directed relation; the other end is then a context. A name that is both a context
and an external does not compile ([`D1`](../contract.md#refusals-d)).

## An example

A bike workshop: a mechanic accepts a bike for repair with a quote, a text tells the customer, and the card
terminal records the payment.

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

- The mechanic is scoped by shop, and `accept_bike` is too: a mechanic's grant for one shop does not accept
  bikes for another.
- The customer's phone is sealed with the customer's key; after `EhOsContract.erase(:customer, "c-17", …)`
  every `bike_accepted` of that customer still says which shop, which customer id and what quote, and no
  longer which phone.
- `Money` checks every amount dispatch sees: a quote of `-1` is refused before the decision runs.
- The card terminal is `:inbound`: it backs the actor that records payments. The text gateway is `:outbound`:
  the effect only sends to it. The effect is delivered after the transaction (`:at_least_once`,
  the default for an effect), so it names who makes a second delivery harmless: the gateway, which receives
  the event's id.

## What the compiler refuses

The full table is in [Writing a domain and a contract](../contract.md). For what this page covers:

- **[`D1`](../contract.md#refusals-d)**: a name not snake_case, declared twice, or both a context and an external; an operation or a
  responsibility not snake_case or declared twice.
- **[`D3`](../contract.md#refusals-d)**: a value with both or neither of a type and fields, a `unit` on a value that is not numeric, an
  undeclared `context:`, values in a cycle.
- **[`D4`](../contract.md#refusals-d)**: an actor's name not snake_case, a human actor with `backed_by`, `backed_by` naming no external,
  an undeclared `context:`; a `may_grant:` on a system actor, or naming the actor itself, a system, an undeclared
  actor or one twice, and rules that lead back to an actor.
- **[`D6`](../contract.md#refusals-d)**: `{:id, entity}` naming an undeclared entity; an entity with an undeclared context, or a field
  that is personal or holds personal data.
- **[`D8`](../contract.md#refusals-d)**: `issued_by:` naming what is not an external of the domain.
- **[`D9`](../contract.md#refusals-d)**: a value invariant without examples of both kinds, an example not of the value's type, or one
  that keeps an invariant and that another invariant lists as breaking.
- **[`D10`](../contract.md#refusals-d)**: a scoped query or command whose `by:` names an actor that does not carry the scope.
- **[`F5`](../contract.md#refusals-f)**: `personal:` naming what is not a required, non-personal `:id` field with `subject:` in the same
  struct; a personal field whose type holds personal data of its own.
- **[`X2`](../contract.md#refusals-x)**, **[`X3`](../contract.md#refusals-x)**, **[`X4`](../contract.md#refusals-x)**: `by:` or `recorded_by:` naming no actor of the domain or one of another
  context; a type, an entity or a `subject:` the domain does not declare; `calls:`, `depends_on:` or
  `issued_by:` naming no external, or an operation the external does not declare.

## What `mix eh_os_contract.check` reports

From [the rules](../rules.md):

- **`orphan-actor`** (warning): no command's or query's `by:`, no event's `recorded_by:` and no process's
  `accountable` names the actor. A scenario's actor does not count. Remove it, or write the contract that
  gives it work.
- **`scoped-actor-with-unscoped-command`** (warning): an actor with scope dimensions is in the `by:` of a
  command without `scope`, so that command's capability is application-wide for it. Declare the command's
  `scope` when it acts on one of those dimensions, or name another actor when application-wide authority is
  deliberate.
- **`free-text-not-personal`** (notice): a `:string` field of an event, or text inside a list or a value of
  one, is not `personal:`. Text is what a person typed, and unless it is personal it stays in the log as
  written after its subject is erased. Mark it personal, or give a code, a number or a choice a type of its
  own: an `:id`, an enum, or a value declared `code: true`, whose invariants, or those of a value it names, pin
  its form. A code that identifies a person, such as a national id number, is still marked personal.
- **`value-without-implementation`** (warning): a value declares invariants and no module checks them, so
  dispatch raises on every value of it. Add a module with `use <Domain>, value: <name>`. The check reports it only once
  some contract of the domain is implemented.
- **`owner-view-without-label`** (notice): a value, or a member of its enum written as a bare atom, has no
  label, so a business owner reading the model would see its name in the code. Write the member as
  `card: "Card"`, and give the value `label:`.
- **`orphan-external-system`** (warning): no actor is backed by the external, no relation ends at it, no
  field or entity is issued by it, no effect calls it and no event depends on it.
- **`operation-never-called`** (warning): an operation of an external is named in no effect's `calls:`.
  Asked only of a system some effect calls. A system no effect calls is reported by
  `orphan-external-system` instead, when nothing else uses it either.
- **`external-direction-contradicted`** (warning): an external declared `direction: :outbound`, which only
  receives from the application, issues a field's value or an entity's identity, or backs an actor: both bring
  what the system says into the application. Declare it `:bidirectional` when it also answers. A call says
  nothing either way, since an effect calls a system to send and to fetch alike.
