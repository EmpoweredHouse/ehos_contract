# The domain: subdomains, contexts and how they relate

How a domain module splits a business into subdomains and bounded contexts, gives each context its glossary,
says how the contexts depend on each other, and why every contract belongs to exactly one of them.

<!-- covers: entities domain.subdomain, domain.context, domain.context.term, domain.relation; rules subdomain-without-bounded-context, bounded-context-without-content, orphan-context-mapping, relation-against-references, label-with-avoided-term, cross-bounded-context-reference-without-mapping -->

## A domain module

An application has one domain module. It is the vocabulary its contracts share: the parts the business is
split into, the words each part uses, who acts, whose personal data is kept, the value types, and the systems
the application depends on. Nothing in it runs. Contracts name it, `domain: Lending.Domain`, and the rules
between modules hold every contract to it as it compiles.

```elixir
use EhOsContract.Domain, name: :lending, language: :en, time_zone: "Europe/Warsaw"
```

`name:` is the application's namespace towards EHOS: the first segment of every capability, role, contract id
and published event name. `language:` is the language labels and terms are written in. `time_zone:` is the
zone the business's days are in. [Writing a domain and a contract](../contract.md) says what each refuses;
every key is in [the domain's reference](../dsl/domain-dsl.md).

This page is about the first half of a domain: how the business is divided and how the parts relate. Actors,
personal data, values, entities and external systems are in [the domain's data](domain-data.md).

## Subdomains

A subdomain is a part of the business, named as the business names it, with its kind:

- `:core`: what the business competes on, where the model deserves the most care;
- `:supporting`: what the core needs and nobody sells ready-made;
- `:generic`: what any business does the same way, and could buy.

```elixir
subdomain :lending, "Lending", type: :core
subdomain :cataloguing, "Cataloguing", type: :supporting
```

A subdomain holds nothing itself. Contexts name the subdomain they belong to, and a context naming a
subdomain the domain does not declare does not compile (`D7`). The context map,
`mix eh_os_contract.graph --map <domain>`, draws each subdomain as a group of its contexts, with its kind; nothing at
run time reads the kind.

## Contexts and their glossary

A bounded context is a part of the domain where a word means one thing. "Copy" at the loan desk is a copy a
member can take home; in the catalogue it may be any item on the shelf, lendable or not. Two contexts are
where the same word may mean two things without either being wrong.

```elixir
context :loans, "Loans", subdomain: :lending do
  term "Loan", definition: "A copy lent to a member until it is returned" do
    avoid "Borrowing", reason: "The desk lends; the member borrows"
  end
end
```

A context names its subdomain (required) and may name a `language:` of its own, when its labels are not
written in the domain's. Its block holds its glossary: one `term` per word, each with a `definition` of what it
means in this context and, optionally, the `source` the definition comes from.

A term may say which words must not be used for it, `avoid "Borrowing", reason: "…"`, and how it is said in
another language, `translation :de, "Ausleihe", definition: "…"`, with what it means there; a translation
may avoid words of its own language. A term defined twice in one context does not compile (`D1`), nor two
translations of one term into one language, or one into the context's own (`D2`).

The glossary is what `mix eh_os_contract.glossary` prints, per context, with the words to avoid and the
translations; `--language en` prints each term in English, or notes that it has none.

## Relations between contexts

A relation says how two contexts depend on each other: one of the eight context-mapping patterns. Five are
directed, with an upstream the other side depends on and a downstream that depends on it:

| Type | What it says |
| --- | --- |
| `:customer_supplier` | the downstream asks, the upstream plans what it supplies with it |
| `:conformist` | the downstream takes the upstream's model as it is |
| `:anticorruption_layer` | the downstream translates the upstream's model into its own |
| `:open_host_service` | the upstream offers a protocol for any downstream |
| `:published_language` | the two exchange a documented, shared language |

Three are symmetric and name their two contexts with `between:`. On the context map a directed relation is an
arrow from upstream to downstream, a symmetric one a line, and `:separate_ways` a dashed one.

| Type | What it says |
| --- | --- |
| `:partnership` | the two succeed or fail together and plan together |
| `:shared_kernel` | the two share a part of the model |
| `:separate_ways` | the two do not depend on each other |

```elixir
relation :customer_supplier, upstream: :catalogue, downstream: :loans, terms: [{"Item", "Copy"}]
relation :separate_ways, between: [:loans, :events]
```

`terms:` pairs the words the two ends use for one thing: the first end's word (the upstream, or the first of
`between:`), then the second's, each a term of its context's glossary. The glossary then shows, under a term,
what the other end calls it.

An end of a directed relation may be an external system rather than a context, the other end then a context:
`relation :anticorruption_layer, upstream: :payment_provider, downstream: :loans`. A symmetric relation is
between contexts only. A relation whose roles do not fit its type, an end the domain does not declare, a
context related to itself, or a word of `terms:` its context's glossary does not define does not compile
(`D5`); a relation declared twice does not either (`D1`).

## A contract belongs to one context

Every contract names its context,
`use EhOsContract.Contract, domain: Lending.Domain, context: :loans, id: "lending.loans"`, and a context the domain does not declare is refused (`X1`). One context, because a
contract is written in one language: its labels are that context's words, its actors are that context's (an
actor declared with another `context:` is refused in `by:`, `X2`), and its glossary is the one its labels are
read against.

A contract reaches into another context in two ways, and each is a dependency between the contexts:

- it **consumes** a contract of another context, `consumes Lending.Contracts.Catalogue, [:item_withdrawn]`,
  and reacts to its events;
- it **names an entity another context owns**, a field `{:id, :copy}` where `:copy` belongs to the
  catalogue.

A policy or a read model left without `delivery` runs inside the transaction of the context that decided the
event it takes (an effect and a process manager run after it). So one taking an event of a sibling of another context has to
declare its `delivery` (`X10`): `:at_least_once` decouples the two, `:in_transaction` couples them on purpose.

The relations are where these dependencies are written down, and `mix eh_os_contract.check` holds the two
against each other (below).

## An example

The loan desk depends on the catalogue: a loan names the copy it lends, which the catalogue owns.

```elixir
defmodule Concepts.Domain.Domain do
  use EhOsContract.Domain, name: :domain_page, language: :en

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

  relation :customer_supplier,
    upstream: :catalogue,
    downstream: :loans,
    terms: [{"Item", "Copy"}]

  entity :copy, "Copy", context: :catalogue, identity: :copy_id

  actor :librarian, :human, "Librarian", context: :loans
end

defmodule Concepts.Domain.Contracts.Loans do
  use EhOsContract.Contract,
    domain: Concepts.Domain.Domain,
    context: :loans,
    id: "domain_page.loans"

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

The loans contract names the catalogue's entity, so it depends on the catalogue, and the relation says so:
the catalogue is upstream, the desk downstream.

## What the compiler refuses

The domain's own rules (`D1`–`D7`) and the rules between a contract and its domain (`X1`, `X2`) are in the
table of [Writing a domain and a contract](../contract.md). The ones this page is about:

- **`D1`**: a name not snake_case, two subdomains or contexts of one name, a term defined twice in a
  context, a relation declared twice, a name that is both a context and an external, a blank label.
- **`D2`**: two translations of one term into one language, or one into the context's own.
- **`D5`**: a relation whose roles do not fit its type, an undeclared end, an external in a symmetric
  relation, a context related to itself, a word of `terms:` not in its context's glossary.
- **`D7`**: a context in a subdomain the domain does not declare.
- **`X1`**: a contract's `context:` naming none of its domain's contexts.
- **`X2`**: a contract's `by:`, `recorded_by:` or scenario actor naming an actor of another context.
- **`X10`**: a policy or a read model taking an event of a sibling contract of another context without
  declaring `delivery`.

## What `mix eh_os_contract.check` reports

A domain that compiles may still describe a business its contracts do not have. These are warnings
([the rules](../rules.md)):

- **`subdomain-without-bounded-context`** (warning): no context names the subdomain with `subdomain:`. Give
  it a context, or remove it.
- **`bounded-context-without-content`** (warning): no contract names the context as its `context:`, so
  nothing is decided, recorded or read there. Values and entities the context owns do not count. In the
  example, the catalogue is reported until a contract belongs to it; that is right while its contract is not
  written yet.
- **`orphan-context-mapping`** (warning): a relation that no reference crosses: no contract of one context
  consumes a contract of the other or names an entity it owns, in either direction. For a relation to an
  external system, no contract of the context calls it, depends on it, has a field it issues or acts through
  an actor it backs. The relation describes a dependency the contracts do not have.
- **`cross-bounded-context-reference-without-mapping`** (warning): the other way round: a contract consumes
  a contract of another context, or names an entity another context owns, and no relation connects the two
  contexts. Declare the relation, which says who depends on whom. One finding per reference.
- **`relation-against-references`** (warning): a reference runs against the relation: a contract of the
  upstream context of a directed relation consumes a contract of the downstream one or names an entity it
  owns, or any reference crosses a `:separate_ways` relation. Either the relation or the reference is wrong.
  It is asked between contexts only: which way a call to an external system runs says nothing about who
  depends on whom.
- **`label-with-avoided-term`** (warning): a label of a contract uses a word its context's glossary says to
  avoid. In the example, an event of the loans contract labelled "Borrowing recorded" is reported. Every
  declaration's label and every enum member's label is read; a word matches whole, in any letter case, and
  not inside the term itself. Inflected forms are not caught, so `avoid` names each form to avoid. The words
  a translation avoids are another language's, which labels are not written in.
