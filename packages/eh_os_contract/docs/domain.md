# The domain: subdomains, contexts and relations

This page tells how a domain divides a business into parts, and how the parts depend on each other.
It is for a developer who writes the domain of an application, and for a person who knows the
business and reads it. [The glossary](glossary.md) defines each word of the contract language.

<!-- covers: entities domain.subdomain, domain.context, domain.context.term, domain.relation; rules subdomain-without-bounded-context, bounded-context-without-content, orphan-context-mapping, label-with-avoided-term, word-without-term, term-of-another-context, cross-bounded-context-reference-without-mapping -->

## What does a domain hold?

A domain is the vocabulary that the contracts of an application share. Nothing in it runs. It holds:

- the subdomains and the contexts of the business, and the words of each context;
- the relations between the contexts;
- the actors, the values, the entities and the external systems, which
  [actors, values, entities and external systems](domain-data.md) describes;
- the subjects of personal data, which [personal data and erasure](personal-data.md) describes.

Each contract names its domain with `domain:`. The compiler `:eh_os_contract` checks each contract
against its domain.

<!-- in: Concepts.Domain.Domain -->
```elixir
use EhOsContract.Domain, name: :lending, language: :en, time_zone: "Europe/Warsaw"
```

- `name:` is the namespace of the application. Each capability, role, contract id and published
  event name starts with it.
- `language:` is the language of the labels and the terms.
- `code_language:` is the language of the names in the code. If you do not give it, it is English.
- `time_zone:` is the time zone of the days of the business.

[The domain reference](dsl/domain-dsl.md) gives each key.

