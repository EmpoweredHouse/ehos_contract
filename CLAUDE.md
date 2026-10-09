# eh_os_contract — the library's repository

This is the repository of the `eh_os_contract` library: a contract of a business process, and two things built
on it — dispatching events for an event-driven application, and checking whether what happened matches what the
contract says. Other repositories install its packages from git (`sparse:`), later from Hex.

| Directory | What |
| --- | --- |
| `packages/eh_os_contract/` | **the library**: the contract DSL, dispatch, the log, conformance, `docs/contract.md` |
| `packages/eh_os_contract_web/` | the mountable dashboard |
| `packages/eh_os_contract_auth/` | verifying EHOS credentials, keys from JWKS (what to configure: its `README.md`) |
| `packages/eh_os_contract_graph/` | the graph renderer: a `graph.v1` document drawn in a LiveView, without the engine (plan E13b) |
| `sandbox/` | the development host `:eh_os_contract_host` and the test material: TaxVision, Rehmed, AppUnite equipment |
| `docs/` | the design record (`docs/adr/`), distillations and workshop material |

Each of the five is its own Mix project. The packages build and test on their own, without `sandbox/`, and that
is a property we keep: `sandbox/` is the library's first consumer, not part of it.

**`sandbox/` is not a product.** The library is. TaxVision (`sandbox/lib/taxvision/`), Rehmed
(`sandbox/lib/rehmed/`) and AppUnite's equipment (`sandbox/lib/appunite_equipment/`) are **test material**: each
has a domain, contracts and implementations that decide and react, so that dispatch and the report have
something to check. What writing a contract teaches goes into the library's work, not into notes about a
client, and a contract that cannot be written is a **better** result than one written beside the material. An
invented medical domain, `UniversalityGate`, lives in `packages/eh_os_contract/test/support/` and says so in its
first line.

Until 23 September the package was called `pns` (`PNS.*`, host `:pns_prototype`, tables `pns_*`). Everything in
the code has the new name; the old one remains only in `docs/adr/` and in `PLAN.md`'s history, where `PNS.X`
means today's `EhOsContract.X`.

## Before you change anything

| What | Where |
| --- | --- |
| How work is planned, recorded and reviewed, for a person and an assistant alike: where each thing lives, from an idea to `main`, how to follow a line of code back to its reason | [`CONTRIBUTING.md`](CONTRIBUTING.md) |
| The programmes, their stages and **their status** | [`PLAN.md`](PLAN.md), the "Postęp" table |
| A stage's scope, decisions, review and pull requests | its GitHub issue (labels `dd`, `wave-<n>`); how to run a stage through one: the [`stage-issue`](.claude/skills/stage-issue/SKILL.md) skill |
| What this repository is, the gate, the structure | [`README.md`](README.md) |
| **How to write a domain and a contract**: what will not compile, every refusal with its code | [`packages/eh_os_contract/docs/contract.md`](packages/eh_os_contract/docs/contract.md) |
| Every key of both DSLs: type, required or optional, default (generated) | [`packages/eh_os_contract/docs/dsl/`](packages/eh_os_contract/docs/dsl) |
| Every rule of `mix eh_os_contract.check` (generated) | [`packages/eh_os_contract/docs/rules.md`](packages/eh_os_contract/docs/rules.md) |
| What to write and run when you add something, so the docs stay true | [`packages/eh_os_contract/MAINTAINING-DOCS.md`](packages/eh_os_contract/MAINTAINING-DOCS.md) |
| The initial assumptions and decisions, the `§N` code comments cite | [`docs/adr/architecture.md`](docs/adr/architecture.md) |
| The contract language v2, its rules and shapes | [`docs/adr/contract-v2.md`](docs/adr/contract-v2.md) |
| Code shapes, schemas, pitfalls, libraries: the `notes §N` comments cite | [`docs/adr/technology-notes.md`](docs/adr/technology-notes.md) |
| What each decision beat, rejected alternatives | [`docs/adr/design-rationale.md`](docs/adr/design-rationale.md) |

`PLAN.md` is long and written for an assistant that needs the whole context in one file; its entries before
6 October 2026 are in Polish and are not translated. Read the handoff at its top, then the programme you work on.

**`docs/adr/` holds assumptions, and is deliberately behind the code.** When `docs/adr/` and `PLAN.md` differ,
`PLAN.md` is newer. Where a correction goes:

