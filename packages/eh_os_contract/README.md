# EhOsContract

A contract per business process, and 2 things built on it: an event-sourced application that
dispatches through the contract, and a continuous check that what happened is what the contract says
should.

You write the process down as 2 Elixir modules, in the manner of [ESDM](https://www.esdm.io): a
**domain** (the words, the contexts, the actors and the systems it depends on) and a **contract** (the
units that decide, their commands, events and invariants, what reacts to them, what is read, and the
promises the process owner agreed to). The compiler refuses a model that contradicts itself and code that
contradicts the model. `EhOsContract.dispatch/3` runs a command through it: who may issue it, what its
fields must be, what the implementation decides. Nothing the contract does not declare is appended to
the log, which the engine owns. Then EhOsContract compares the log with the contract and answers 4
questions about the difference:

- which declared steps have never been taken,
- what happened that the contract does not declare,
- which promises are being broken,
- which contract version is deployed, and since when.

Nothing else. Performance belongs to your APM, errors to your error tracker, and the state of your
business to your own application, which the library helps you build, through read models and queries,
but does not show on its dashboard. A tool that starts answering "which customer has not closed July" has
become a second, worse copy of the screen you already have.

New here: [the introduction](docs/introduction.md) says what the library is for and what it is not,
[getting started](docs/getting-started.md) goes from this page to a contract whose scenarios run as tests,
and the concepts explain each kind of declaration, from [the domain](docs/concepts/domain.md) to
[processes](docs/concepts/process.md).

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

The rules between a contract, its domain and its siblings are a Mix compiler, because those
references record no compile dependency. Register it after Elixir's, in `mix.exs`:

```elixir
compilers: Mix.compilers() ++ [:eh_os_contract]
```

And add EhOsContract to your supervision tree, after the repo and Oban. At boot it
scans the running binary for contracts and their implementations and records which
contract version is deployed; without it the report has nothing to compare against.

```elixir
children = [
  MyApp.Repo,
  {Oban, Application.fetch_env!(:my_app, Oban)},
  EhOsContract,
  MyAppWeb.Endpoint
]
```

The child is a supervisor: it also starts one runner per consumer a contract feeds
from the log after the transaction. A test cannot use those runners, because they would
not see the rows of its sandbox transaction, so in `config/test.exs`:

```elixir
config :eh_os_contract, subscriptions: :manual
```

and a test that needs them runs `EhOsContract.Testing.drain/1`.

Every append takes one lock, held to the end of its transaction, which is what keeps the log's order. So
whatever runs `:in_transaction` holds every other write while it runs, and belongs in the database only. In
the Ecto sandbox a test's transaction lasts the whole test, so 2 `async: true` tests that write the log
wait for each other, and the one waiting fails once the other outlasts the repo's timeout: mark them
`async: false`.

A contract that declares personal data (`personal:` on a field) has those fields
encrypted in the log, each subject under its own data key, and the data keys wrapped by a
master key. Give the master keys in `config/runtime.exs`, 32 bytes each in Base64, the
current one first:

```elixir
config :eh_os_contract, EhOsContract.Vault,
  keys: [{"2026-09", System.fetch_env!("EH_OS_CONTRACT_KEK")}]
```

Without one the host does not boot, rather than failing on the first command that carries
personal data. A data key is wrapped by the first master key and unwrapped by the one it names, so
rotate in 3 deploys: add the new key **after** the current one and deploy, so that every node can
unwrap what the new key will wrap; move it first and deploy; then rewrap every data key with it
(`mix eh_os_contract.rewrap`, or `EhOsContract.Personal.rewrap!(MyApp.Repo)` from a release, which has
no `mix`) and drop the old key in the third. Putting the new key first in one step leaves the nodes
still on the old configuration unable to read what the new ones write until the rollout ends. A KMS
goes behind the `EhOsContract.Vault` behaviour: `config :eh_os_contract, vault: MyApp.KmsVault`.

To erase a subject, that is, a person who asked for their data to be removed:

```elixir
EhOsContract.erase(:member, "member-17", actor: actor)
```

It deletes the subject's data key, records the erasure and appends an event saying so; the
subject's personal fields read back as `%EhOsContract.Erased{}` from then on, everything else
stays, and a command that would write their personal data again is refused with
`{:error, :subject_erased}`. It answers `{:ok, :erased}`, `{:ok, :already_erased}`, or
`{:ok, :no_data}` when no data key was there for that id. That case is recorded all the same, but worth
reporting, since a mistyped id erases nobody. Who may erase is yours to decide: the engine asks no authorizer.
A read model that projects personal data keeps a copy in your tables, so it defines
`forget(subject_type, subject_id)`; without it the host does not boot. One delivered in the
transaction forgets inside the erasure, under the lock every append takes, so index the
column its `forget/2` looks the subject up by.

Erasing a subject deletes its data key from the database, not from your backups: a
backup, a WAL archive or a replica still holds the key, wrapped, and anyone who also
has the master key can open the subject's data. Retire and destroy master keys on a
cadence no longer than you keep backups, or keep the key store out of the log's backups.
Either has a price at restore: a backup older than the destroyed master key, or restored without
the key store, cannot unwrap any subject's data, erased or not. And a read model's copy of personal
data is plain text in your own tables, so its backups hold it whatever happens to the keys:
`forget/2` reaches the live table, and only your backup policy reaches the rest.

## A domain, a contract and a process

```elixir
defmodule MyApp.Domain do
  use EhOsContract.Domain, name: :my_app, language: :en

  subdomain :core, "Core", type: :core

  context :onboarding, "Onboarding", subdomain: :core

  actor :applicant, :human, "Applicant"
  actor :reviewer, :human, "Reviewer"
end

defmodule MyApp.Contracts.Onboarding do
  use EhOsContract.Contract, domain: MyApp.Domain, context: :onboarding, id: "my_app.onboarding"

  aggregate :application, "Application" do
    identity :application_id

    command :submit_application, "Submit an application",
      by: :applicant,
      emits: :application_received

    command :approve_application, "Approve an application",
      by: :reviewer,
      emits: :application_approved

    event :application_received, "Application received"
    event :application_approved, "Application approved"
  end
end

defmodule MyApp.Processes.ApplicationReview do
  use EhOsContract.Process,
    id: "my_app.application_review",
    domain: MyApp.Domain,
    label: "Reviewing an application",
    accountable: :reviewer

  correlate :application_id

  stage :review, "Review",
    include: [{MyApp.Contracts.Onboarding, [:application_received, :application_approved]}]

  ends_on :application_approved

  promise :decided_within_a_week do
    from :application_received
    eventually :application_approved
    within {7, :day}
  end
end
```

Read the promise aloud: *after an application is received, within 7 days it is approved.* That
sentence is what a process owner confirms or corrects, and it is the reason every declaration carries a
label in the words of the people in the process.

## The code that decides

A contract names no implementation. A module binds to one of its declarations and gets the structs and
the behaviour the contract generates:

```elixir
defmodule MyApp.Onboarding.Application do
  use MyApp.Contracts.Onboarding, aggregate: :application

  @impl true
  def submit_application(%SubmitApplication{application_id: id}, _state),
    do: emit(%ApplicationReceived{application_id: id})

  @impl true
  def approve_application(%ApproveApplication{application_id: id}, _state),
    do: emit(%ApplicationApproved{application_id: id})
end
```

and a command goes through dispatch, with the actor your application authenticated:

```elixir
alias MyApp.Contracts.Onboarding

EhOsContract.dispatch(Onboarding, %Onboarding.Commands.SubmitApplication{application_id: id},
  actor: actor
)
```

An implementation that emits an event its command does not declare, or leaves a callback out, does not
compile. How to write both modules, and every refusal with its code, is in
[`docs/contract.md`](docs/contract.md); every key of the DSLs is in the reference generated from them,
[the domain](docs/dsl/domain-dsl.md), [the contract](docs/dsl/contract-dsl.md) and
[the process module](docs/dsl/process-dsl.md). Who the actor is, and how a
credential becomes one, is in [`docs/authorization.md`](docs/authorization.md).

## What you get

```
mix eh_os_contract.check          whole-program checks over the contracts and their implementations
mix eh_os_contract.report         the conformance report for a period: the four questions, one page
mix eh_os_contract.graph          a contract, a process or a domain as a graph.v1 document, every one at once, or the log over one
mix eh_os_contract.view           the domain as a tree: contexts, contracts, units, consumers and processes
mix eh_os_contract.glossary       the domain's ubiquitous language
mix eh_os_contract.pages          the domain, its contracts and processes as Markdown pages, one per element
mix eh_os_contract.schema         every event's fields by version, recorded; a changed version refused
mix eh_os_contract.subscriptions  where each subscription stands, and a way past a poison event
mix eh_os_contract.rewrap         the subjects' data keys, rewrapped with the current master key
```

`mix eh_os_contract.check` is the one to put in CI. Its findings are warnings and notices, each under a
stable name [listed with its reason](docs/rules.md); `--warnings-as-errors` fails the build on a warning.
What is unambiguously wrong never gets that far: it does not compile. Beside it in CI goes
`mix eh_os_contract.schema --check`, which fails when an event's fields changed, or the event went, without
a new version.

## What it deliberately does not do

It does not know what a company is, what a tenant is, or what any of your fields mean, and it does not
know who anybody is: an actor is an opaque subject with the capabilities and scopes its verified credential
grants (EHOS derives them from the contract's `by:`), and only a `:system` actor is checked against `by:`
directly. An actor built from a credential nobody verified is a hole the host opened. Authentication,
accounts and tenants stay on your side. A library that knows one
client's domain is a library for one client.

## Licence

Apache 2.0.
