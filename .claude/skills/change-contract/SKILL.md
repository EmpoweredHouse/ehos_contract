---
name: change-contract
description: Before editing a contract whose units, events or reactions may already have rows in the log — renaming, adding or removing a field, changing a type or an enum, `personal:`, a unit's identity, the process's `correlate`, a promise, a deadline, a command's name or `by:`, a reaction's declaration — classify what the change risks before touching code. The compiler catches one class for free; the rest compiles and still breaks history, because every stored event is decoded again by today's declaration whenever its stream is folded, and upcasters are not built. Produces a written impact analysis and the smallest edit that satisfies it. Use when modifying a contract that has declarations; not for its first version (see `contract-distillation` and `add-event`) and not for deciding whether something belongs in a contract at all (see `module-boundary-check`).
---

# Changing a contract that already exists

Checked on 30 September 2026 (plan E11e) against the engine's source —
`EhOsContract.Codec.decode/4`, `EhOsContract.Consumer.decode!/1`, `EhOsContract.Deployment`,
`EhOsContract.Conformance`, `EhOsContract.Subscription` — and `docs/adr/contract-v2.md` §7, §10.6 and
§13. Not yet run on a real change: read what it says against those before trusting it.

## Why this runs before the code

The log cannot be edited, only added to, and it is the source of the state: **an old row is read
again, by today's declaration, every time its stream is folded for a decision, every time an ordered
subscription, a process manager or an effect job takes it**. A row that no longer fits is not
skipped: decoding raises "no longer fits". Every command on that aggregate's stream fails — every
decision of a boundary that consults the type, whatever stream the row is in; an ordered
subscription stops at that position, `failing`; an effect job is retried three times and
discarded. A unit with no `evolve/2` never reads its history back, and one whose only catch-all is
`def evolve(state, _), do: state` reads back only the events it has a clause for: an old row of a
type it passes over is not decoded, so it breaks nothing. `schema_version` exists on
every event, but **no upcaster is built** (§10.6 describes one; nothing calls it), so there is no
way yet to carry old rows across a breaking change. By the time the compiler runs, the file already
says whatever it says — which is why the analysis comes first.

## What the compiler already catches

`packages/eh_os_contract/docs/contract.md`, "What will not compile", is the complete list with codes.
The ones a change most often trips, so you know not to reason about them:

- a reference to what the change removed — `emits:`, `rejects:`, `handles:`, `consults`, a promise's
  events, a scenario's data (`A1`, `A3`, `P1`, `A4`, `R5`, `S3`–`S5`);
- a sibling that uses a field the change removed or retyped in `correlate`, `match` or `include`
  (`X6`), and every implementation that matches on the changed struct, since expanding a struct is a
  compile dependency (§7);
- an invariant without a `rejected` scenario (`S8`).

Everything in the table below compiles.

## The table

"Seen" says whether the next deploy's `EhOsContract.Deployment.diff/2` names it. Every declaration
has its own digest there (`declarations: added / removed / changed`, keyed `"<kind>:<name>"`), and
any edit — a label and a `source:` included — moves the contract's version. The diff is only as good
as its rows: before `declaration_digests` were recorded it answers `:not_recorded`.