- **An implementation detail**: `docs/adr/technology-notes.md`, in place, in one commit.
- **What writing the code taught about a stage**: its issue. `PLAN.md` changes only its status.
- **An assumption that turned out wrong, or a rule of the contract a stage changes**: a **dated amendment** in
  `docs/adr/`, never a silent rewrite, ending with the link to the stage's issue. These files are worth keeping
  only because they can be compared with what actually happened; rewritten to match today's code, they measure
  nothing. Twice an assumption proved wrong while writing the code, and both times the fix belonged in
  `docs/adr/`, not in a comment working around it.

## What the library is, and is not

An application describes its business as two kinds of Elixir module, in the manner of ESDM: a **domain** — its
words and their definitions, contexts and how they relate, actors, values, the external systems it depends
on — and **contracts**, each in one context and, until the DD programme's wave 2 changes it, describing one
process: the units that decide (aggregates, boundaries), their
commands, events, invariants and lifecycles, what reacts to the events, what is read, the process they belong
to, its promises, and scenarios. Both are Spark DSLs; what is wrong with them fails the compile, with a code
and a message (`docs/contract.md`). Everything the library does reads those modules.

**`packages/eh_os_contract`, the engine:**

- **Dispatch and the log.** `EhOsContract.dispatch/3` asks whether the actor may issue the command (an
  `EhOsContract.Authorizer`), checks its fields, reads the unit's history from the engine's own event log
  (Postgres), lets the implementation decide, and appends only what the contract declares. A unit's state is
  its events, folded. Personal fields are encrypted per subject, and erasing a subject destroys its key
  (crypto-shredding, `EhOsContract.Vault`). A field the host must supply rather than the caller comes from an
  `EhOsContract.Supplier`.
- **Reactions.** Read models, policies, process managers with timers, and effects run inside the dispatch's
  transaction (`:in_transaction`) or after it (`:at_least_once`: an ordered subscription to the log, or an Oban
  job inserted in the same transaction). A reaction to another context's event has to say which.
