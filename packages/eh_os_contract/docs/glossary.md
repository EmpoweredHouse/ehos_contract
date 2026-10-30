# Glossary

<!-- covers: entities domain.subdomain, domain.context, domain.context.term, domain.relation, domain.actor, domain.subject, domain.value, domain.entity, domain.external, contract.aggregate, contract.dcb, contract.domain_service, contract.policy, contract.effect, contract.process_manager, contract.read_model, contract.query, contract.consumes, contract.publish, contract.subscribe, contract.scenario, process.correlate, process.stage, process.ends_on, process.promise, process.deadline -->

This page gives the meaning of each word of the contract language. It is for each reader of this
documentation: a person who knows the business, and a developer. Each word has one meaning. If
another page uses a word in a different way, this page is correct.

## The words

| Word | Meaning | In the code |
| --- | --- | --- |
| **Actor** | A kind of person or a system that issues commands, asks queries or records events. The contract names the actors of each declaration. | `actor`, in the domain; `by:`, `recorded_by:` |
| **Aggregate** | A unit that decides over one stream. Example: one loan of a copy. | `aggregate` |
| **Application** | The Elixir application that uses the engine. It holds the domain, the contracts, the process modules and the code that implements them. Its contracts share one log. | — |
| **Authorizer** | The module of the application that decides if the actor of a credential can issue a command, ask a query or record an event. The engine asks it before it checks the fields or gets a decision. | `EhOsContract.Authorizer` |
| **Bus** | The interface that carries integration events from one application to another. The library supplies only a local bus, for tests and for one node. | `EhOsContract.Bus` |
| **Command** | A request to a unit to change something. The command names the actors that can issue it, the events that it can emit, and the invariants and constraints that it can reject on. | `command` |
| **Conformance** | The comparison of the log with what the contracts and the process modules declare. It answers [the four questions](#four-questions), and nothing more. | `mix eh_os_contract.report`, the dashboard |
| **Constraint** | A rule about the data of one command or one query, or a rule of a reaction. A command can reject on its constraints. | `constraint` |
| **Consumer** | A declaration that takes events from the log: a reaction, a read model, or the relay of a publication. It is not the `consumes` declaration: see "Consumed event". | — |
| **Consumed event** | An event of another contract of the same application, which this contract takes from the same log. | `consumes` |
| **Context** | A part of the domain in which each word has one meaning. Each contract belongs to one context. Also called a bounded context. | `context` |
| **Contract** | A module that describes what the units of one context decide: their commands, events, invariants and lifecycles. It also holds the consumers of their events, the queries and the scenarios. | `use EhOsContract.Contract` |
| **Correlation** | The fields that tell the runs of one process apart. Each event that the process includes carries them. Example: `loan_id`. | `correlate` |
| **Deadline** | The longest time that a whole run can take, from its first event to the first event that ends it. | `deadline` |
| **Decision** | The answer of a unit to a command: events, or a rejection. The implementation of the unit makes the decision. | the callback for each command, `emit/1`, `reject/1` |
| **Delivery** | When a reaction or a read model runs. `:in_transaction` runs it before the event is committed, in the same transaction. `:at_least_once` runs it after the commit, and can run it again. A relay always runs after the commit. | `delivery:` |
| **Dispatch** | What the engine does with a command. It checks the actor and the fields, and reads the events of the unit. Then it gets the decision and appends the declared events. | `EhOsContract.dispatch/3` |
| **Domain** | The module that holds the words of the business: its subdomains, contexts, actors, subjects, values, entities and external systems. Nothing in it runs. | `use EhOsContract.Domain` |
| **Domain service** | Pure functions that belong to no unit, such as a price from a tariff. A decision calls them. | `domain_service` |
| **Dynamic consistency boundary** | A unit that decides over a query of the log: its own events, and the events of other units that it consults. Example: the places of a workshop and each seat that a person takes. | `dcb` |
| **Effect** | A reaction that acts outside the log, for example to send a message. It names the external systems that it calls. | `effect` |
| **Entity** | A thing with an identity that the code of the application or another system keeps, outside the log. A contract points to it by its identity. | `entity`, in the domain |
| **Event** | Something that occurred in the business, declared in a unit. A unit emits it after a decision, or an actor records it. The log keeps it. Do not call it a "fact". | `event` |
| **External system** | A system that the application exchanges data with. Its name tells what it does for the business, not the name of its vendor. | `external`, in the domain |
| **Identity** | The fields that tell one unit from another. The engine adds them to the state, the commands and the events of the unit. | `identity` |
| **Implementation** | The module that holds the code of one declaration of a contract. It points to the contract. The contract does not name it. | `use <Contract>, aggregate: :name` |
| **Inbox** | The table of the engine that receives the events of other applications. Only a policy takes an event from it. The inbox drops a second delivery of the same message, and the same event published again. The event does not go into the log. | `EhOsContract.Inbox` |
| **Integration event** | An event that leaves the application: a versioned name and the fields that it carries. A publication declares it. | `publish` |
| **Invariant** | A rule that must stay true, as the business states it: of a unit, of a value, or of a process manager. A command names the invariants that it can reject on. | `invariant` |
| **Lifecycle** | The statuses of an aggregate, and the transitions that its events make between them. A dynamic consistency boundary has no lifecycle. | `lifecycle` |
| **Log** | The table of the engine that keeps the events of the application, in the order that they were appended. | `EhOsContract.Store` |
| **Personal field** | A field that holds personal data of one subject. The engine encrypts it with a key for that subject. If the subject is erased, the engine destroys the key. | `personal:`, `EhOsContract.erase/3` |
| **Policy** | A reaction without state. When it takes an event, it can issue commands. | `policy` |
| **Process manager** | A reaction that steers one run over time. It keeps a state, sets timers, and issues commands. | `process_manager` |
| **Process module** | A module that describes one kind of run. It names the events of each stage, from one or more contracts, the events that end a run, the promises and the deadline. A contract whose units only decide and record needs no process module. | `use EhOsContract.Process` |
| **Promise** | What a process states about each run: after one event, another event follows, or an alternative event. A promise can also give a time limit. | `promise`, `eventually`, `or_else`, `within` |
| **Publication** | The declaration that lets an event leave the application, as an integration event. It is the only way out. | `publish` |
| **Query** | A question that an actor asks of one read model. The query names the actors that can ask it. It changes nothing. | `query` |
| **Reaction** | A policy, an effect or a process manager: a declaration that does something because an event occurred. A read model is not a reaction. | — |
| **Read model** | Data that the application keeps for reading, written from events, usually in its own table. Queries read it. A read model decides nothing. | `read_model` |
| **Recording** | An event that an actor writes into the log without a decision: an observation, or the answer of an external system. The event names the actors that can record it. | `recorded_by:`, `EhOsContract.record/3` |
| **Rejection** | The answer of a unit that refuses a command on an invariant or a constraint. The log gets no event. | `reject/1`, `rejects:` |
| **Relation** | How two contexts depend on each other: one of 8 patterns of context mapping. | `relation`, in the domain |
| **Relay** | The consumer that reads the published events from the log and gives them to the bus. | `EhOsContract.Relay` |
| **Run** | One case of a process. Example: one loan, from lending to return. The correlation fields of its events tell it from other runs. | — |
| **Scenario** | An example that a contract or a process module carries: the events that occurred, what occurs next, and the result that it must give. The engine runs each scenario as a test. | `scenario`, `EhOsContract.ScenarioCase` |
| **Stage** | One step of a run, with the events that it includes. The stages have an order. The report counts the runs that entered them out of order. | `stage` |
| **State** | What a unit or a process manager remembers between decisions. The engine folds it from the events, in order. | `state` |
| **Status** | The position of an aggregate in its lifecycle. The engine calculates it from the names of the events in the stream. | `status`, in the state |
| **Stream** | The events of one aggregate, in order. The name of the aggregate and the values of its identity select them. | — |
| **Subdomain** | A part of the business, of one kind: core, supporting or generic. Each context belongs to one subdomain. | `subdomain` |
| **Subject** | A kind of person whose personal data the application keeps and may have to erase. Example: a customer. | `subject`, in the domain |
| **Subscribed event** | An event of another application that a contract takes by its published name. It arrives in the inbox. | `subscribe` |
| **Subscription** | The position in the log of one consumer that reads the log in order. Examples: a read model, a process manager, a relay, a policy delivered `:at_least_once`. | `mix eh_os_contract.subscriptions` |
| **Term** | One word of the glossary of a context, with its definition in that context. A term can name the words not to use for it. | `term` |
| **Transition** | A move of an aggregate from one status to another, which one event makes. | `transition` |
| **Unit** | The thing that a command goes to: an aggregate or a dynamic consistency boundary. It keeps its invariants and answers each command with a decision. | `aggregate`, `dcb` |
| **Value** | A name that the domain gives to a type of data: a built-in type, or a set of fields. A field can use it as its type. | `value`, in the domain |
| **Verdict** | The result of one promise for one run at one moment: satisfied, violated, pending or suspended. | `:satisfied`, `:violated`, `:pending`, `:suspended` |

<a id="four-questions"></a>

## The four questions of conformance

The conformance report and the dashboard answer these four questions about the contracts and the
process modules:

1. Which declared paths were never taken?
2. Which transitions occurred that the contract does not declare?
3. Which promises were broken?
4. Which version of the contract is deployed, and since when?

## The words in a model

This example shows the words in a domain, a contract and a process module.

```elixir
defmodule Glossary.Domain do
  # The domain, with one subdomain, one context and one actor.
  use EhOsContract.Domain, name: :glossary_example, language: :en

  subdomain :lending, "Lending", type: :core

  context :loans, "Loans", subdomain: :lending

  actor :librarian, :human, "Librarian"
end

defmodule Glossary.Contracts.Loans do
  # A contract of the context `:loans`.
  use EhOsContract.Contract, domain: Glossary.Domain, context: :loans, id: "glossary_example.loans"

  # A unit: an aggregate. Its identity is `loan_id`.
  aggregate :loan, "Loan of a copy" do
    identity :loan_id

    state do
      field :returned, :boolean, default: false
    end

    invariant :returned_once, "A loan is returned once"

    # A command, which the actor `:librarian` issues.
    command :open_loan, "Lend a copy", by: :librarian, emits: :loan_opened do
      field :copy_id, :id
    end

    # A command that can be rejected on the invariant.
    command :return_copy, "Take a copy back",
      by: :librarian,
      emits: :copy_returned,
      rejects: :returned_once

    # Two events.
    event :loan_opened, "Copy lent" do
      field :copy_id, :id
    end

    event :copy_returned, "Copy returned"
  end

  # Two scenarios: the second one shows the rejection.
  scenario "a copy is lent" do
    command :open_loan, %{copy_id: "c-1"}
    expect :loan_opened
  end

  scenario "a returned copy is not returned twice" do
    given :loan_opened, %{copy_id: "c-1"}
    given :copy_returned
    command :return_copy
    rejected :returned_once
  end
end

defmodule Glossary.Processes.Loan do
  # A process module. Each run is one loan, correlated by `loan_id`.
  use EhOsContract.Process,
    id: "glossary_example.loan",
    domain: Glossary.Domain,
    label: "A loan, from lending to return",
    accountable: :librarian

  correlate :loan_id

  stage :lending, "Lending", include: [{Glossary.Contracts.Loans, :loan_opened}]
  stage :return, "Return", include: [{Glossary.Contracts.Loans, :copy_returned}]

  ends_on :copy_returned

  # A promise, and the deadline of each run.
  promise :returned_within_a_month do
    from :loan_opened
    eventually :copy_returned
    within {30, :day}
  end

  deadline {60, :day}
end
```

## Next steps

- [Introduction](introduction.md): what the library does, and what it does not do.
- [Writing a domain and a contract](contract.md): how to start, and what does not compile.
- The concepts, from [the domain](concepts/domain.md) to [processes](concepts/process.md).
