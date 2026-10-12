# Introduction

What eh_os_contract is, what it is for, and the principles it is built on.

## What it is

A business process is written down as 2 Elixir modules. The **domain** holds the words the people in
the process use, the contexts it is split into, who acts in it and which systems it depends on. The
**contract** holds what is decided in one context, what happened, what reacts to it, what is read, and
what was promised. Both are declarations, not code that runs: every key of them is listed in the reference
([the domain](dsl/domain-dsl.md), [the contract](dsl/contract-dsl.md),
[the process module](dsl/process-dsl.md)).

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
    event :application_approved, "Application approved", terminal: true
  end

  process :onboarding, "Onboarding" do
    correlate :application_id
    accountable :reviewer

    promise :decided_within_a_week do
      from :application_received
      eventually :application_approved
      within {7, :day}
    end
  end
end
```

Read the promise aloud: *after an application is received, within 7 days it is approved.* That
sentence is what the person who owns the process confirms or corrects, and it is why every declaration
carries a label in the words of the people in the process.

Everything else the library does reads those 2 modules:

- **The compiler** refuses a model that contradicts itself and code that contradicts the model: an
  implementation that emits an event its command does not declare does not compile.
- **Dispatch** (`EhOsContract.dispatch/3`) runs a command through the contract: may this actor issue it,
  are its fields sound, what does the implementation decide. What the contract declares is appended to
  the engine's own event log, and nothing else is. A unit's state is its events, folded: applied one by one, in order.
- **Reactions** run from the log: read models that answer queries, policies that issue commands, effects
  that call other systems, process managers that steer a run over time.
- **Between applications**, an event leaves only through a `publish`, and one arrives only in an inbox a
  policy takes.
- **Conformance** compares the log with the contract and answers 4 questions: which declared paths were
  never taken, what happened that the contract does not declare, which promises are broken, and which
  version of the contract is deployed, and since when.

## What it is for

- **Building an event-sourced application (every change stored as an event) from a model the business can read.** The contract is the
  part of the code a process owner reviews; the implementation decides, the contract holds it to what
  was agreed.
- **Knowing whether the deployed code does what the process says**, by comparing what happened, in
  the log, with what was declared: a path nobody takes, a transition nobody declared, a promise kept
  late.
- **Changing a process and seeing what changed.** Each deployment records the version of every
  contract, and the report says which version is deployed, since when, which declarations changed, and
  which events were written under an earlier version.
- **Exchanging events between applications** without a broker in the library: the library defines the
  bus (`EhOsContract.Bus`) and ships a local one for tests; the transport is the platform's.

## What it is not

It answers the 4 questions and nothing more. Performance belongs to your application performance monitoring (APM) tool, errors to your error
tracker, and the state of your business to your own application, which the library helps you build
through read models and queries but does not show on the conformance dashboard. It does not know who anybody is: an
actor is an opaque subject with the capabilities its verified credential grants
([authorization](authorization.md)). It ships no message broker, no identity provider, no REST or
GraphQL layer beyond the documents it generates from the contract, and nothing that answers a question
about one particular customer.

## Principles

- **The model is code, and there is nothing beside it.** A domain and a contract are Elixir modules on
  [Spark](https://hexdocs.pm/spark), in the manner of [ESDM](https://www.esdm.io). What is wrong with them
  fails the compile, with a code and a message ([what will not compile](contract.md)); what a model may
  legally say but a reader should hear about, `mix eh_os_contract.check` reports ([its rules](rules.md)).
- **The contract names no implementation.** An implementation points at its contract
  (`use MyContract, aggregate: :application`), never the other way round, so a change to the code never
  recompiles the contract.
- **Events and commands are literals.** An implementation emits and issues struct literals, so the
  graph of a contract, and what each command can produce, is read straight from the code.
- **Nothing the contract does not declare reaches the log.** An undeclared event, a command an actor
  may not issue, a field of the wrong type: each is refused before anything is written.
- **No rule of the check can be switched off.** A finding goes away when the model changes.

Next: [Getting started](getting-started.md).
