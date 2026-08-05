# Writing a PNS contract

A contract is an Elixir module that states what a business process is supposed to
do. The engine reads it twice — at compile time, to refuse code that contradicts
it, and at runtime, to compare what the log recorded against what was agreed.

If you know `Ecto.Schema`, you already have the mental model. `Ecto.Schema`
declares the shape of **rows that are stored**; `PNS.Contract` declares the shape
of **facts that happened**. Both are declarations a machine reads, and both
generate query functions you did not write.

```elixir
schema "users" do        # a stored row has an email
  field :email, :string
end

event :invoice_issued,   # a fact that happened carries an invoice id
  label: "Faktura wystawiona",
  payload: %{invoice_id: :id}
```

## The smallest contract that compiles

Everything below is optional or has a fallback. This is the floor:

```elixir
defmodule Docs.MinimalContract do
  use PNS.Contract

  event :case_opened,
    label: "Sprawa otwarta",
    payload: %{case_id: :id},
    process: :handling

  event :case_closed,
    label: "Sprawa zamknięta",
    payload: %{case_id: :id},
    process: :handling,
    terminal: true

  process :handling,
    label: "Obsługa sprawy",
    instance: [:case_id]
end
```

This example is compiled by `test/docs_test.exs`. It cannot rot, for the same
reason a `rule` cannot exist without an `example`: documentation that is not
executed is documentation nobody has checked.

**Declaration order does not matter.** Validation runs at `@before_compile`, once
the whole module is known, so an `event` may name a `process:` declared fifty
lines below it. Group declarations however reads best.

## The six declarations

| Declaration | States |
| --- | --- |
| `event` | a fact that happened, named in the past tense |
| `process` | a run those facts belong to — start, middle, end |
| `trace` | an assertion an observed run must satisfy |
| `external` | a dependency outside this system, named as a business fact |
| `rule` | one pure function that decides something |
| `example` | a case that pins a rule, readable aloud and executable |

## Key reference

Generated from `PNS.Contract.schema/0` by `mix pns.docs`. Do not edit by hand —
`mix check` fails if this block is stale.

<!-- pns:reference:start -->
### `event`

| Key | Required | Omitted means |
| --- | --- | --- |
| `label` | yes | — |
| `owner` | no | `nil` |
| `payload` | no | `%{}` |
| `retain` | no | `%{}` |
| `depends_on` | no | `nil` |
| `identity` | no | `nil` |
| `process` | no | `nil` |
| `stage` | no | `nil` |
| `terminal` | no | `false` |

### `process`

| Key | Required | Omitted means |
| --- | --- | --- |
| `label` | yes | — |
| `instance` | yes | — |
| `stages` | no | `[]` |
| `cadence` | no | `nil` |
| `deadline` | no | `nil` |
| `unverified` | no | `[]` |

### `trace`

| Key | Required | Omitted means |
| --- | --- | --- |
| `from` | yes | — |
| `eventually` | yes | — |
| `within` | no | `nil` |
| `or_else` | no | `nil` |

### `external`

| Key | Required | Omitted means |
| --- | --- | --- |
| `label` | yes | — |
| `expected_latency` | no | `nil` |
| `unavailable_looks_like` | no | `nil` |

### `rule`

| Key | Required | Omitted means |
| --- | --- | --- |
| `label` | yes | — |
| `function` | yes | — |
| `source` | no | `nil` |

### `example`

| Key | Required | Omitted means |
| --- | --- | --- |
| `rule` | yes | — |
| `command` | yes | — |
| `given` | no | `%{}` |
| `then` | no | `nil` |
| `rejected_with` | no | `nil` |
<!-- pns:reference:end -->

## What each key means, and which mechanism needs it

A key with no reader is decoration. This table names the reader, so decoration is
visible rather than implied.

### `event`

| Key | Meaning | Read by |
| --- | --- | --- |
| `label` | The business name. `invoice_issued` means nothing to an accountant, and the accountant is who confirms the process. **Written in the client's language** — the only place where that is true. | the client-facing report |
| `payload` | Field name to type. The engine casts keys back to atoms after a JSON round trip through the queue and the database, so synchronous and asynchronous handlers see one shape. | `PNS.Payload`, three compile gates, the retention check |
| `owner` | Which module owns this fact. | `mix pns.check` reports an owner that does not exist as a module — as `info`, because the owner of an unimplemented phase is a normal state |
| `retain` | Per field: `:persist` (default), `:hash`, `:drop`. Applied **once, before anything else**, so what comes out is the only version in the system — log, handlers and job arguments alike. A retention policy the queue can bypass looks satisfied and is not. | `PNS.Emitter` |
| `identity` | What makes two occurrences **the same fact**. This is the idempotency key. It must include what *distinguishes* facts, not only what groups them. | `PNS.Job`; an asynchronous handler on an event without it does not compile |
| `depends_on` | Which `external` this fact relies on. | compile gate; the runtime answer does not exist yet — see *Known decoration* |
| `process` | Which run this fact belongs to. A single key, so belonging to two processes is not expressible. | `PNS.Instance`, `PNS.Graph`, `PNS.Check` |
| `stage` | Which phase of that process. | backward-edge detection in `PNS.Check` |
| `terminal` | The process ends here. Being blocked counts: a run that ended badly still ended. | `mix pns.check`, `PNS.Graph` |

### `process`

