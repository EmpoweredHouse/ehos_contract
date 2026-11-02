# How does a domain divide a business into contexts?

<!-- covers: entities domain.subdomain, domain.context, domain.context.term, domain.relation; rules subdomain-without-bounded-context, bounded-context-without-content, orphan-context-mapping, label-with-avoided-term, word-without-term, term-of-another-context, cross-bounded-context-reference-without-mapping -->

This page tells how a domain divides a business into subdomains and contexts, and how the contexts
depend on each other. It is for a developer who writes a domain, and for a person who reviews its
words. [The glossary](glossary.md) defines each word in italics.

## What is a domain?

A *domain* is a module that holds the words that its contracts share. Nothing in it runs. It
contains these declarations:

- the parts of the business: subdomains and contexts;
- the words of each part: the glossary of each context;
- how the contexts depend on each other: the relations;
- the actors, the values, the entities and the external systems, which
  [What are actors, values, entities and external systems?](domain-data.md) tells about;
- the subjects of personal data, which
  [How does the engine keep and erase personal data?](personal-data.md) tells about.

Each contract names its domain, for example `domain: Lending.Domain`. After Elixir compiles the
project, the compiler `:eh_os_contract` checks each contract against its domain.

<!-- in: Concepts.Domain.Domain -->
```elixir
use EhOsContract.Domain, name: :lending, language: :en, time_zone: "Europe/Warsaw"
```

- `name:` is the namespace of the application. It is the first segment of each capability, role,
  contract id and published event name.
- `language:` is the language of the labels and the terms.
- `code_language:` is the language of the identifiers. It is English if you do not give it. The
  check compares the names in the code with the glossary in this language.
- `time_zone:` is the zone of the business days.

