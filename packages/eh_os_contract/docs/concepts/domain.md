# The domain: subdomains, contexts and how they relate

How a domain module splits a business into subdomains and bounded contexts, gives each context its glossary,
says how the contexts depend on each other, and why every contract belongs to exactly one of them.

<!-- covers: entities domain.subdomain, domain.context, domain.context.term, domain.relation; rules subdomain-without-bounded-context, bounded-context-without-content, orphan-context-mapping, label-with-avoided-term, word-without-term, term-of-another-context, cross-bounded-context-reference-without-mapping -->

## A domain module

A domain module is the vocabulary its contracts share: the parts the business is split into, the words each
part uses, who acts, whose personal data is kept, the value types, and the systems the application depends on.
Nothing in it runs. Contracts name it, `domain: Lending.Domain`, and the compiler's rules between modules check
every contract against it.

An application usually has one domain. It may hold more, each with its own contracts: a contract consumes only
the events of its own domain ([`X5`](../contract.md#refusals-x)), and the tasks that read one domain then take
`--domain`. Connected to EHOS through `eh_os_contract_auth`, only the domain named after the application may
publish, since EHOS lets an application publish only under its own name.

```elixir
use EhOsContract.Domain, name: :lending, language: :en, time_zone: "Europe/Warsaw"
```

`name:` is the application's namespace towards EHOS: the first segment of every capability, role, contract id
and published event name. `language:` is the language labels and terms are written in. `code_language:` is
the language of identifiers, English unless given, and the glossary below is held to it. `time_zone:` is the
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
subdomain the domain does not declare does not compile ([`D7`](../contract.md#refusals-d)). The domain's graph
document, `mix eh_os_contract.graph --domain <domain>`, holds each subdomain with its kind, and the dashboard's
context map draws it as a group of its contexts; nothing at run time reads the kind.

## Contexts and their glossary

A bounded context is a part of the domain where a word means one thing. "Copy" at the loan desk is a copy a
member can take home; in the catalogue it may be any item on the shelf, lendable or not. Separate contexts
let the same word mean 2 things without either being wrong.

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
may avoid words of its own language. A term defined twice in one context does not compile ([`D1`](../contract.md#refusals-d)), nor 2
translations of 1 term into the same language, nor a translation into the context's own language ([`D2`](../contract.md#refusals-d)).

The glossary is what `mix eh_os_contract.glossary` prints, per context, with the words to avoid and the
translations; `--language en` prints each term in English, or notes that it has none.

### The glossary in the code

Labels are in the context's language and identifiers are in the domain's `code_language:`, English unless
`use EhOsContract.Domain` says otherwise. A term's **word in code** is its translation into that language, or
the term itself in a context written in that language. So a term "Ausleihe" with `translation :en, "Loan"` is the
word `loan`, and `:loan`, `:loan_id` and `:return_loan` are named with it. A term with several words is
matched as those words in a row: "Due date" is in `:due_date_set`, not in `:date_due`. Inflected forms are not
matched.

`mix eh_os_contract.glossary` lists, under each term, its word in code and the declarations of the context's
contracts named with it, then each process module that includes the context's events and whose id, stages,
promises or `correlate` fields are named with it. `mix eh_os_contract.check` reads the names of things (units,
read models and fields) both ways:

- **`word-without-term`** (notice): one finding per context. It lists the words in the context's names that
  no term covers, starting with the word used by the most names. Words of 1 or 2 letters (`id`, `at`) are left
  out, and so are names of commands and events, whose verbs are inflected ("returned") where a term is not ("Return").
- **`term-of-another-context`** (warning): a name uses the word in code of a term another context declares,
  and no term of its own context covers it. Either the word means something here too and the glossary should
  say what, or the name borrows the other context's meaning. One finding per name. The check skips a field typed
  `{:id, entity}` or named like the identity of another context's unit (`loan_id`): it refers to that
  declaration under its name. Neither rule reads the words of a field that name the value it is typed with:
  a field `:office_nip` of type `:nip` says "nip" as the value's word, shared by every context that uses the
  value, so no context has to copy another's term for it.

## Relations between contexts

A relation says how two contexts depend on each other: one of the 8 context-mapping patterns. Of these, 5 are
directed, with an upstream the other side depends on and a downstream that depends on it:

| Type | What it says |
| --- | --- |
| `:customer_supplier` | the downstream asks, the upstream plans what it supplies with it |
| `:conformist` | the downstream takes the upstream's model as it is |
| `:anticorruption_layer` | the downstream translates the upstream's model into its own |
| `:open_host_service` | the upstream offers a protocol for any downstream |
| `:published_language` | the two exchange a documented, shared language |

The other 3 are symmetric and name their 2 contexts with `between:`. On the context map a directed relation is an
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

One end of a directed relation may be an external system; the other end is then a context:
`relation :anticorruption_layer, upstream: :payment_provider, downstream: :loans`. A symmetric relation is
between contexts only. A relation whose roles do not fit its type, an end the domain does not declare, a
context related to itself, or a word of `terms:` its context's glossary does not define does not compile
([`D5`](../contract.md#refusals-d)); a relation declared twice does not either ([`D1`](../contract.md#refusals-d)).

### What a relation lets through

A relation is a rule the contracts are held to, not a drawing. A contract of one context depends on another
when it consumes a contract of it, names an entity or a unit it owns (`{:id, name}`), or uses a value it
declares (`value …, context:`). Such a reference has to follow the relation between the two:

| Relation | What a contract of the downstream context may consume from one of the upstream |
| --- | --- |
| `:customer_supplier`, `:conformist`, `:partnership`, `:shared_kernel` | any event |
| `:anticorruption_layer` | an event only a policy takes, translating it into a command of its own context |
| `:open_host_service`, `:published_language` | only the events the upstream contract `publish`es |
| `:separate_ways` | nothing, and nothing else crosses either |

A reference from the upstream context into the downstream one, or any reference across `:separate_ways`,
does not compile ([`X11`](../contract.md#refusals-x)); nor does a read model, an effect or a process manager
taking an event, or a boundary consulting one, across an `:anticorruption_layer` ([`X12`](../contract.md#refusals-x)), nor a contract consuming
an event its upstream sibling does not publish across an `:open_host_service` or a `:published_language`
([`X13`](../contract.md#refusals-x)). In one application the published event is still taken from the log, whole;
another application takes it by its name on the wire, with only the fields it declares. Including an event in a
process module is no reference: a process belongs to no context.

## A contract belongs to one context

Every contract names its context,
`use EhOsContract.Contract, domain: Lending.Domain, context: :loans, id: "lending.loans"`, and a context the domain does not declare is refused ([`X1`](../contract.md#refusals-x)). One context, because a
contract is written in one language: its labels are that context's words, its actors are that context's (an
actor declared with another `context:` is refused in `by:`, [`X2`](../contract.md#refusals-x)), and its glossary is the one its labels are
read against.

A contract reaches into another context in two ways, and each is a dependency between the contexts:

- it **consumes** a contract of another context, `consumes Lending.Contracts.Catalogue, [:item_withdrawn]`,
  and reacts to its events;
- it **names an entity another context owns**, a field `{:id, :copy}` where `:copy` belongs to the
  catalogue.

A policy or a read model left without `delivery` runs inside the transaction of the context that decided the
event it takes (an effect and a process manager run after it). So one taking an event of a sibling of another context has to
declare its `delivery` ([`X10`](../contract.md#refusals-x)): `:at_least_once` decouples the two, `:in_transaction` couples them on purpose.

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

The domain's own rules ([`D1`](../contract.md#refusals-d) to [`D7`](../contract.md#refusals-d)) and the rules between a contract and its domain ([`X1`](../contract.md#refusals-x), [`X2`](../contract.md#refusals-x)) are in the
table of [Writing a domain and a contract](../contract.md). The ones this page is about:

- **[`D1`](../contract.md#refusals-d)**: a name not snake_case, two subdomains or contexts of one name, a term defined twice in a
  context, a relation declared twice, a name that is both a context and an external, a blank label.
- **[`D2`](../contract.md#refusals-d)**: two translations of one term into one language, or one into the context's own.
- **[`D5`](../contract.md#refusals-d)**: a relation whose roles do not fit its type, an undeclared end, an external in a symmetric
  relation, a context related to itself, a word of `terms:` not in its context's glossary.
- **[`D7`](../contract.md#refusals-d)**: a context in a subdomain the domain does not declare.
- **[`X1`](../contract.md#refusals-x)**: a contract's `context:` naming none of its domain's contexts.
- **[`X2`](../contract.md#refusals-x)**: a contract's `by:`, `recorded_by:` or scenario actor naming an actor of another context.
- **[`X10`](../contract.md#refusals-x)**: a policy or a read model taking an event of a sibling contract of another context without
  declaring `delivery`.
- **[`X11`](../contract.md#refusals-x)**, **[`X12`](../contract.md#refusals-x)**, **[`X13`](../contract.md#refusals-x)**: a
  reference against the relation between two contexts, or more than its pattern lets through (above).

## What `mix eh_os_contract.check` reports

A domain that compiles may still describe a business its contracts do not have. These are warnings
([the rules](../rules.md)):

- **`subdomain-without-bounded-context`** (warning): no context names the subdomain with `subdomain:`. Give
  it a context, or remove it.
- **`bounded-context-without-content`** (warning): no contract names the context as its `context:`, so
  nothing is decided, recorded or read there. Values and entities the context owns do not count. In the
  example, the catalogue is reported until a contract belongs to it; that is expected until its contract is
  written.
- **`orphan-context-mapping`** (warning): a relation that no reference crosses: no contract of one context
  consumes a contract of the other, names an entity or a unit it owns or uses a value it declares, in either
  direction. For a relation to an
  external system, no contract of the context calls it, depends on it, has a field it issues or acts through
  an actor it backs. The relation describes a dependency the contracts do not have.
- **`cross-bounded-context-reference-without-mapping`** (warning): the other way round: a contract consumes
  a contract of another context, names an entity or a unit another context owns, or uses a value it declares,
  and no relation connects the two contexts. Declare the relation, which says who depends on whom. One finding
  per reference. A domain may be mapped a piece at a time, so this one warns; a reference against a relation
  that is declared does not compile (above).
- **`label-with-avoided-term`** (warning): a label of a contract uses a word its context's glossary says to
  avoid. In the example, an event of the loans contract labelled "Borrowing recorded" is reported. Every
  declaration's label and every enum member's label is read; a word matches whole, in any letter case, and
  not inside the term itself. Inflected forms are not caught, so `avoid` names each form to avoid. The check skips
  words a translation avoids: they belong to another language, and labels are not written in it.
