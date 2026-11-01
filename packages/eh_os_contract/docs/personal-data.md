# How does the engine keep and erase personal data?

<!-- covers: entities domain.subject; rules free-text-not-personal -->

This page tells how a contract marks personal data, how the engine keeps it, and what an erasure
does and does not reach. It is for a developer who writes a contract with personal data, and for a
person who answers for the protection of that data. [The glossary](glossary.md) defines each word
in italics.

## What is a subject?

A *subject* is a kind of person whose personal data the application keeps, and may have to erase.
Examples: a customer, a patient, an employee. The domain declares each subject:

<!-- in: Concepts.PersonalData.Domain -->
```elixir
subject :customer, "Customer"
```

## How does a contract mark personal data?

A contract marks which fields are personal, and whose data they hold. A field that identifies the
subject names it with `subject:`. A *personal field* names that identifier with `personal:`:

<!-- in: Concepts.PersonalData.Contracts.Repairs, event :bike_accepted -->
```elixir
field :customer_id, :id, subject: :customer
field :customer_phone, :string, personal: :customer_id
```

- The identifier is a required `:id` field of the same struct, with `subject:`. It is not personal
  itself ([`F5`](refusals.md#refusals-f)).
- The domain declares the subject ([`X3`](refusals.md#refusals-x)).

<a id="personal-data-in-a-value"></a>

A field of a value with fields can also be personal. It names an identifier field of the same value,
which has `subject:`. Then each field of that value type holds personal data, in each place where a
contract uses it. The compiler refuses a personal field whose type holds personal data of its own
([`F5`](refusals.md#refusals-f)).

### Which text must be personal?

If a `:string` field of an event is not personal, the check gives the notice
`free-text-not-personal`. The check also reads text in a list or in a value of the event. A
`:string` is text that a person typed. If it is not personal, it stays in the log as it was written,
also after the subject is erased.

- If the text is personal, mark it `personal:`.
- If the text is a code, a number or a choice, give it a type of its own. Use an `:id`, an enum, or
  a value with `code: true`. The invariants of that value, or of a value that it names, fix its form.
- A code that identifies a person, such as a national id number, is personal. Mark it `personal:`.

### Where can personal data not go?

The engine keeps personal data only where it can erase it. So the compiler refuses personal data in
these places:

- a field that tells the runs of a process manager apart, a `correlate` field
  ([`F4`](refusals.md#refusals-f));
- a state field of a process manager, or a scope field of a command or a query
  ([`F7`](refusals.md#refusals-f));
- a publication ([`D11`](refusals.md#refusals-d)): the engine cannot erase a copy on a broker.

## What does the engine do with a personal field?

The engine encrypts each personal field with a key for its subject.

- A subject gets a *data key* the first time that an event carries its personal data. A data key is
  32 random bytes.
- Dispatch encrypts each personal field of an event with that data key, before it appends the event.
- The id of the subject stays in clear text, in its own field. So the log still tells whose data it
  was.
- The engine stores a data key only wrapped by a *master key*. The database alone cannot decrypt a
  personal field.
- The `EhOsContract.Vault` holds the master keys. The default vault, `EhOsContract.Vault.Local`,
  takes them from the configuration: `config :eh_os_contract, EhOsContract.Vault, keys: [...]`.
- If the contracts of a node declare personal fields, the node does not start without a configured
  vault. `EhOsContract.Vault.Local` reads the configuration of the keys, and does not try a key.
  Another vault answers through its `check/0`.
- The node also does not start if a read model that projects personal data has no `forget/2`.

[Manage the keys and the backups of personal data](master-keys.md) tells how to rotate a master key, and how to use a key
management service.

<a id="what-happens-when-a-subject-is-erased"></a>

## What happens when a subject is erased?

To erase a subject, the engine destroys its data key. This is called crypto-shredding. Each
personal field that the key encrypted becomes unreadable for good, and the engine does not rewrite
the log. You cannot undo an erasure.

<!-- not compiled: a call in the host's code -->
```elixir
EhOsContract.erase(:customer, "c-17", actor: actor)
```

![Dispatch encrypts a personal field with the data key of its subject; an erasure destroys that key, records the erasure, and the read models forget the subject.](img/personal-erasure.svg)

1. The application dispatches a command that carries personal data of a subject.
2. The vault wraps the data key of the subject with the current master key. The engine stores only
   the wrapped key.
3. Dispatch encrypts each personal field with the data key, and appends the event to the log.
4. `erase/3` destroys the data key of the subject.
5. `erase/3` appends the event `eh_os_contract.subject_erased`, with the type and the id of the
   subject, and nothing personal.
6. The read models that project personal data get this event, and forget the subject through their
   `forget/2`. A read model delivered `:in_transaction` forgets in the transaction of the erasure.
   Another read model gets the event from the log, in order.
7. From now on, a personal field of the subject reads back as
   `%EhOsContract.Erased{subject: :customer, id: "c-17"}`. `evolve/2` and each reaction must accept
   this struct in place of the value.

After the erasure, dispatch refuses a command whose events carry personal data of the subject again.
It answers `{:error, :subject_erased}`. This is also true after the result `:no_data`: the engine
records the erasure of the id in each case.

`erase/3` returns one of three results:

| Result | When | Appends `subject_erased` |
| --- | --- | --- |
| `{:ok, :erased}` | The engine deleted the data key. | yes |
| `{:ok, :no_data}` | The engine found no data key for the id. Either no personal data was written for it, or the id is wrong. | yes |
| `{:ok, :already_erased}` | The subject was erased before. | no |

The application decides who can erase a subject: `erase/3` does not ask the
`EhOsContract.Authorizer`. Check the id before you erase. An id of another real subject erases that
subject.

### An erasure holds the append lock

Index the column by which `forget/2` finds the subject. An erasure runs in one transaction, which
holds the lock that each append to the log takes. A read model delivered `:in_transaction` that
projects personal data forgets inside this transaction. While it forgets, each other append to the
log waits.

<a id="what-does-an-erasure-not-reach"></a>

## What does an erasure not reach?

An erasure deletes the data key from the database. It does not delete it from your backups.

- A backup, a WAL archive or a delayed replica still holds the wrapped data key. A person who also
  has the master key can read the data of the subject.
- So destroy each master key within the time that you keep backups.
  [Manage the keys and the backups of personal data](master-keys.md) tells how to rotate a key.
- After that, a backup cannot unwrap a data key that the destroyed master key wraps. Accept this
  cost, or keep those backups shorter.
- The data keys are in the table `eh_os_contract_subject_keys`, and the erasures in
  `eh_os_contract_erasures`. Restore both with the log, from the same moment. If they do not agree,
  the engine raises on a personal field of a subject that has no key and no erasure. It does not
  read the field as erased.
- A backup that is older than an erasure holds the data key of the subject, and no record of the
  erasure. If you restore it, the engine reads the personal data of the subject again, and accepts
  new personal data for it. [Restore a backup older than an erasure](master-keys.md#restore-a-backup-older-than-an-erasure)
  tells what to do.
- You can keep the table of data keys out of the backups of the log, so that no backup holds a data
  key. Then you cannot restore the personal data from those backups: the engine raises on it.

An erasure also does not reach these copies:

- A read model keeps its copy of personal data as clear text, in your tables. `forget/2` deletes it
  from the live table. Only your backup policy reaches the backups of that table.
- `erase/3` reaches the read models of the applications in `config :eh_os_contract, applications:`.
  A read model of a contract outside them keeps its copy.
- A read model delivered `:at_least_once` keeps its copy until it reads the event of the erasure.
  If `mix eh_os_contract.subscriptions --skip` moves it past that event, it keeps the copy. A
  `--reset` rebuilds it, and the replay forgets.
- An effect that already sent personal data to an external system, such as a text message gateway,
  cannot take it back.

## An example

A bike workshop keeps the phone of each customer. The phone is personal, so an erasure of the
customer makes it unreadable. The customer id and the quote stay readable.

```elixir
defmodule Concepts.PersonalData.Domain do
  use EhOsContract.Domain, name: :personal_data_page, language: :en

  subdomain :repairs, "Repairs", type: :core
  context :workshop, "Workshop", subdomain: :repairs

  actor :mechanic, :human, "Mechanic"

  subject :customer, "Customer"
end

defmodule Concepts.PersonalData.Contracts.Repairs do
  use EhOsContract.Contract,
    domain: Concepts.PersonalData.Domain,
    context: :workshop,
    id: "personal_data_page.repairs"

  aggregate :repair, "Repair of a bike" do
    identity :repair_id

    command :accept_bike, "Accept a bike for repair", by: :mechanic, emits: :bike_accepted do
      field :customer_id, :id, subject: :customer
      field :customer_phone, :string, personal: :customer_id
      field :quote, :integer
    end

    event :bike_accepted, "Bike accepted" do
      field :customer_id, :id, subject: :customer
      field :customer_phone, :string, personal: :customer_id
      field :quote, :integer
    end
  end

  scenario "a bike is accepted" do
    command :accept_bike, %{customer_id: "c-17", customer_phone: "+1 555 0100", quote: 4_500}
    expect :bike_accepted
  end
end
```

After `EhOsContract.erase(:customer, "c-17", actor: actor)`, each `bike_accepted` of that customer
still gives the customer id and the quote. Its `customer_phone` is `%EhOsContract.Erased{}`.

## Next steps

- [Manage the keys and the backups of personal data](master-keys.md): rotate a master key, or keep the keys in a key
  management service.
- [What are actors, values, entities and external systems?](domain-data.md): the other declarations
  of a domain.
- [Reading](reading.md): read models, and their `forget/2`.
- [The compile refusals](refusals.md#refusals-f): each refusal of a field, personal fields
  included.
