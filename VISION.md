# EHOS Contract — Compile the architecture

> A developer — or an agent — changes an event.
>
> The project knows which process owns it, which command emits it, which consumers depend on it, and which
> scenarios prove it.
>
> If the change contradicts the model, the project does not compile.

Modern software rarely has one trustworthy description of how it works. Domain knowledge lives in workshop
notes, architecture in diagrams, event schemas in registries, behavior in code, examples in tests, and the
rest in people's heads.

LLMs make this fragmentation more expensive. They can generate code quickly, but when architecture is implicit,
they can only guess.

**EHOS Contract turns domain design into executable architecture.**

It is an Elixir DSL for Domain-Driven Design and event-driven applications. The model lives beside the code,
is versioned with it, and participates in compiling, testing, running, and explaining the application.

One domain language. One contract per business process. One model that humans, tools, and agents can all read.

---

## One executable model

A domain defines the language and ownership of the system: subdomains, bounded contexts, actors, external
systems, entities, values, and the relations between them.

A contract defines one business process in that language: its consistency boundaries, commands, events,
reactions, read models, process flow, and scenarios.

Together they connect two views that are too often separated:

- **DDD describes meaning** — language, ownership, boundaries, invariants, and rules.
- **EDA describes movement** — commands, events, consumers, projections, and flows across boundaries.

The contract is not documentation that code is expected to follow. It is part of the program.

| When | What the contract does |
| --- | --- |
| **Compile** | Refuses invalid models, missing implementations, undeclared behavior, and incompatible producer-consumer changes. |
| **Test** | Turns scenarios, examples, invariants, and domain rules into executable evidence. |
| **Run** | Validates inputs and outputs, enforces authorization and consistency, dispatches reactions, and records what happened. |
| **Explain** | Generates detailed documentation and connected graphs from the same model the application executes. |

A rule expressed once should not need to be remembered everywhere else.

When a human or an LLM writes code, the compiler provides immediate architectural feedback. Tests prove the
examples. Runtime checks protect the boundaries that static analysis cannot see. The event history shows whether
the running process still matches the contract.

**The LLM does not have to guess the architecture. The project teaches it.**

---

## Architecture you can navigate

```text
Domain
└── Subdomain
    └── Bounded Context
        └── Process Contract
            ├── Commands and Events
            ├── Reactions and Read Models
            └── Process and Scenarios
```

Start with the domain and its context map. Zoom into a system, a process, or one consistency unit. Follow which
command produces an event, which policy reacts, which read model consumes it, and where an external system enters
the flow.

Process owners see language, flows, responsibilities, and examples. Engineers see boundaries, message shapes,
dependencies, and change impact. Agents receive precise context and machine-checkable feedback.

The graphs and pages are not drawn after implementation. They are the implementation model rendered for a
different reader. Documentation cannot quietly drift away because it has no separate source to drift from.

---

## From model to living architecture

Architecture becomes useful when its parts are connected. Domains lead to bounded contexts. Processes belong to
those contexts. Commands produce events. Reactions consume them. People and systems own responsibilities. A
change in one place reveals what depends on it.

EHOS Contract keeps those relationships in one navigable model, close to the code and available to people,
tools, and agents.

**The model is not a catalog of what somebody once intended. It is architecture the application must obey.**

The contract itself is compiled, tested, executed, and rendered. Correctness and documentation are two readings
of the same model.

---

## The bet

LLM-assisted development does not become reliable through better prompts alone. It becomes reliable when the
project contains an explicit model and fast, deterministic feedback at every boundary.

EHOS Contract makes that model an integral part of the application:

- the code cannot silently contradict it;
- scenarios make business examples executable;
- runtime guards what compilation cannot see;
- event history provides evidence of what really happened;
- graphs and detailed contract pages keep the system understandable.

Humans own the language, meaning, and trade-offs. Agents work inside boundaries the project can enforce.

**Describe the domain. Compile the architecture. Build with confidence.**
