---
name: write-docs
description: Before adding or changing a public module, function, macro, behaviour callback, mix task, DSL entity or option, or configuration key under `packages/*/lib/` — write its `@moduledoc`, `@doc`, `@spec`, `describe:` or `doc:` for the person who will read it on hexdocs or in a generated page of `docs/`: what it is in one sentence, when a host reaches for it, an example, what it promises and refuses; decide between `@doc` and `@doc false`; keep the design record's codes in comments, not in the docs; and regenerate the pages built from it. Use for any change a host could see in the published documentation; not for prose pages in `docs/` written by hand, nor for comments explaining a decision to the next maintainer.
---

# Writing the docs a host reads

Checked on 7 October 2026 against the gate of `packages/eh_os_contract` (`mix check`: `eh_os_contract.docs
--check`, `docs --warnings-as-errors`, `test/doc_coverage_test.exs`, `test/docs_test.exs`) and the generated
pages it holds. Not yet run on a change: read what it says against those before trusting it.

## Who reads it, and where

A doc in `lib/` is published twice: on hexdocs, beside the code, and in a page of `docs/` that a generator
writes from it. Whoever reads it is building an application on the library, has not read the stages' issues, and
may never see this repository.

| You write | It appears in | Regenerate with |
| --- | --- | --- |
| a `@moduledoc`, `@doc`, `@typedoc`, `@spec` | the module's page on hexdocs | nothing; `mix docs` builds it |
| a mix task's `@shortdoc` and `@moduledoc` | `docs/cli.md`, `mix help <task>` | `mix eh_os_contract.docs` |
| a behaviour's `@moduledoc`, `@callback`, its `@doc` | `docs/behaviours.md` | `mix eh_os_contract.docs` |
| a DSL entity's `describe:`, an option's `doc:` | `docs/dsl/<dsl>-<entity>.md` | `mix eh_os_contract.docs` |
| a configuration key's `doc:` in `EhOsContract.Config` | `docs/configuration.md` | `mix eh_os_contract.docs` |
| a rule's text in `EhOsContract.Check.Catalog` | `docs/rules.md` | `mix eh_os_contract.rules` |

Run the generator in `packages/eh_os_contract`, with `MIX_ENV=dev`, and commit what it writes beside the
change. `--check` fails the gate until you do.

## A `@moduledoc`

In this order, each part only if it has something to say:

1. **One sentence: what the module is, for a host**, as a paragraph of its own. ExDoc shows the first
   paragraph as the module's summary in its lists and search, so a first paragraph that runs on is
   cut mid-thought. (The DSL index pages do the same to a `describe:`, at its first full stop.) Start
   with the thing, not with "This module": "Where the values of the fields a contract declares
   `supplied_by: :host` come from."
2. **When a host reaches for it**, and what it would use instead. A module no host touches is
   `@moduledoc false` (below).
3. **An example** a host can copy: the `config` line, the `use`, the call. Indented four spaces or
   fenced as `elixir`; `docs_test.exs` compiles the examples of the guides, not of moduledocs, so keep
   them to what you have run.
4. **What it promises and what it refuses**, in sentences a host can test against: "`:ok` means the
   transport holds every message of the batch." A heading per promise when there are several
   (`## What an adapter promises`); the headings sit one level below the module's on its page and on
   `docs/behaviours.md`.
5. **Why it is shaped so**, only where the shape would otherwise look wrong to a host. The history of
   how it came to be belongs in the commit, the issue or `docs/adr/`.

## A `@doc`

- **What it returns and when**, not what the `@spec` already says. "The values of `request.fields`, or
  why the host cannot give them" beats "Returns `{:ok, map}` or `{:error, term}`."
- **Every refusal by its shape**: `{:error, :idempotency_key_invalid}`, an `ArgumentError` naming the
  key. A host matches on these.
- **What it writes and in which transaction**, when it writes: "runs inside the caller's Ecto
  transaction, so an append commits or rolls back with whatever else the caller wrote."
- **What it raises, and that it raises**, when a raise is the answer to the host's defect rather than
  to bad input.

A `@spec` on every documented function: `test/doc_coverage_test.exs` fails without it. Name the
arguments in the spec when the types alone do not say which is which (`after_version ::
non_neg_integer()`), since the reference pages print the spec as written.

