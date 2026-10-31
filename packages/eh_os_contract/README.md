# EhOsContract

`eh_os_contract` is an engine for event-driven Elixir applications. You describe a business process
as Elixir modules, and the engine runs the application on them. Then it checks if what occurred
agrees with what the modules declare. This page is for a developer who decides whether to use the
engine. [The glossary](docs/glossary.md) defines each word in italics.

## What does a model look like?

A *domain* holds the words of the business. A *contract* holds what one *context* decides: the
*commands*, the *events* and the rules. An *implementation* holds the code that decides.

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

Your application sends a command through *dispatch*, with the actor that it authenticated:

```elixir
alias MyApp.Contracts.Onboarding

EhOsContract.dispatch(Onboarding, %Onboarding.Commands.SubmitApplication{application_id: id},
  actor: actor
)
```

The compiler refuses an implementation that emits an event that its command does not declare.
Dispatch appends to the *log* only the events that the contract declares.
[Getting started](docs/getting-started.md#dispatch-a-command) shows each step of dispatch in a
diagram.

## What does the engine give you?

- **Compile-time checks.** The compiler refuses a model that contradicts itself, with a code and a
  message. [The compile refusals](docs/refusals.md) list each code.
- **Dispatch and the log.** The engine keeps the events in its own table in PostgreSQL. The state of
  a unit is its events, folded in order.
- **Reactions and read models.** Policies, effects and process managers react to events. Read models
  keep data for the queries.
- **Personal data that you can erase.** The engine encrypts each personal field with a key for its
  subject. An erasure destroys the key.
- **Scenarios as tests.** Each scenario of a contract runs as a test of its implementation.
- **Conformance.** `mix eh_os_contract.report` and the dashboard answer
  [the four questions of conformance](docs/glossary.md#four-questions).

[What is eh_os_contract?](docs/introduction.md) tells how these parts fit together, and what the
engine does not do.

## Next steps

- [Getting started](docs/getting-started.md): install the engine and dispatch a first command.
- [Write a domain, a contract and a process module](docs/contract.md): the full task.
- [The command-line tasks](docs/cli.md): each `mix` task and its options.
- [Authorization](docs/authorization.md): how a credential becomes an actor.

## Licence

Apache 2.0.