[The domain reference](dsl/domain-dsl.md) lists each key.
[The compile refusals](refusals.md#refusals-d) list what the compiler refuses in a domain.

An application usually has one domain. It can have more than one, each with its own contracts. The
tasks that read one domain then need `--domain` to name it.

With `consumes`, a contract takes only the events that sibling contracts of its own domain declare
([`X5`](refusals.md#refusals-x)). An event of another domain, or of another application, arrives
through `subscribe`.

If the application uses `eh_os_contract_auth`, only one domain can publish: the domain whose
`name:` is exactly the name of the application. The platform that issues the credentials accepts a
publication only under the name of the application. For the application `my-shop`, the name is
`:"my-shop"`, not `:my_shop`.

## What is a subdomain?

A *subdomain* is a part of the business, with the name that the business uses. It has one of three
kinds:

| Kind | What it is |
| --- | --- |
| `:core` | What the business competes on. The model of a core subdomain needs the most care. |
| `:supporting` | What the core needs, and no vendor sells ready to use. |
| `:generic` | What each business does in the same way, and can buy. |

<!-- in: Concepts.Domain.Domain -->
```elixir
subdomain :lending, "Lending", type: :core
subdomain :cataloguing, "Cataloguing", type: :supporting
```

A subdomain holds nothing itself. Each context names the subdomain that it belongs to. The compiler
refuses a context in a subdomain that the domain does not declare
([`D7`](refusals.md#refusals-d)).

`mix eh_os_contract.graph --domain <domain>` writes the graph document of the domain. It holds each
subdomain with its kind. The context map of the dashboard draws each subdomain as a group of its
contexts. No code reads the kind at run time.

If no context names a subdomain, `mix eh_os_contract.check` warns
`subdomain-without-bounded-context`. Give the subdomain a context, or remove it.

## What is a context, and what is its glossary?

A *context* is a part of the domain in which each word has one meaning. Also called a bounded
context. Example: at the loan desk, "Copy" is an item that a member can take home. In the catalogue,
an item is anything on the shelf, which the desk can lend or not. Two contexts let one word have two
meanings, and both meanings are correct.

<!-- in: Concepts.Domain.Domain -->
```elixir
context :loans, "Loans", subdomain: :lending do
  term "Copy", definition: "An item a member may take home"

  term "Loan", definition: "A copy lent to a member until it is returned" do
    avoid "Borrowing", reason: "The desk lends; the member borrows"
  end
end
```

- `subdomain:` is required. It names the subdomain of the context.
- `language:` is optional. Give it when the labels of the context are in a language other than the
  language of the domain.
- The block of the context holds its glossary. Each `term` is one word, with its `definition` in
  this context. A term can also give the `source` of the definition.
- `avoid` names a word not to use for the term, with its reason.
- `translation :de, "Ausleihe", definition: "…"` gives the word in another language, with its
  meaning there. A translation can avoid words of its own language.

The compiler refuses these glossaries:

- a term that the context defines two times ([`D1`](refusals.md#refusals-d));
- two translations of one term into the same language ([`D2`](refusals.md#refusals-d));
- a translation into the language of the context itself ([`D2`](refusals.md#refusals-d)).

`mix eh_os_contract.glossary` prints the glossary of each context, with the words to avoid and the
translations. With `--language en`, it prints each term in English, or says that the term has no
English translation.

If a label of a contract uses a word that its glossary avoids, the check warns
`label-with-avoided-term`. Example: the loans contract labels an event "Borrowing recorded". The
check reads the label of each declaration and of each member of an enum. It matches a whole word, in
each letter case. It does not find an inflected form, so `avoid` names each form to avoid. It
does not read the words that a translation avoids: they are of another language, and the labels are
not in that language.

If no contract names a context in `context:`, the check warns `bounded-context-without-content`.
The values and the entities of the context do not count. In the example at the end of this page,
the catalogue gets this warning until a contract belongs to it.

### How does the check compare names with the glossary?

The labels are in the language of the context. The identifiers are in the `code_language:` of the
domain. The word in code of a term is its translation into that language. If the context is in
that language, the word in code is the term itself.

Example: the term "Ausleihe" has `translation :en, "Loan"`, so its word in code is `loan`. The
names `:loan`, `:loan_id` and `:return_loan` use it. A term of several words matches as those
words in a row: "Due date" is in `:due_date_set`, but not in `:date_due`. The check does not match
inflected forms.

`mix eh_os_contract.glossary` shows the word in code of each term. Under it, the task lists:

- the declarations of the contracts of the context that use the word in their names;
- each process module that includes events of the context and uses the word in its id, its stages,
  its promises or its `correlate` fields.

`mix eh_os_contract.check` reads the names of units, read models and fields in two directions:

- `word-without-term` (a notice): a word in the names of a context that no term covers. The
  check gives one finding for each context.
- `term-of-another-context` (a warning): a name uses the word in code of a term of another context,
  and no term of its own context covers it. Either the word has a meaning here too, and the glossary
  must say it, or the name borrows the meaning of the other context.

[The rules of the check](rules.md) tell which names each rule does not read.

## How do two contexts relate?

A *relation* tells how two contexts depend on each other. It has one of 8 patterns. Five patterns
are directed: the downstream context depends on the upstream context. Three patterns are
symmetric.

| Pattern | Direction | What it says | What a contract can consume across it |
| --- | --- | --- | --- |
| `:customer_supplier` | directed | The downstream asks. The upstream plans what it supplies. | each event of the upstream |
| `:conformist` | directed | The downstream uses the model of the upstream as it is. | each event of the upstream |
| `:anticorruption_layer` | directed | The downstream translates the model of the upstream into its own model. | an event that only a policy takes, to issue a command of its own context |
| `:open_host_service` | directed | The upstream gives a protocol for each downstream. | only the events that the upstream contract publishes |
| `:published_language` | directed | The two contexts exchange a documented, shared language. | only the events that the upstream contract publishes |
| `:partnership` | symmetric | The two contexts succeed or fail together, and plan together. | each event, in both directions |
| `:shared_kernel` | symmetric | The two contexts share a part of the model. | each event, in both directions |
| `:separate_ways` | symmetric | The two contexts do not depend on each other. | nothing, in either direction |

<!-- in: Concepts.Domain.Domain -->
```elixir
relation :customer_supplier, upstream: :catalogue, downstream: :loans, terms: [{"Item", "Copy"}]
relation :separate_ways, between: [:loans, :events]
```

- A directed relation names `upstream:` and `downstream:`. A symmetric relation names its two
  contexts in `between:`.
- `terms:` pairs the words that the two ends use for one thing. The first word is of the upstream,
  or of the first context in `between:`. Each word is a term of the glossary of its context. The
  glossary then shows, under a term, the word of the other end.
- One end of a directed relation can be an external system. Then the other end is a context:
  `relation :anticorruption_layer, upstream: :payment_provider, downstream: :loans`. A symmetric
  relation has only contexts.
- On the context map of the dashboard, a directed relation is an arrow from the upstream to the
  downstream. A symmetric relation is a line. `:separate_ways` is a dashed line.

The compiler refuses these relations ([`D5`](refusals.md#refusals-d)):

- roles that do not fit the pattern, directed or symmetric;
- an end that the domain does not declare;
- an external system in a symmetric relation, or a directed relation with no context at either end;
- a context in a relation with itself;
- a word of `terms:` that the glossary of its context does not define.

It also refuses a relation that the domain declares two times ([`D1`](refusals.md#refusals-d)).

### What does a relation let through?

A relation is a rule for the contracts. A contract of one context makes a reference to another
context when it does one of these things:

- it consumes a contract of the other context;
- it names an entity or a unit that the other context owns, with a field of type `{:id, name}`;
- it uses a value that the other context declares, with `value …, context:`.

Each reference must agree with the relation between the two contexts. The compiler refuses these
references:

- a reference from the upstream context into its downstream context, or across `:separate_ways`
  ([`X11`](refusals.md#refusals-x));
- across an `:anticorruption_layer`, a read model, an effect or a process manager that takes an event
  of the upstream ([`X12`](refusals.md#refusals-x));
- across an `:anticorruption_layer`, a boundary that consults an event of the upstream
  ([`X12`](refusals.md#refusals-x));
- across an `:open_host_service` or a `:published_language`, an event that the upstream contract does
  not publish ([`X13`](refusals.md#refusals-x)).

In one application, a contract takes a published event from the log, with all of its fields.
Another application takes the event by its published name, with only the fields that the
publication declares.

A process module makes no reference when it includes an event: a process belongs to no context.

The check compares the relations with the references:

- If a contract makes a reference and no relation connects the two contexts, the check warns
  `cross-bounded-context-reference-without-mapping`. Declare the relation, so that the domain says
  which context depends on which. The check gives one finding for each reference. You can map a
  domain one part at a time, so this is a warning and not a refusal.
- If no reference crosses a relation in either direction, the check warns
  `orphan-context-mapping`. A `:separate_ways` relation is not checked: the compiler refuses a
  reference across it. For a relation to an external system, the check looks for a contract
  of the context that uses the system. The contract calls the system, depends on it, has a field that
  the system issues, or acts through an actor that the system backs.

## Why does a contract belong to one context?

Each contract names its context:
`use EhOsContract.Contract, domain: Lending.Domain, context: :loans, id: "lending.loans"`. The
compiler refuses a context that the domain does not declare ([`X1`](refusals.md#refusals-x)).

A contract has one context because it uses one language:

- its labels are the words of that context, and the check reads them against its glossary;
- its actors are of that context. The compiler refuses an actor of another context in `by:`, in
  `recorded_by:` or as the actor of a scenario ([`X2`](refusals.md#refusals-x)).

A contract of one context reaches into another context in three ways. Each way is a dependency
between the two contexts:

- it consumes a contract of the other context, for example
  `consumes Lending.Contracts.Catalogue, [:item_withdrawn]`, and reacts to its events;
- it names an entity or a unit that the other context owns, for example a field `{:id, :copy}`,
  where the catalogue owns `:copy`;
- it uses a value that the other context declares with `context:`.

A policy or a read model without `delivery` runs in the transaction of the contract that decided its
event. An effect and a process manager run after that transaction. So a policy or a read model that
takes an event of a sibling contract of another context must declare its `delivery`
([`X10`](refusals.md#refusals-x)). `:at_least_once` keeps the two contexts apart.
`:in_transaction` couples them, on purpose.

## An example

The loan desk depends on the catalogue: a loan names the copy that it lends, and the catalogue owns
the copy.

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

<a id="which-context-depends-on-which"></a>

### Which context depends on which?

![Loans depends on the catalogue, because a loan names a copy that the catalogue owns; library events and loans go separate ways.](img/domain-contexts.svg)

1. Loans depends on the catalogue: a customer–supplier relation. It makes the catalogue the upstream
   and the loans the downstream. So a contract of the loans context can make references to the
   catalogue, and the catalogue cannot make references to the loans.
2. The catalogue owns the entity copy: the domain declares `:copy` with `context: :catalogue`.
3. A field of the loans contract names a copy: `open_loan` and `loan_opened` have a field of type
   `{:id, :copy}`. This field is the reference that the relation lets through.

Library events and loans go separate ways. No contract of one can make a reference to the other.

## Next steps

- [What are actors, values, entities and external systems?](domain-data.md): the other declarations
  of a domain.
- [How does the engine keep and erase personal data?](personal-data.md): the subjects,
  and what the engine does with their personal data.
- [Write a domain, a contract and a process module](contract.md): the full task.
- [The compile refusals](refusals.md#refusals-d): each refusal of a domain, and of a contract
  against its domain ([`X`](refusals.md#refusals-x)).
- [The rules of the check](rules.md): each warning and notice of `mix eh_os_contract.check`.
