# What is eh_os_contract?

This page tells what the engine does, which problem it solves, and what it does not do. It is for a
developer and for a person who owns a business process, who meet the library for the first time.
[The glossary](glossary.md) defines each word in italics.

## Which problem does it solve?

Tests show that a module works. Monitoring shows that a server runs. Neither shows if the running
system still does what the business agreed.

Example: the business agreed that a clerk files each invoice within 3 days. For one case, the code
that files the invoice does not run. No error occurs, so no person gets an alert.

The engine finds such a case. You describe the process as Elixir modules, in the manner of
[ESDM](https://www.esdm.io). The application runs on these modules, and the engine records what
occurs. Then the engine compares what occurred with what the modules declare.

## How do a domain, a contract and a process module fit together?

![A domain holds contexts with their contracts, and a process module of the domain includes events of one or more of these contracts.](img/domain-nesting.svg)

1. A *domain* holds the words of one business: its subdomains, its contexts, and the terms of
   each context. Nothing in a domain runs.
2. The domain also declares the *actors*, the *subjects* of personal data, the *values* and the
   *external systems*. An actor can belong to one context. Then only the contracts of that context
   can name it.
3. A *context* draws a line inside the domain. A word can mean one thing in one context and
   another thing in a second context.
4. A *contract* holds the declarations of its context. Its *units* decide each *command*, with
   *events* or a *rejection*. Its *reactions* and *read models* take the events, and its *queries* read the read
   models.
5. A *process module* describes one kind of *run*: its *stages*, the events that end it, its
   *promises* and its *deadline*. It includes events of one or more contracts of its domain. A
   business with no run, such as a register of rooms, needs no process module.

This example has a domain, a contract with one aggregate, and a process module with one promise:

```elixir
defmodule Introduction.Domain do
  use EhOsContract.Domain, name: :introduction_example, language: :en

  subdomain :core, "Core", type: :core

  context :onboarding, "Onboarding", subdomain: :core

  actor :applicant, :human, "Applicant"
  actor :reviewer, :human, "Reviewer"
end

defmodule Introduction.Contracts.Onboarding do
  use EhOsContract.Contract,
    domain: Introduction.Domain,
    context: :onboarding,
    id: "introduction_example.onboarding"

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

defmodule Introduction.Processes.ApplicationReview do
  use EhOsContract.Process,
    id: "introduction_example.application_review",
    domain: Introduction.Domain,
    label: "Reviewing an application",
    accountable: :reviewer

  correlate :application_id

  stage :review, "Review",
    include: [{Introduction.Contracts.Onboarding, [:application_received, :application_approved]}]

  ends_on :application_approved

  promise :decided_within_a_week do
    from :application_received
    eventually :application_approved
    within {7, :day}
  end
end
```

The promise reads as a sentence: "After an application is received, it is approved within 7 days."
The owner of the process reads this sentence and confirms it or corrects it. For this reason, each
declaration has a label in the words of the business.

## What does the engine do with these modules?

- **It compiles them.** The compiler refuses a model that contradicts itself. It also refuses an
  implementation that contradicts the model, for example one that emits an event that its command
  does not declare.
- **It dispatches commands.** `EhOsContract.dispatch/3` checks the actor and the fields, gets the
  decision of the implementation, and appends the declared events to the *log* of the engine.
  [Getting started](getting-started.md#dispatch-a-command) shows each step.
- **It runs the reactions and the read models.** A policy issues commands, an effect calls an
  external system, and a process manager steers a run over time.
- **It connects applications.** An event leaves an application only through a *publication*. An
  event from another application arrives in the *inbox*, and only a policy takes it.
- **It checks conformance.** It compares the log with the contracts and the process modules.

## How does the contract reach the conformance report?

![The application runs on the contracts and appends events, and conformance compares the log with what the contracts and process modules declare.](img/conformance-flow.svg)

1. The people who do the work describe the process in a workshop. A developer writes the domain,
   the contracts and the process modules. The owner of the process reviews the labels.
2. The contract generates a struct for each command, event and state, and a behaviour for each
   implementation. Its scenarios run as tests.
3. The application sends each command through dispatch. An event that the contract does not
   declare never reaches the log. At start, the engine records which version of each contract runs.
4. The contracts declare the paths of the commands and the transitions of each lifecycle. The
   process modules declare the stages of each run and its promises.
5. The log keeps each event in order, with the version of its contract.
6. `mix eh_os_contract.report` and the dashboard answer
   [the four questions of conformance](glossary.md#four-questions) for a period.

## What does it not do?

The engine checks conformance. It does not watch the operation of the application. Other tools own
the rest:

- Your application performance monitoring (APM) tool measures performance.
- Your error tracker records errors.
- Your monitoring tools send alerts and keep metrics.
- Your application shows the state of the business. The engine helps you build that state with
  read models and queries, but the dashboard does not show it.

The engine also does not supply these things:

- **An identity.** An actor is an opaque subject with the capabilities that its verified
  credential grants. [Authorization](authorization.md) tells how a credential becomes an actor.
- **A message broker.** The library defines the bus, `EhOsContract.Bus`, and supplies only a local
  bus for tests and one node.
- **An API layer.** The engine generates OpenAPI and AsyncAPI documents from the contract. It has no
  REST or GraphQL layer of its own.
- **An answer about one customer.** A question such as "Which order has not shipped?" belongs
  to your application.

## Next steps

- [Getting started](getting-started.md): install the engine and dispatch a first command.
- [Write a domain, a contract and a process module](contract.md): the full task.
- [The glossary](glossary.md): the meaning of each word.
- The reference of each key: [the domain](dsl/domain-dsl.md), [the contract](dsl/contract-dsl.md)
  and [the process module](dsl/process-dsl.md).