## `@doc` or `@doc false`

`@doc false` hides a public function from every published page. It is right when:

- the function is public only because another module of the library calls it (`Config.validate!/1`,
  `Tools.domain!/2`);
- a macro generates it into a host's module (`__eh_os_contract_model__/0`);
- it implements a callback with `@impl`, which Elixir already hides.

It is wrong when a host calls the function, configures it, or meets it in a message or a stacktrace it
must act on: then the host needs the doc. When in doubt, ask whether a sentence of any other public doc
mentions it; if one does, it is public.

A function with `@doc false` keeps a `@spec` when it is written by hand: dialyzer still checks the
calls between the library's modules. The gate does not require it there, because generated functions
cannot carry one.

A module with `@moduledoc false` publishes nothing; a doc elsewhere may not reference it (the docs build
fails on a reference to a hidden module or function).

## The design record's codes stay out of the docs

The stages of a programme (`E7c`, `plan T1`), the sections of `docs/adr/` (`v2 §16`, `notes §2`) and the layer
names (`L3`) mean nothing on hexdocs. `CLAUDE.md` already says a code never stands alone in prose; in a
doc a host reads, it does not stand at all:

- **The reason goes in a comment** (`#`) above the `@doc` or inside the function, where the next
  maintainer reads it, with its code: `# The append lock (v2 §10.2) ...`.
- **The doc says the meaning**: "Appends are serialised: positions become visible in commit order."
- **A refusal code a host sees is fine** in parentheses after its meaning, because the host meets it in
  a compile error or a finding: "an `:at_least_once` reaction without `idempotency` (P3)".

Many moduledocs still carry such codes; when you change one, take its codes out of the part you touch.

## References that resolve

The docs build fails (`--warnings-as-errors`) on a reference that is not there, and the generated
pages need references that work away from the module's own page:

- **Qualify** a function, callback or type of another module: `EhOsContract.Store.read_query/2`,
  `c:EhOsContract.Bus.publish/2`, `t:EhOsContract.Store.entry/0`. A bare `publish/2` resolves only on its
  own module's page; the generator of `docs/behaviours.md` and `docs/cli.md` qualifies bare references
  to the module's own functions, callbacks and types, but not to another's.
- **Never reference what is not published**: a `@doc false` function, a `@moduledoc false` module, a
  module of `test/support/` or `dev/`, or a `dev/` task (`mix eh_os_contract.docs`, `mix
  eh_os_contract.rules`; write them without `mix ` so ExDoc does not try to link them).
- **ExDoc says nothing about a module that does not exist at all**: a typo in a module's name renders as
  plain code. Check a new module reference by following it on the built page (`MIX_ENV=dev mix docs`,
  then `doc/`).
- **A link to a file** is relative to the page and must exist inside the package; anything outside it
  (another package, `docs/adr/`) is an absolute GitHub URL, since hexdocs has only the package.

## Language

English, always. A client's strings (a `label`, a `definition`) appear in the generated DSL pages only
as examples taken from the material, and only where `CLAUDE.md` allows Polish.

## Before the commit

1. `MIX_ENV=dev mix eh_os_contract.docs` (and `eh_os_contract.rules` if a rule's text changed) in
   `packages/eh_os_contract`, and commit the pages it rewrote.
2. Read the generated page of what you changed, not only the source: a doc that reads well beside the
   code can read badly alone.
3. The gate: `docs --warnings-as-errors` and `test/doc_coverage_test.exs` run inside each package's
   `mix check`, the engine's, `eh_os_contract_web`'s, `eh_os_contract_auth`'s and `eh_os_contract_graph`'s
   alike. The other three publish only what a host calls or implements; a module the host never names (a LiveView, a plug its
   router mounts) is `@moduledoc false`, its text kept as a comment.

## Not this skill

- Prose pages written by hand in `docs/` (`contract.md`, `authorization.md`, the concept pages): they have
  their own tests (`docs_test.exs`) and are guides, not reference. How to add one, and what each kind of change
  asks of the docs: `packages/eh_os_contract/MAINTAINING-DOCS.md`.
- Comments for the next maintainer: `CLAUDE.md`, "A code never stands alone in prose", and the issue
  convention (`plan DD, ID1 (#165)`).
