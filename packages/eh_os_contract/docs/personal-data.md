# Personal data and erasure

This page tells how a domain and a contract mark personal data, and what the engine does when a
person asks to be erased. It is for a developer who keeps personal data in the log, and for a person
who is responsible for that data. [The glossary](glossary.md) defines each word of the contract
language.

<!-- covers: entities domain.subject; rules free-text-not-personal -->

## What is a subject?

A subject is a kind of person whose personal data the application keeps, and may have to erase.
Examples: a customer, a patient, an employee. The domain declares each subject:

<!-- in: Concepts.PersonalData.Domain -->
```elixir
subject :customer, "Customer"
```

## How does a contract mark personal data?

A contract marks which fields are personal, and whose data they hold:

- An identifier field names the subject that it identifies, with `subject:`.
- A personal field names that identifier field, with `personal:`.

<!-- in: Concepts.PersonalData.Contracts.Repairs, event :bike_accepted -->
```elixir
field :customer_id, :id, subject: :customer
field :customer_phone, :string, personal: :customer_id
```

The identifier must be a required `:id` field of the same struct, with `subject:`, and it cannot be
personal itself. The domain must declare the subject ([`F5`](refusals.md#refusals-f),
[`X3`](refusals.md#refusals-x)).

A field of a value of fields can be personal too. It names an identifier field of the same value.
Then the field holds personal data in each place that uses the value.

## Where can personal data not go?

The engine keeps personal data in the log only where an erasure reaches it. So some fields cannot
be personal:

- A field that tells the runs of a process apart, a `correlate` field
  ([`F4`](refusals.md#refusals-f)).
- A field of the state of a process manager, or a scope field ([`F7`](refusals.md#refusals-f)).
- A field of a publication ([`D11`](refusals.md#refusals-d)). A copy on a broker cannot be erased.

The check gives a notice for a `:string` field of an event that is not personal
(`free-text-not-personal`). It also reads the text in a list or a value of an event. A person
typed this text, so it can hold personal data. If it is not personal, it stays in the log after the
erasure of its subject. Do one of these:

- Mark the field personal.
- If the field holds a code, a number or a choice, give it a type of its own. Use an `:id`, an enum,
  or a value declared `code: true` whose invariants fix its form.

A code that identifies a person, such as a national id number, is personal data. Mark it personal.

## What happens to personal data when a subject is erased?

![Dispatch encrypts personal fields with the key of their subject; erasure deletes the key, so the database holds no key that can read those events.](img/personal-data-erasure.svg)

1. The first time an event carries personal data of a subject, dispatch makes a data key for the
   subject: 32 random bytes. It asks the `EhOsContract.Vault` to wrap the data key with a master
   key.
2. Dispatch stores the data key only in its wrapped form, in the table of subject keys.
3. Dispatch encrypts each personal field of the event with the data key, and appends the event. The
   id of the subject stays readable in its own field, so the log still tells whose data it was.
4. The application calls `EhOsContract.erase/3`. It deletes the data keys of the subject. The
   engine does not change the events in the log.
5. In the same transaction, `erase/3` appends the event `eh_os_contract.subject_erased`. This event
   holds the type and the id of the subject, and no personal data.
6. Each read model delivered `:in_transaction` that holds personal data forgets the subject, with its
   `forget/2`. A read model delivered `:at_least_once` gets the same event later, in order.
7. From then on, a personal field of that subject reads back as `%EhOsContract.Erased{}`.

This is called crypto-shredding: the data stays in the log, and the database holds no key that can
read it. [What does an erasure not reach?](#what-does-an-erasure-not-reach) tells where a key can
still be.

<!-- not compiled: a call in the host's code -->
```elixir
EhOsContract.erase(:customer, "c-17", actor: actor)
```

`erase/3` gives one of these answers:

| Answer | When | Appends `subject_erased` |
| --- | --- | --- |
| `{:ok, :erased}` | The subject had a data key. | Yes |
| `{:ok, :no_data}` | No data key had that id: the id is wrong, or no personal data was written for it. | Yes |
| `{:ok, :already_erased}` | The subject was erased before. | No |

After an erasure:

- A personal field of the subject reads back as `%EhOsContract.Erased{subject: :customer, id:
  "c-17"}`. So `evolve/2` and each reaction must accept this struct in place of the value.
- Dispatch refuses a command whose events carry personal data of the subject again, with
  `{:error, :subject_erased}`. A new key would make new data readable again.
- This is also true after `{:ok, :no_data}`. So check the id before you erase: an erasure with a
  wrong id blocks the personal data of the person who gets that id later.

`erase/3` does not ask the `EhOsContract.Authorizer`. Your application decides who can erase.

## What must the application configure?

A node whose contracts declare personal fields does not start without a vault that can wrap and
unwrap keys.

- The default vault is `EhOsContract.Vault.Local`. It takes its master keys from the configuration:
  `config :eh_os_contract, EhOsContract.Vault, keys: [...]`.
- To keep the master keys in a key management service (KMS), write a module of the
  `EhOsContract.Vault` behaviour, and configure it: `config :eh_os_contract, vault: MyApp.KmsVault`.

[Getting started](getting-started.md#configure-and-start) tells where to put the key.

<a id="rotate-a-master-key"></a>

## How does the engine use more than one master key?

The first master key of the list wraps each new data key. Each wrapped data key names the master key
that wrapped it, and the engine unwraps it with that key. So you can change the master key in three
deploys:

1. Add the new key after the current key, and deploy. Each node can now unwrap what the new key
   wraps.
2. Move the new key to the first place, and deploy.
3. Wrap each data key again with the new key: run `mix eh_os_contract.rewrap`. A release has no
   `mix`, so call `EhOsContract.Personal.rewrap!(MyApp.Repo)` there. Then remove the old key, and
   deploy.

Do not put the new key first in one deploy. If you do, the nodes that still run the old configuration
cannot read what the new nodes write, until the rollout ends.

<a id="what-does-an-erasure-not-reach"></a>

## What does an erasure not reach?

- **Backups.** An erasure deletes the data key from the database, not from your backups. A backup, a
  WAL archive or a replica still holds the wrapped key. A person who also has the master key can
  read the data of the subject.
- **Read models.** A read model keeps its copy of personal data as plain text in your tables.
  `forget/2` deletes it from the live table. Only your backup policy reaches the backups of that
  table.
- **A read model that has not read the erasure yet.** A read model delivered `:at_least_once` keeps
  the plain text until its subscription reads `subject_erased`. If the subscription stops, the
  data stays. `mix eh_os_contract.subscriptions` shows where each subscription is.

So [change the master key](#rotate-a-master-key), and then destroy the old key, at an interval that
is not longer than the time that you keep backups. Do not destroy a master key that still wraps a data
key. If you do, the personal data of each subject whose key it wraps becomes unreadable. Or keep the table of subject keys out of the backups of the log. Each choice has a cost: a
backup older than a destroyed master key cannot unwrap the data of any subject. A backup restored
without the subject keys cannot either.

## Why can an erasure make other appends wait?

An erasure holds the lock that each append to the log takes. A read model delivered
`:in_transaction` that holds personal data forgets inside this transaction. While it forgets, each
other append waits. So index the column that its `forget/2` uses to find the subject.

## An example

A bike workshop keeps the phone number of each customer, to tell them when the bike is ready.

```elixir
defmodule Concepts.PersonalData.Domain do
  use EhOsContract.Domain, name: :personal_data_page, language: :en

  subdomain :repairs, "Repairs", type: :core
  context :workshop, "Workshop", subdomain: :repairs

  actor :mechanic, :human, "Mechanic", context: :workshop

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
    end

    event :bike_accepted, "Bike accepted" do
      field :customer_id, :id, subject: :customer
      field :customer_phone, :string, personal: :customer_id
    end
  end

  scenario "a bike is accepted" do
    command :accept_bike, %{customer_id: "c-17", customer_phone: "+1 555 0100"}
    expect :bike_accepted
  end
end
```

After `EhOsContract.erase(:customer, "c-17", actor: actor)`, each `bike_accepted` of that customer
still tells which repair and which customer id. It no longer tells which phone number.

## Next steps

- [Actors, values, entities and external systems](domain-data.md): the other declarations of a
  domain.
- [Reading](reading.md): read models, and how `forget/2` works.
- [The configuration](configuration.md): the keys of the vault.
- [The compile refusals](refusals.md), families F, D and X: each refusal about personal data.