| Change | Seen | What it does to history |
| --- | --- | --- |
| A label, `source:`, a scenario's description | `changed` | Nothing functional. A version moved by wording alone is not a red flag. |
| A new unit, command, event, reaction, read model | `added` | Additive. A new policy starts at the head and does not react to history; a new ordered read model projects it from position 0 (`write-reaction`). |
| A new **optional** field on an event | `changed` | Compatible: old rows read back with `nil`. |
| A new **required** field on an event | `changed` | **Every old row of that type fails to decode** (`:required`), with the consequences above. With history: make it optional, or a new event. |
| A field removed from an event | `changed` | Old rows still decode — an undeclared key is ignored on read. Personal values stay sealed in the log until their subject is erased. |
| A field's type changed; an enum member removed | `changed` | Old rows fail to decode (`:type`; a member the contract no longer declares does not fit) — unless every stored value also fits the new type: `:integer` to `:decimal`, `:id` to `:string`, a value of the same base type. Adding an enum member is compatible. |
| `personal:` added to, or removed from, a field | `changed` | Old rows fail to decode: clear text where a sealed value is expected, or the reverse. |
| An event renamed, removed, or moved to another contract | `removed` + `added` | The log stores the type as `"<contract id>.<event>"`. Folding a stream that holds the old type raises ("declares no event of type"); the report loses its runs. An event a person records has a capability, `<domain>.<event>`, and a rename withdraws its grant (see the command row). |
| The contract's `id:` changed | `removed` + `added` | Every event type is `"<id>.<event>"`, so a new id renames every type the contract records: folding a stream that holds the old types raises, and the report starts from nothing. Every row and key names the id too (plan DD, ID4, #178): subscriptions, process managers and their timers, relays and inboxes (an inbox's durable consumer on the bus), reaction and idempotency keys and queued effect jobs are left behind under the old one. With history: do not, or reset the engine's schema (#173, #178). |
| A unit renamed | `removed` + `added` | An aggregate reads its stream by id, the unit's name and its key values: old streams are left under their old ids, and the unit decides from an empty state — silently. A boundary reads by types and tags, not by its name. |
| A unit's `identity` changed | `changed` | For an aggregate, the same as a rename: new stream ids, an empty state. For a boundary, it now reads what the new tags select. |
| The contract module renamed | — | Rows and keys name the contract's `id:`, not its module (plan DD, ID4, #178), so its history stays. What still names the module: the conformance wire and the dashboard's APIs, until P1a. Implementations point at the contract by module, so they are renamed with it. |
| The process's `correlate` | `changed` | Runs are computed at append and stored; old events keep the runs they were given. A report across the change counts two keying schemes as one. |
| A new invariant or constraint | `changed` | History is never checked against it; a command that passed before may now be refused. `S8` asks for its `rejected` scenario. |
| A new invariant of a domain **value** | the domain's | History is not held to it, but a policy or a process manager that builds a command from an old event's value is refused, and the refusal rolls back the command that set it off, or stops an ordered consumer at that event (§6, D9). Look at the values in the log first. |
| A promise's `from`, `eventually`, `within` or `or_else` | `changed` | The report splits the runs judged under the earlier declaration from the deploy that changed it (`under_earlier_declaration`, `declaration_changed_at`). `unverified` and `source` do not move that boundary. |
| `deadline` | `changed` | No boundary: every past run is judged by the new number. Bound a report across the change by the deploy date. |
| `cadence` | `changed` | Shown in the report, not judged: nothing in the log changes meaning. |
| A command's `emits:`, a reaction's `handles:` or `issues:`, a timer | `changed`, paths | The declared paths change: a path removed stops being counted untraversed, a new one starts at zero runs. |
| Stages | `changed` | Nothing in the log; the order of stages decides what `backward-edge` warns of. |
| A `lifecycle` added to an aggregate with history, or its transitions changed | `changed` | Nothing is rewritten, and nothing fails to read: the status is computed from each stream's event names whenever it is read, by today's graph. A stream whose history does not fit — events before an `initial` one, a move the graph does not allow — keeps the status where the graph leaves it, and the conformance report (from LC3, #99) counts those events as undeclared, so the first report after the deploy shows the old history there. A command with a new `from:` may now be refused on aggregates that stand where the old code let it through. A new state field named `:status` is refused (`T1`): the status takes it, so drop the one `evolve/2` kept, and every pattern in the decider that read it now reads the engine's. |
| A read model's or a process manager's declaration, or the events it takes | `changed` | Its subscription is `stale`. A read model is rebuilt through its `reset/0`, and without one it stays stale; a process manager is rebuilt at boot, since the library owns its table. |
| A command renamed, or its `by:` changed | `removed` + `added`, or `changed` | Commands leave no payload in the log, so history is untouched — but a command a person may issue has a capability, `<domain>.<command>`, which EHOS grants to roles. A rename withdraws a grant every role has today; a changed `by:` changes who is given it. Host-visible: to the user first. |
| A required field added to a command | `changed` | No history, but every caller — the host's code, an HTTP client — is refused until it sends the field. |
| A `publish` changed | `changed` | Nothing refuses the edit, but a publication is another application's input: a changed field is a new versioned name, not an edit (`docs/adr/contract-v2.md` §7). A changed `idempotent_on:` changes the key of every message built after the deploy, so a fact published again after it — a batch retried across the deploy, a relay reset — can be taken once more under the new key; a redelivery of a message already sent keeps its key. |
| A `publish` renamed or removed | `removed` (+ `added`) | Its relay's row is keyed by the declaration's name (`"<contract>:relay:<name>"`), not by `as:`. Renamed, a new relay starts at the head of the log, and what the old one had not yet published — behind an outage, or with no bus configured — never leaves; the old row stays. Removed and added back later, it finds the old row and publishes everything since. Removing it stops the event leaving for every subscriber in force: in EHOS that is a breaking change (`eh-os` C-4). |
| A `subscribe "<name>.vN"` removed, or its policy | `removed` / `changed` | The inbox goes with the last policy that handles it, and so does `<name>.subscribe` unless a policy handles another version of the name; messages the transport keeps for the durable consumer wait unread until the grant is withdrawn. A field a subscriber stops reading changes nothing; one it starts reading must be in the publisher's version in force (`eh-os` C-3). |
| A `subscribe "<name>.vN"` given another `as:` | `removed` + `added` | The inbox is keyed `"<contract>:inbox:<as>"`, its durable consumer's name and the `consumer` of its rows: a new `as:` is a new consumer, which gets only what is published after it subscribes, while what waited for the old one goes unread, and facts the old one took are taken again if they come again. Keep `as:` once the inbox has run. |

## Check the data before calling a change free

For every row in the table that says "old rows", count them. The development database is the one to
read (`CLAUDE.md`: never `MIX_ENV=test mix run`):

```bash
docker compose exec -T postgres psql -U eh_os -d eh_os_contract_host_dev -c "select type, count(*) from eh_os_contract_events group by type order by type;"
```

Zero rows of the type means the change is still additive in fact. Anything else is a decision for the
user, with the count: a new event instead of a changed one, an optional field instead of a required
one, or data work written down in `PLAN.md` before the change.

## Non-negotiables

- **Work from a diff, not a regeneration.** State the change as "this declaration, this key, old
  value → new value". A rewritten module drops a `source:`, an `unverified: true` or a dated comment,
  and a resolved question quietly reopens.
- **No new key to paper over a missing one.** A category the DSL has no word for is a vocabulary
  decision for the user, with an example.
- **Host-visible shapes go to the user before they change**: a capability, a command's fields, a
  publication, a query's parameters (`PLAN.md`, strategy of stage 6).

## Procedure

1. Write the change as a diff against the committed declaration.
2. Compile. Whatever `packages/eh_os_contract/docs/contract.md`'s codes refuse is answered; fix it or drop that part.
3. Classify every changed key against the table.
4. For each row that touches history, count the rows of the type (above). For each host-visible
   row, ask the user.
5. Write the consequence into the commit message — what changed, what it costs, which deploy draws
   the boundary — so whoever reads a report across it knows.
6. Make the smallest edit, in the existing file.
7. Run the scenarios of the contract and the gate from `sandbox/`. Both pass silently on everything
   in the table, by construction: they are confirmation, not the analysis.

## Not this skill

Whether the changed model is the right one — that belongs to whoever confirmed the process.
Building upcasters, or a versioned history of deadlines — plan items, if they are ever needed; this
skill records that they do not exist.
