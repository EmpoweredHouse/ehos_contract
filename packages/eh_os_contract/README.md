# EhOsContract

A contract per business process, and two things built on it: event dispatch for an
event-driven Elixir application, and a continuous check that what happened is what
the contract says should.

You declare a process as an Elixir module — its events, the run they belong to,
the promises it makes about them. `EhOsContract.emit/4` refuses anything the contract
does not declare and writes the rest to an event log; handlers react to those events,
synchronously inside the emitting transaction or asynchronously through an Oban job
inserted in that same transaction. Then EhOsContract compares the log with the contract
and answers four questions about the difference:

- which declared paths have never been traversed,
- which transitions happened without being declared,
- which `trace` assertions are being violated,
- which contract version is deployed, and since when.

Nothing else. Performance belongs to your APM, errors to your error tracker, and
the state of your business to your own application. A tool that starts answering
"which customer has not closed July" has become a second, worse copy of the screen
you already have.

## Installation

Not on Hex yet, so from git. The package lives in a subdirectory of its repository,
hence `sparse:`; `mix.lock` pins the commit.

```elixir
def deps do
  [
    {:eh_os_contract,
     git: "https://github.com/EmpoweredHouse/eh-os-contract.git",
     sparse: "packages/eh_os_contract"}
  ]
end
```

EhOsContract owns its tables and ships the migration for them, the same shape Oban does.
Generate a migration and call into it:

```elixir
defmodule MyApp.Repo.Migrations.AddEhOsContract do
  use Ecto.Migration

  def up do
    Oban.Migration.up()
    EhOsContract.Migrations.up()
  end

  def down do
    EhOsContract.Migrations.down()
    Oban.Migration.down()
  end
end
```

Oban's tables are Oban's; `EhOsContract.Migrations` deliberately does not wrap them, so an
application that already runs Oban for its own work is not surprised by an upgrade
it did not ask for. When a later release raises `EhOsContract.Migrations.current_version/0`,
the upgrade is another generated migration rather than an edit to the one above.

Then tell EhOsContract which applications hold your contracts, and which repo to use:

```elixir
config :eh_os_contract,
  applications: [:my_app],
  repo: MyApp.Repo
```

And add EhOsContract to your supervision tree, after the repo and Oban. At boot it
scans the running binary for contracts and handlers and records which contract
version is deployed; without it the report has nothing to compare against.

```elixir
children = [
  MyApp.Repo,
  {Oban, Application.fetch_env!(:my_app, Oban)},
  EhOsContract,
  MyAppWeb.Endpoint
]
```

The child is a supervisor: it also starts one runner per consumer a v2 contract feeds
from the log after the transaction. A test cannot use those runners, because they would
not see the rows of its sandbox transaction, so in `config/test.exs`:

```elixir
config :eh_os_contract, subscriptions: :manual
```

and a test that needs them runs `EhOsContract.Testing.drain/1`.

A contract that declares personal data (`personal:` on a field, v2 §14) has those fields
encrypted in the log, each subject under its own data key, and the data keys wrapped by a
master key. Give the master keys in `config/runtime.exs`, 32 bytes each in Base64, the
current one first:

```elixir
config :eh_os_contract, EhOsContract.Vault,
  keys: [{"2026-09", System.fetch_env!("EH_OS_CONTRACT_KEK")}]
```

Without one the host does not boot, rather than failing on the first command that carries
personal data. To rotate, put the new key first and keep the old one after it, deploy, run
`mix eh_os_contract.rewrap`, and then drop the old key. A KMS goes behind the
`EhOsContract.Vault` behaviour: `config :eh_os_contract, vault: MyApp.KmsVault`.

Erasing a subject deletes its data key from the database, not from your backups: a
backup, a WAL archive or a replica still holds the key, wrapped, and anyone who also
has the master key can open the subject's data. Retire and destroy master keys on a
cadence no longer than you keep backups, or keep the key store out of the log's backups.

## A contract

```elixir
defmodule MyApp.Contracts.Onboarding do
  use EhOsContract.Contract

  event :application_received,
    label: "Application received",
    payload: %{application_id: :id},
    identity: [:application_id],
    process: :onboarding,
    stage: :intake

  event :application_approved,
    label: "Application approved",
    payload: %{application_id: :id},
    process: :onboarding,
    stage: :decision,
    terminal: true

  command :submit_application,
    label: "Submit an application",
    process: :onboarding,
    principals: [:human],
    payload: %{application_id: :id}

  process :onboarding,
    label: "Onboarding",
    stages: [:intake, :decision],
    instance: [:application_id],
    accountable: "Head of onboarding"

  trace :decided_within_a_week do
    from :application_received
    eventually :application_approved, within: {7, :day}
  end
end
```

Read the `trace` aloud: *after an application is received, within seven days it is
approved.* That sentence is what a process owner confirms or corrects, and it is
the reason the declarations carry a `label` in the client's own language.

The full key reference — every declaration, every key, and the list of things that
will not compile — is generated from `EhOsContract.Contract.schema/0` and lives in
[`docs/contract.md`](docs/contract.md), inside this package.

## Emitting and reacting

```elixir
EhOsContract.emit(MyApp.Contracts.Onboarding, :application_received, %{application_id: id})

defmodule MyApp.Onboarding.OnApplicationReceived do
  use EhOsContract.Handler,
    contract: MyApp.Contracts.Onboarding,
    event: :application_received,
    async: true

  @impl EhOsContract.Handler
  def handle(%{application_id: id}, ctx) do
    # ctx.idempotency_key: the queue delivers at least once
    MyApp.Mailer.acknowledge(id, ctx.idempotency_key)
    :ok
  end
end
```

A handler for an event the contract does not declare does not compile. Neither does
an asynchronous one whose event has no `identity:` to derive an idempotency key from.

## What you get

```
mix eh_os_contract.check      whole-program checks the compiler cannot make
mix eh_os_contract.report     the conformance report for a period
mix eh_os_contract.graph      the declared graph, and declared versus observed
mix eh_os_contract.trace      assertion verdicts, per run
mix eh_os_contract.brief      one process, rendered for the person who owns it
```

`mix eh_os_contract.check` is the one to put in CI. It refuses a build for the things that are
unambiguously wrong — a rule whose function does not exist, two contracts claiming
one event name — and reports as warnings or notices the things that need a person's
judgment.

## What it deliberately does not do

It does not know what a company is, what a tenant is, or what any of your fields
mean, and it does not know who anybody is: an event's actor is an opaque subject the
emitting application supplies, and authentication, roles and tenants stay on that
application's side. Every payload type describes the shape of a value rather than
the name of a thing. A library that knows one client's domain is a library for one
client.

## Licence

Apache 2.0.
