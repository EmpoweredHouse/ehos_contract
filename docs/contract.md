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
  label: "Invoice issued",
  payload: %{invoice_id: :id}
```

## The smallest contract that compiles

Everything below is optional or has a fallback. This is the floor:

```elixir
defmodule Docs.MinimalContract do
  use PNS.Contract

  event :case_opened,
    label: "Case opened",
    payload: %{case_id: :id},
    process: :handling

  event :case_closed,
    label: "Case closed",
    payload: %{case_id: :id},
    process: :handling,
    terminal: true

  process :handling,
    label: "Case handling",
    instance: [:case_id]
end
```

This example is compiled by `test/docs_test.exs`. It cannot rot, for the same
reason a `rule` cannot exist without an `example`: documentation that is not
executed is documentation nobody has checked.

**Declaration order does not matter.** Validation runs at `@before_compile`, once
the whole module is known, so an `event` may name a `process:` declared fifty
lines below it. Group declarations however reads best.

## The seven declarations

| Declaration | States |
| --- | --- |
| `event` | a fact that happened, named in the past tense |
| `process` | a run those facts belong to — start, middle, end |
| `trace` | an assertion an observed run must satisfy |
| `external` | a dependency outside this system, named as a business fact |
| `rule` | one pure function that decides something |
| `example` | a case that pins a rule, readable aloud and executable |
| `command` | a way into a process from outside, and who may take it |

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
| `accountable` | no | `nil` |

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

### `command`

| Key | Required | Omitted means |
| --- | --- | --- |
| `label` | yes | — |
| `process` | yes | — |
| `principals` | yes | — |
| `payload` | no | `%{}` |
| `source` | no | `nil` |

### payload types

| Type |
| --- |
| `:id` |
| `:string` |
| `:integer` |
| `:timestamp` |
| `:enum` |
<!-- pns:reference:end -->

## What each key means, and which mechanism needs it

A key with no reader is decoration. This table names the reader, so decoration is
visible rather than implied.

### `event`

| Key | Meaning | Read by |
| --- | --- | --- |
| `label` | The business name. `invoice_issued` means nothing to an accountant, and the accountant is who confirms the process. **Written in the client's language** — the only place where that is true. | the client-facing report |
| `payload` | Field name to type, from the closed set above — see *Payload types*. The engine casts keys back to atoms after a JSON round trip through the queue and the database, so synchronous and asynchronous handlers see one shape. | `PNS.Payload`, four compile gates, the retention check |
| `owner` | Which module owns this fact. | `mix pns.check` reports an owner that does not exist as a module — as `info`, because the owner of an unimplemented phase is a normal state |
| `retain` | Per field: `:persist` (default), `:hash`, `:drop`. Applied **once, before anything else**, so what comes out is the only version in the system — log, handlers and job arguments alike. A retention policy the queue can bypass looks satisfied and is not. | `PNS.Emitter` |
| `identity` | What makes two occurrences **the same fact**. This is the idempotency key. It must include what *distinguishes* facts, not only what groups them. | `PNS.Job`; an asynchronous handler on an event without it does not compile |
| `depends_on` | Which `external` this fact relies on. | compile gate, and `PNS.Trace`: if this dependency was seen unavailable inside an assertion window, the run is `:suspended` rather than in breach |
| `process` | Which run this fact belongs to. A single key, so belonging to two processes is not expressible. | `PNS.Instance`, `PNS.Graph`, `PNS.Check` |
| `stage` | Which phase of that process. | backward-edge detection in `PNS.Check` |
| `terminal` | The process ends here. Being blocked counts: a run that ended badly still ended. | `mix pns.check`, `PNS.Graph`, `PNS.Run` — a run's duration is measured to this event |

### `command`

| Key | Meaning | Read by |
| --- | --- | --- |
| `label` | The business name of the action, in the client's language. | the client-facing report |
| `process` | Which process this command enters. A command that started two processes would be two commands. | compile gate |
| `principals` | Which kinds of principal may issue it, from the closed set `[:human, :system]`. This derives the capability, and it answers level 2 only — *may this kind of caller issue this at all*. Whether *this* caller may issue it *for this subject* is level 3 and stays a `rule` with a decision function. | `PNS.Command.permits?/3` |
| `payload` | Field name to type, from the same closed set an event's payload uses. An `example`'s command params must supply exactly these keys. | compile gate |
| `source` | Where this command came from — a pointer into the workshop material a person can follow, in the same sense `rule` means it. Nothing reads it mechanically, and that is the point: it is provenance for whoever asks "who said this". An absent one is informative rather than untidy, because it says nobody has yet found this command in what the client actually said. | a person; and its digest, so correcting a citation is recorded as a change to the agreement |

There is deliberately **no `emits:` key.** What a command emits has two readings —
the events its decision function returns, and the events reachable from those
through handlers — and in this repository's own corpus they are identical for one
command and differ by three events for another, including the event that command is
named after. Both readings are already held elsewhere, by the examples and by the
handlers' `publishes:`. A third copy could not be checked for completeness by any
gate, only for the existence of its members, so it would be the first key in a
contract allowed to be wrong with nothing to notice.

#### Payload types

**Every type says something about the shape of a value and nothing about anybody's
business, and the set is closed so it stays that way.** A type that names a thing an
accountant recognises is this library knowing one client's domain — and that is not a
matter of taste, it is what makes the library a library.

| Type | Means | Accepts |
| --- | --- | --- |
| `:id` | An identifier of something. What it identifies is the client application's business, not ours — a period, an invoice, a patient are all `:id` here | Non-empty text, or an integer. A client keying on a database sequence should not have to call it a string |
| `:string` | **Text a human typed.** The only type the retention check reacts to: a `:string` field with no `retain` policy reaches the log verbatim | Text |
| `:integer` | A whole number: a count, an amount | An integer. `"5"` is refused rather than coerced — JSON carries integers, so text here is a caller passing the wrong thing |
| `:timestamp` | A point in time | A `DateTime`, or ISO 8601 text — which is normalised to a `DateTime` before any handler sees it |
| `:enum` | One of a fixed set | Bare `:enum`: any atom or text — the set is unconstrained, which is a legitimate choice, not only a gap. `{:enum, [...]}`: an atom or text that is a **member of the declared list** — fixed 21 August 2026, see `test/payload_edges_test.exs` |

**These are enforced at emit time, not only described.** A declared field that is
missing, holds `nil`, or holds the wrong shape refuses the emission and nothing reaches
the log. An undeclared *extra* field is kept rather than refused: one spare key is
visible in the log, while a missing one is silence.

Two rules about when, both of which were wrong on the first attempt:

**Validation runs on the payload as supplied, before `retain`.** `retain` is a storage
policy applied afterwards, and it transforms the value — `:hash` turns anything into a
hex string, so a `:string` field could never fail and an `:integer` field could never
pass, and `:drop` removes the field, so a declared field would be permanently missing.
A type describes the fact; `retain` describes what the log keeps of it. Dropping a field
does not excuse the caller from declaring it correctly.

**Nothing validates on the way out.** The log holds events written under contracts that
have since changed, and a report that cannot read history is worse than one that reads
it loosely. Strict on write, defensive on read.

There is no `:period`, and it was here for two days. It looked like a general type and
named an accounting month, which is exactly the failure this table exists to prevent.
The universality gate did not catch it, because that gate asks whether describing a
second domain forced a **new** word, never whether one of the existing words is
surplus — counting caught it: the second contract has fourteen payload fields and used
`:period` zero times. **If your type names a thing rather than a shape, it is `:id`.**

### `process`

| Key | Meaning | Read by |
| --- | --- | --- |
| `label` | The business name of the run. | the report |
| `instance` | Payload fields that say **which run** an event belongs to. Required, because both things that make this a product — assertion evaluation and the declared-versus-observed overlay — are counted within a run. | `PNS.Instance`, `PNS.Trace`, `PNS.Conformance` |
| `stages` | The order **between** phases, and nothing about order inside one. Omit it and the process has one phase and makes no claim about sequence; its events then carry no `stage`. | `PNS.Check` |
| `cadence` | How often a run is due. Only meaningful for calendar-driven processes — an event-driven one has none. | the report, for the declaration itself — see *Known decoration* for what still does not read it |
| `deadline` | How long a run may take, from the run's earliest event to its `terminal: true` one. | `PNS.Run`, and the report — a count of the runs that exceeded it, plus a separate line for runs still open and already past it |
| `unverified` | Declarations the **process owner has not confirmed**. They stay, because the mechanism needs something to watch, but they must not count toward the evidence report: a false metric is worse than a missing one when it is the metric the product sells. | `mix pns.check`, every run |
| `accountable` | The role a finding about this process is addressed to. A role, not a person and not a module — `owner` on an event answers "which module implements this fact" and holds a module, which is why these are two words and not one. | the report; `mix pns.check` warns when a process names none |

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
| A `payload` field with a type outside the closed set | a type that names a thing rather than a shape is the library knowing one client's domain |
| `{:enum, [...]}` with an empty list, a member that is not an atom or text, or the same member twice (as an atom or as text) | an enum with nothing legal in it, or a name that cannot resolve, is not a set |
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
| The same command declared twice | the capability is derived from the name, so one permission would authorise two things |
| `command` naming a process the contract does not declare | nothing could read it |
| `principals` empty, or naming anything outside `[:human, :system]` | the set is closed; a command nobody may issue is a forgotten key, not a narrower permission |
| `example` naming a command the contract does not declare | the third pointer gate, beside `example`'s rule and `event`'s `depends_on` |
| `example` supplying a different set of command params than the command declares | this DSL has no optional fields, so a mismatch means one of the two is wrong |

## Known decoration

Declarations the contract accepts and no mechanism reads yet. Listed because a
reference that hides its gaps is worse than one that admits them.

| Declaration | State |
| --- | --- |
| `cadence` | declared, and read by the report for the declaration itself. The "never observed" window **will not be built** — rejected 6 August, not merely undone; see `docs/adr/technology-notes.md` §9 |
| `external`'s `expected_latency` | declared; nothing measures latency |
| `external`'s `unavailable_looks_like` | **no longer decoration since 6 August** — `depends_on` plus an unavailability observation produces the fourth assertion verdict, `:suspended`. The sentence itself is still only read by a person |
| `depends_on` at runtime | **read since 6 August**: it decides which dependency's outage can suspend an assertion. Nothing yet measures whether a dependency is slow, only whether it was seen unavailable |

`deadline` left this table on 22 September, built exactly as narrowly as it was
planned on 6 August: a retrospective count in the periodic report, never a live
per-instance monitor. A process that declares one and marks no event `terminal: true`
has no observable ending, so nothing can be measured — `mix pns.check` says so as a
notice rather than leaving the silence unexplained.

Three rows left this table on 6 August: payload types are enforced at emit time, and
`depends_on` together with `unavailable_looks_like` now produce the `:suspended` verdict
instead of describing one. A fourth left on 21 August: `:enum`'s set now has somewhere to be
written down — `{:enum, [...]}`, see *Payload types* above — so declaring which names are legal is
no longer a gap, only something a contract can choose not to do. Bare `:enum` stays legal and
unconstrained; nothing existing was forced to declare a set it never had.

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