An application usually has one domain. It can have more, each with its own contracts. Then the tasks
that read one domain need `--domain` to name it. A contract consumes only the events of its own
domain ([`X5`](refusals.md#refusals-x)).

If the application uses `eh_os_contract_auth`, only the domain whose `name:` is the name of the
application can publish. The two names must be equal: `:"my-shop"` for the application `my-shop`,
not `:my_shop`.

## What is a subdomain?

A subdomain is a part of the business, with the name that the business gives it. It has one of three
kinds:

| Kind | What it is |
| --- | --- |
| `:core` | What the business competes on. The model needs the most care here. |
| `:supporting` | What the core needs, and what no vendor sells ready to use. |
| `:generic` | What each business does the same way, and could buy. |

<!-- in: Concepts.Domain.Domain -->
```elixir
subdomain :lending, "Lending", type: :core
subdomain :cataloguing, "Cataloguing", type: :supporting
```

A subdomain holds nothing itself. Each context names the subdomain that it belongs to. If the
subdomain is not declared, the compiler refuses the context ([`D7`](refusals.md#refusals-d)).

The kind is for people. The graph of the domain, `mix eh_os_contract.graph --domain <domain>`, shows
each subdomain with its kind. The dashboard draws a subdomain as a group of its contexts. Nothing
reads the kind at run time.

## What is a context?

A context is a part of the domain in which each word has one meaning. Example: at the loan desk, a
"copy" is a copy that a member can take home. In the catalogue, a copy can be any item on the shelf.
Two contexts let one word have two meanings, and neither meaning is wrong.

<!-- in: Concepts.Domain.Domain -->
```elixir
context :loans, "Loans", subdomain: :lending do
  term "Copy", definition: "An item a member may take home"

  term "Loan", definition: "A copy lent to a member until it is returned" do
    avoid "Borrowing", reason: "The desk lends; the member borrows"
  end
end
```

- `subdomain:` is required.
- `language:` is optional. Give it when the labels of the context are not in the language of the
  domain.
- The block holds the glossary of the context: one `term` for each word.

## What does the glossary of a context hold?

Each `term` has a `definition` of what the word means in this context. A term can also have:

- a `source`: where the definition comes from;
- `avoid "Borrowing", reason: "…"`: a word not to use for this term;
- `translation :de, "Ausleihe", definition: "…"`: the word in another language, with what it means
  there. A translation can avoid words of its own language.

The compiler refuses a term that a context defines twice. It also refuses two translations of one
term into one language, and a translation into the language of the context itself
([`D1`](refusals.md#refusals-d), [`D2`](refusals.md#refusals-d)).

`mix eh_os_contract.glossary` prints the glossary of each context, with the words to avoid and the
translations. With `--language en`, it prints each term in English, or says that the term has no
English word.

## How does the check hold the code to the glossary?

The names in the code are in the `code_language:` of the domain. The labels are in the language of
the context. The *word in code* of a term is its translation into the code language. In a context
that is written in the code language, it is the term itself.

Example: the term "Ausleihe" with `translation :en, "Loan"` has the word in code `loan`. So `:loan`,
`:loan_id` and `:return_loan` use this term.

- A term of several words matches the same words in a row. "Due date" matches `:due_date_set`, but
  not `:date_due`.
- Inflected forms do not match.

`mix eh_os_contract.glossary` shows, under each term, its word in code and the declarations that use
it. `mix eh_os_contract.check` reads the names of units, read models and fields in two directions:

- It lists the words of a context that no term covers, as one notice for each context
  (`word-without-term`). It ignores words of 1 or 2 letters, such as `id`, and the names of commands
  and events.
- It warns about a name that uses the word of a term of another context. It does not warn when a
  term of its own context covers the word (`term-of-another-context`). Define the word in this context too, or
  rename the field.

Both rules ignore the part of a field name that names its value type. Example: in a field
`:office_nip` of the type `:nip`, the word "nip" belongs to the value, not to a context. The second
rule also ignores a field that refers to another context by an identity, such as `{:id, :copy}` or
`loan_id`.

The check also warns about a label that uses a word that its glossary says to avoid
(`label-with-avoided-term`). It reads the label of each declaration and of each enum member. A word
matches whole, in any letter case. Inflected forms do not match, so name each form in `avoid`.

<a id="how-do-two-contexts-relate"></a>

## How do two contexts relate?

A relation tells how two contexts depend on each other. It is one of 8 patterns of context mapping.
Five patterns are directed: the *downstream* context depends on the *upstream* context.

| Pattern | What it tells | What a contract of the downstream context can consume from the upstream context |
| --- | --- | --- |
| `:customer_supplier` | The downstream asks. The upstream plans what it supplies. | Each event. |
| `:conformist` | The downstream uses the model of the upstream as it is. | Each event. |
| `:anticorruption_layer` | The downstream translates the model of the upstream into its own model. | Only an event that a policy takes and translates into a command. |
| `:open_host_service` | The upstream gives a protocol for each downstream. | Only an event that the upstream publishes. |
| `:published_language` | The two exchange a documented language. | Only an event that the upstream publishes. |

Three patterns are symmetric. They name their two contexts with `between:`.

| Pattern | What it tells | What a contract of one context can consume from the other |
| --- | --- | --- |
| `:partnership` | The two plan together, and succeed or fail together. | Each event. |
| `:shared_kernel` | The two share a part of the model. | Each event. |
| `:separate_ways` | The two do not depend on each other. | Nothing. No reference crosses. |

<!-- in: Concepts.Domain.Domain -->
```elixir
relation :customer_supplier, upstream: :catalogue, downstream: :loans, terms: [{"Item", "Copy"}]
relation :separate_ways, between: [:loans, :events]
```

- `terms:` pairs the words that the two contexts use for one thing. The first word belongs to the
  upstream, or to the first context of `between:`. Each word must be a term of its context. The
  glossary then shows, under a term, the word of the other context.
- One end of a directed relation can be an external system. The other end is then a context:
  `relation :anticorruption_layer, upstream: :payment_provider, downstream: :loans`.
- A symmetric relation connects two contexts, never an external system.
- On the context map of the dashboard, a directed relation is an arrow from the upstream to the
  downstream. A symmetric relation is a line. `:separate_ways` is a dashed line.

The compiler refuses a relation with ends that do not fit its pattern or that the domain does not
declare. It also refuses a context in a relation with itself, and a word of `terms:` that is not a
term of its context ([`D5`](refusals.md#refusals-d)).

<a id="which-context-depends-on-which"></a>

## Which context depends on which?

A contract of one context depends on another context when it does one of these:

- It consumes a contract of the other context: `consumes Lending.Contracts.Catalogue, [:item_withdrawn]`.
- It names an entity or a unit that the other context owns, with a field of the type `{:id, name}`.
- It uses a value that the other context declares (`value …, context:`).

Each such reference must follow the relation between the two contexts.

![The loans contract names the copy that the catalogue owns, so loans depends on the catalogue, and their customer-supplier relation allows it.](img/domain-relations.svg)

1. The contract of the loans context names the entity `:copy`, with a field `{:id, :copy}`. This is
   a reference from loans to the catalogue.
2. The catalogue context owns the entity `:copy`. So the loans context depends on the catalogue.
3. The loans context holds the contract. The contract uses the words of this context.
4. The relation `:customer_supplier` makes the catalogue the upstream and loans the downstream. A
   reference from the downstream to the upstream is what this relation allows.

The library events context has a `:separate_ways` relation with loans. No reference crosses between
them.

The compiler refuses a reference that breaks a relation:

- A reference from the upstream context into the downstream context, or a reference across
  `:separate_ways` ([`X11`](refusals.md#refusals-x)).
- A read model, an effect or a process manager that takes an event across an
  `:anticorruption_layer`, or a boundary that consults one ([`X12`](refusals.md#refusals-x)).
- An event that the upstream does not publish, across an `:open_host_service` or a
  `:published_language` ([`X13`](refusals.md#refusals-x)).

In one application, a contract takes a published event whole from the log. Another application takes
it by its published name, with only the fields that the publication declares. A process module that
includes an event is no reference, because a process belongs to no context.

The check compares the references with the relations in both directions:

- A reference between two contexts that no relation connects is a warning
  (`cross-bounded-context-reference-without-mapping`). Declare the relation. A domain can be mapped
  one part at a time, so this is a warning, not a refusal.
- A relation that no reference crosses is a warning (`orphan-context-mapping`). For a relation to an
  external system, the check looks for a contract of the context that uses the system.

## Why does a contract belong to one context?

A contract is written in one language: the words of its context. Each contract names its context:
`use EhOsContract.Contract, domain: Lending.Domain, context: :loans, id: "lending.loans"`.

- If the domain does not declare the context, the compiler refuses the contract
  ([`X1`](refusals.md#refusals-x)).
- The labels of the contract use the words of its context, and the check reads them against that
  glossary.
- An actor that belongs to another context cannot be named in `by:`
  ([`X2`](refusals.md#refusals-x)).

A policy or a read model without `delivery` runs in the transaction of the context that decided the
event. So one that takes an event of a contract of another context must declare its `delivery`
([`X10`](refusals.md#refusals-x)). `:at_least_once` keeps the two contexts apart.
`:in_transaction` couples them, and you choose that on purpose.

## An example

The loan desk depends on the catalogue: a loan names the copy that it lends, and the catalogue owns the
copy.

```elixir
defmodule Concepts.Domain.Domain do
  use EhOsContract.Domain, name: :lending, language: :en

  subdomain :lending, "Lending", type: :core
  subdomain :cataloguing, "Cataloguing", type: :supporting

  context :catalogue, "Catalogue", subdomain: :cataloguing do
    term "Item", definition: "Anything the library holds, whether it may be lent or not"
  end

  context :loans, "Loans", subdomain: :lending do
    term "Copy", definition: "An item a member may take home"

    term "Loan", definition: "A copy lent to a member until it is returned" do
      avoid "Borrowing", reason: "The desk lends; the member borrows"
      translation :de, "Ausleihe", definition: "Ein Exemplar, das bis zur Rückgabe verliehen ist"
    end
  end

  context :events, "Library events", subdomain: :lending

  relation :customer_supplier,
    upstream: :catalogue,
    downstream: :loans,
    terms: [{"Item", "Copy"}]

  relation :separate_ways, between: [:loans, :events]

  entity :copy, "Copy", context: :catalogue, identity: :copy_id

  actor :librarian, :human, "Librarian", context: :loans
end

defmodule Concepts.Domain.Contracts.Loans do
  use EhOsContract.Contract,
    domain: Concepts.Domain.Domain,
    context: :loans,
    id: "lending.loans"

  aggregate :loan, "Loan" do
    identity :loan_id

    command :open_loan, "Lend a copy", by: :librarian, emits: :loan_opened do
      field :copy_id, {:id, :copy}
    end

    event :loan_opened, "Copy lent" do
      field :copy_id, {:id, :copy}
    end
  end

  scenario "a copy is lent" do
    command :open_loan, %{copy_id: "c-1"}
    expect :loan_opened
  end
end
```

The contract of loans names the entity `:copy`, which the catalogue owns. So loans depends on the
catalogue, and the relation `:customer_supplier` says so.

This example is small, so `mix eh_os_contract.check` reports findings for it. Example: no contract
belongs to the catalogue or to the library events (`bounded-context-without-content`).

## Next steps

- [Actors, values, entities and external systems](domain-data.md): the other declarations of a domain.
- [Personal data and erasure](personal-data.md): subjects, and what the engine does when one is erased.
- [Between contracts](between-contracts.md): consume, publish and subscribe.
- [The compile refusals](refusals.md), families D and X: each refusal of a domain, with its code.
- [The rules of the check](rules.md): each warning and notice, with its fix.