- **Between applications.** An event leaves only through `publish`: a relay reads the log and hands it to an
  `EhOsContract.Bus`. One arrives in an inbox that only a policy takes, never in the receiver's log. The library
  ships `Bus.Local`, for tests and a single node; transport adapters (JetStream, EHOS's relay) are EHOS's, and
  the library depends on no broker.
- **The door from outside.** Raw data with a credential enters through `EhOsContract.call/3`, and over HTTP
  through `EhOsContract.Plug` on top of it. The contract also generates OpenAPI and AsyncAPI documents and an
  exported model.
- **Tests from the contract.** Scenarios run as tests (`EhOsContract.ScenarioCase`) against the same rules
  dispatch applies.
- **Conformance.** It answers one question:

  > Does the deployed code do what the defined process says?

  The report and the dashboard ask **four questions and no more**: which declared paths were never taken,
  which transitions were not declared, which promises are broken, and which version of the contract is
  deployed and since when.
- **Tasks:** `check` (the rules a compiler cannot hold: errors, warnings and notices), `report`, `graph`, `pages`, `glossary`,
  `view`, `subscriptions`, `rewrap`.

**`packages/eh_os_contract_web`** is a dashboard a host mounts: each contract's conformance and its graph, and a
JSON API with the model, the conformance and the OpenAPI and AsyncAPI documents. The host decides who may see it
(`EhOsContract.Web.Resolver`).

**`packages/eh_os_contract_auth`** connects an application to EHOS, the platform that hosts it: it verifies the
credentials EHOS issues against keys kept in the application's database (and is the `Authorizer` for them),
signs a person in to the application's pages through EHOS's own sign-in, and writes the application manifest
EHOS deploys from (`mix eh_os_contract.manifest`). The engine does not depend on it.

Everything else has an owner: performance is GCP's, errors are Datadog's, **the state of the business is the
client application's**. The library keeps the client's read models and queries — their state, declared in the
contract — but the dashboard does not show them; it shows conformance. Once it answers "which company has no
open July", it becomes a second, worse screen of the client's application.

## The gate

```bash
docker compose up -d && cd sandbox && mix ecto.setup && mix check
```

`mix check` in `sandbox/` runs `format --check-formatted`, `compile --force --warnings-as-errors`,
`eh_os_contract.check` and the sandbox's tests, then `mix check` of each package in its own invocation:
`packages/eh_os_contract` (with `eh_os_contract.docs --check` and `eh_os_contract.rules --check`, which hold the
generated pages — the DSL reference in `docs/dsl/`, the configuration, the rule catalogue in `docs/rules.md`, and the
generated regions of the prose pages — to the code; `test/docs_test.exs`, which holds the examples and the refusal
table of `docs/contract.md` to it, and what a prose page says it covers (`<!-- covers: … -->`,
`EhOsContract.Docs.Prose`) to the entities, keys and rules that exist; `docs
--warnings-as-errors`, which fails on a reference in a doc to a missing or hidden function of an existing module, a
hidden module, a module outside `lib/`, or a missing page (not to a module that does not exist at all); and
`test/doc_coverage_test.exs`, which fails on a public function of `lib/` with no `@doc` or `@spec`),
`packages/eh_os_contract_web` and
`packages/eh_os_contract_auth` (each with its own `docs --warnings-as-errors` and `test/doc_coverage_test.exs`),
and `packages/eh_os_contract_graph`. **It has to pass.** Separate invocations, not an umbrella, so that each package
stands alone; the gate lives in `sandbox/` because only it sees every project. `--warnings-as-errors` is
required: `boundary` reports violations as warnings, so without it the boundaries are documentation. Postgres
listens on **5433**.

**Do not pipe the gate into `tail` before a commit.** `mix check | tail -4 && git commit` checks the exit code
of `tail`, which is always zero, so the commit goes in on red while you see four lines and not the failure
count. It happened on 6 August: 24 failures committed. To shorten the output:

```bash
out=$(mix check 2>&1); rc=$?; echo "$out" | tail -4; echo "EXIT=$rc"
```

**`mix run` with `MIX_ENV=test` writes outside the Ecto sandbox** (the test transaction, not the `sandbox/`
directory). The Ecto sandbox covers tests, not Mix tasks, so one `MIX_ENV=test mix run -e '...'` leaves rows in
the test database **for good** and breaks everything that counts records afterwards — the same trap
`EhOsContract.Deployment.record!` sets at boot. Look at anything with `MIX_ENV=dev`; if you fall in,
`MIX_ENV=test mix ecto.drop && MIX_ENV=test mix ecto.create && MIX_ENV=test mix ecto.migrate` recovers — the
environment on each command, since an assignment in front of one applies to that one only.

**The Postgres databases are shared by every worktree**: their names are fixed (`eh_os_contract_host_test`,
`…_dev`, `eh_os_contract_test`, …). Two traps follow, both from 4 October:

- **`too_many_connections`.** The gate next to someone else's `phx.server` or tests fails on connections, not on
  code (`AppendLockTest`, `SchemaTest`). Do not retry in a loop: stop your own dev server, wait until
  `lsof -nP -iTCP:5433 | awk 'NR>1 && $1 ~ /beam/' | wc -l` is below about 10, and run the gate once.
- **A migration on an unmerged branch changes the test database for everyone.** After the gate on a branch with
  a migration `main` does not have, restore the schema (`psql` in the container: undo the change and delete its
  row from `schema_migrations`), or tell the user.

## Language

**Everything in this repository and on GitHub is in English**: code, comments, docs, `PLAN.md`'s new entries,
commit messages, issues, pull requests. We may talk in Polish; what we leave behind is English, because the
project will be international.

The one exception is **text the client reads in sentences, inside strings**: the `label` and `source` of
declarations in a domain and a contract, a term, its `definition`, `avoid` and `translation`, the `where` prose
of `consults`, scenario descriptions, task names, a notification's subject. The test material's clients are
Polish, so those strings are Polish there; nowhere else is a Polish string correct, and never in a comment, a
doc or a name. The engine writes its own sentences in English; a client's labels appear in its output as the
client wrote them.

History is not rewritten: `PLAN.md` before 6 October 2026, the first twelve commit messages and the workshop
material in `docs/warsztat-*.md` stay in Polish.

Polish text in strings has its own pitfalls, each of which has already cost a broken build or a false "done":

- **The Polish closing quote is `”` (U+201D), not `"`.** An ASCII `"` inside a string ends it, and the compiler
  reports an unexpected token at the **opening** `„`, a few characters before the real cause.
- **A regex over client text always takes the `u` flag.** Without it `\R`, `\s` and `\w` read bytes, and Polish
  has meaningful bytes in UTF-8: `~r/\R/` matches `0x85`, the second byte of "ą". Test client text with a Polish
  label that has an "ą".
- **With the `u` flag, `\d` is any Unicode digit.** Write an ASCII format — a KSeF number, a NIP, a date — as
  `[0-9]`.
- **Write files with `encoding: :unicode`.** Erlang keeps stdout in latin1 when it is not a terminal and mangles
  every Polish character.
- **Grepping for `[ąćęłńóśźż]` does not find all Polish.** Much of it has no diacritics; check the words too.

## Conventions that are easy to break

- **`boundary`: process modules are siblings, not a hierarchy.** Reaching another's tables needs an explicit
  `deps`.
- **Implementations point at the contract, never the other way** (`use Contract, aggregate: :x`). A contract
  naming its code would depend on it at compile time while the code depends on the contract, so every change to
  the code would recompile the contract and everything after it. For the same reason a contract names its domain
  through `domain:` without a compile dependency, and a Mix compiler checks the links between them.
- **Checks in the macro body, not in `quote`.** That creates the compile dependency and makes an error point at
  the implementation, not at the library.
- **Events and commands are literals.** `emit/1` and `issue/1` take struct literals, because that decides
  whether the static graph is a fact or a guess.
- **Public functions in `packages/*/lib/` have `@doc` and `@spec`**, and a doc is written for a host reading it
  on hexdocs, not for the team: its meaning, an example, what it refuses, and no stage or `§` codes. Without
  them the package has no documentation and `dialyzer` nothing to check. How: the
  [`write-docs`](.claude/skills/write-docs/SKILL.md) skill. Each package's gate holds the mechanics
  (`test/doc_coverage_test.exs`, `docs --warnings-as-errors`).
- **A code never stands alone in prose.** In `PLAN.md`, `docs/adr/`, a pull request or a commit, the meaning
  comes first and the code in parentheses: "a reaction to another context's event that leaves delivery out
  (X10)". An issue's "In short" section carries no codes at all; its technical detail follows the same rule
  as the rest. Compiler messages and tests keep their codes; the message says the
  meaning beside it.
- **A pull request says what it belongs to**: `Closes #N`, `Part of #N` or `No issue: <why>` (the template;
  `.github/workflows/pr-links-issue.yml` checks it). A stage's commits end with `Part of #N`, its branch is
  `dd/<issue>-<words>`, and a code comment citing a stage cites its issue: `plan DD, ID1 (#165)`
  (`CONTRIBUTING.md`).
- **Do not rely on word splitting in shell scripts.** The shell is zsh, which does **not** split unquoted
  expansions: `for x in $LIST` runs once with the whole list as one argument. Once that handed `git cherry-pick`
  seven SHAs as one argument, and the `git commit --amend` after it rewrote the wrong commit. Loop over SHAs
  explicitly or through arrays.
- **TaxVision's event names come from the workshop**, not from imagination: the event storming in
  `workshop_output/02-event-storming.md` of the
  [`appunite/taxvision-process-native`](https://github.com/appunite/taxvision-process-native) repository (private;
  ask the user for access). Rehmed's and AppUnite's sources are the distillations in `docs/`.

## A person is the gate, so readability is a requirement

Code goes in as a pull request and a person verifies it. Two things follow when generating it:

1. **A reviewer's attention goes where the variance is**: to the functions that decide. The skeleton,
   migrations and boundaries are deterministic and are reviewed once per pattern, not once per occurrence.
2. **A small diff.** A pull request that cannot be read with attention is not reviewed, only approved. That is a
   functional limit, not a matter of style.

## What we do not build

- **A project generator** (`mix eh_os_contract.new`): not before something has been copied by a second client.
- **Real integrations in the test material**: a behaviour and a fake. A real registry or mail server is a
  client's domain cost and teaches the library nothing.
- **Identity**: accounts, roles, sign-in and sign-out screens, an identity provider. EHOS owns them. The engine
  knows an actor only as an opaque subject with the capabilities its verified credential grants; roles are the
  contract's actors. `eh_os_contract_auth` verifies EHOS's credentials and hands a person to EHOS to sign in; it
  shows no sign-in screen of its own.
- **A message broker or its adapters**: EHOS's. The library defines `EhOsContract.Bus` and ships only the local
  one.
- **An API layer of its own** (REST or GraphQL) beyond the generated documents and the `call/3` door.
- **Alerts, operational views, metrics.**
- **Anything that answers a question about one particular company or customer.**