| Key | Meaning | Read by |
| --- | --- | --- |
| `label` | The business name of the run. | the report |
| `instance` | Payload fields that say **which run** an event belongs to. Required, because both things that make this a product — assertion evaluation and the declared-versus-observed overlay — are counted within a run. | `PNS.Instance`, `PNS.Trace`, `PNS.Conformance` |
| `stages` | The order **between** phases, and nothing about order inside one. Omit it and the process has one phase and makes no claim about sequence; its events then carry no `stage`. | `PNS.Check` |
| `cadence` | How often a run is due. Only meaningful for calendar-driven processes — an event-driven one has none. | nothing yet — see *Known decoration* |
| `deadline` | How long a run may take. | nothing yet — see *Known decoration* |
| `unverified` | Declarations the **process owner has not confirmed**. They stay, because the mechanism needs something to watch, but they must not count toward the evidence report: a false metric is worse than a missing one when it is the metric the product sells. | `mix pns.check`, every run |

### `trace`

```elixir
trace :month_opens_or_is_blocked do
  from :data_completeness_confirmed
  eventually :accounting_month_opened, within: {2, :day}
  or_else :discrepancy_notification_sent
end
```

Read it aloud: *after completeness is confirmed, within two days the month opens
— or a discrepancy notice goes out.* That sentence is what a process owner
confirms or corrects.

`from`, `eventually` and `or_else` are **not functions**. The macro takes the
block apart at compile time; nothing of it exists at runtime.

Three semantics worth knowing before you write one, each of which can be got
wrong without breaking anything visible:

- The window runs from the **first** occurrence of `from`. From the last, a run
  could outrun its deadline forever by re-emitting `from`.
- `within` applies to `or_else` too. Otherwise a run correctly ended three months
  late counts as satisfied.
- A run without `from` is **not evaluated**. Neither satisfied nor violated —
  there is nothing to rule on.

`within` takes fixed-length units only (`PNS.Duration`). Calendar units are
rejected at compile time, because a month has no fixed length and shifting by one
requires deciding what follows 31 January.

### `external`, `rule`, `example`

`external` names a dependency by the **business fact**, not the vendor — "public
registries", not "CEIDG API v2". The declaration should still mean the same thing
when the system behind it is replaced.

`rule` points at exactly one pure function, as an **MFA tuple, never a capture**.
A capture would make the contract depend on the domain at compile time, and since
handlers depend on the contract, every domain change would recompile all of them.

`example` pins a rule with a case that is readable aloud and executable. **A rule
without an example does not compile.** `then:` means "among the emitted events, in
this order" rather than "exactly these", so adding an event to a flow does not
invalidate every example of every rule.

## What refuses to compile

Every row below is a real compile error with a test in
`test/compile_gates_test.exs`. If you are generating a contract, this is the list
to read: these are not conventions, they are things the compiler will not let you
write.

| Refused | Why |
| --- | --- |
| An unknown key in any declaration | the vocabulary is fixed; a new word is a design decision, not a convenience |
| `rule` without an `example` | a rule without a case is prose |
| `rule` with a capture instead of an MFA tuple | it would make the contract depend on the domain at compile time |
| `trace` naming an event that does not exist | the assertion could never be evaluated |
| `trace` without `from` or without `eventually` | half an assertion has nothing an observed run could satisfy |
| `trace` with a calendar unit in `within` | the evaluator cannot compute it, and failing at runtime means failing at the client |
| `trace` spanning two processes | each process has its own run identity |
| `process` without `instance` | nothing about the run could be counted |
| An event of a staged process without `stage` | backward-edge detection would have a hole |
| `stage` naming a phase the process does not declare | — |
| `stage` or `terminal` without `process` | a phase is a phase of something |
| `process` naming a process that does not exist | — |
| `identity` or `instance` naming a field absent from `payload` | the key could not be computed |
| `identity` or `instance` on a field with `retain: :drop` | the key would vanish with the field |
| `retain` naming a field absent from `payload` | — |
| `depends_on` naming an undeclared `external` | — |
| The same event declared twice | — |
| A handler on an event the contract does not declare | |
| A handler publishing an event the contract does not declare | |
| An asynchronous handler on an event without `identity` | the queue is at-least-once, so the event will arrive twice |

## Known decoration

Declarations the contract accepts and no mechanism reads yet. Listed because a
reference that hides its gaps is worse than one that admits them.

| Declaration | State |
| --- | --- |
| `deadline` | declared; no stalled-run monitor exists |
| `cadence` | declared; the "never observed" window is not computed from it |
| `external`'s `expected_latency` | declared; nothing measures latency |
| `external`'s `unavailable_looks_like` | declared; becomes real with the fourth assertion verdict, `:suspended` |
| `depends_on` at runtime | the compile gate works; the conformance answer does not exist |

## Two things the contract deliberately does not carry

**Who did it.** `actor` is a column on the event log, written by the engine and
carried across causation and job boundaries. It is true of every event in every
domain, so declaring it per event would be boilerplate that drifts. A payload
field duplicating it gives two sources of truth about one fact, which come apart
exactly when an audit needs them.

**Which contract version was in force.** `version/0` is a hash of the
declarations, computed at compile time and stamped on every event, so it cannot
be forgotten or hand-maintained. Note that it hashes the *contract* — paths come
from handlers, and those have their own identity in `PNS.Deployment`.
