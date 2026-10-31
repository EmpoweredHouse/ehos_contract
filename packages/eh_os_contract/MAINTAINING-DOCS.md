# Maintaining the documentation

How the engine's documentation stays true as the library grows: what is generated from the code, what is
written by hand, and what to do when you add something. It is for whoever changes the library, a person or an
assistant; a host reads the pages themselves, on hexdocs or in `docs/`. This file is not published.

Most of it you do not have to remember. `mix check` (in `sandbox/`, or in this package) fails when the
documentation and the code disagree, and the failure says what to run or write. The table below is what each
failure asks of you.

## Two kinds of page

**Generated** pages are written by a task from the code, and edited only through the code. `--check` fails
when one differs from what the task would write now:

| Page | Written by | From |
| --- | --- | --- |
| `docs/dsl/` (one page per top-level entity, an index per DSL) | `mix eh_os_contract.docs` | the DSL extensions' `describe:` and `doc:` |
| `docs/configuration.md` | `mix eh_os_contract.docs` | the schema in `EhOsContract.Config` |
| `docs/cli.md` | `mix eh_os_contract.docs` | each task's `@moduledoc` and `@shortdoc` |
| `docs/behaviours.md` | `mix eh_os_contract.docs` | each behaviour's `@callback`s and their `@doc` |
| `docs/rules.md` | `mix eh_os_contract.rules` | `EhOsContract.Check.Catalog` |
| `docs/img/<id>.svg` | `mix ehos_diagrams.gen` | the hand-laid source `docs/diagrams/<id>.svg`, and the words of `docs/glossary.md` |

**Prose** pages are written by hand: `README.md`, `docs/introduction.md`, `docs/getting-started.md`,
`docs/contract.md`, `docs/concepts/*.md`, `docs/authorization.md` and `docs/glossary.md`. The list is
`EhOsContract.Docs.prose/0` (in `dev/`). Each of them:

- has at least one example that defines a module, and every `elixir` block that defines one compiles, with the
  modules the page defines before it, and passes the rules between modules (`test/docs_test.exs`);
- says, on the line above each `elixir` block that defines no module (a snippet), where the snippet belongs, and
  the same test compiles the page with it in place:
  - `<!-- in: Lending.Contracts.Loans -->` puts it in the body of that module of the page;
    `<!-- in: Lending.Contracts.Loans, command :open_loan -->` in the body of the one declaration of that module
    with that kind and name. The snippet takes the place of the body's declarations of the same kind and name as
    one of its own (for a function, all its clauses), where the first of them was; if it replaces none, it goes
    at the end of the body. Module attributes of the body, such as `@impl`, stay where they are. So a snippet that needs more of the model than it shows fails, as it would for a
    reader who pastes it.
  - `<!-- and in: … -->` puts a snippet in place together with the one before it, for a change that needs both:
    an `upcast` step and the function of the implementation it names, a supplied field and the scenario that
    then gives it.
  - `<!-- not compiled: <why> -->` is for code no page can define: the host's configuration, its `mix.exs`, a
    call in its code, or a declaration of a model the page does not show. Such a snippet still parses. Prefer
    `in:`: a declaration marked `not compiled` can drift.
  - In every snippet, each module, function, macro and type of the library that it names in full
    (`EhOsContract.…`) exists, with the arity of the call. A name through an `alias` is not checked.
  - Inline code is not compiled. A declaration that a reader is to copy goes in a block.
- says what it explains in a `<!-- covers: entities …; keys …; rules … -->` comment, and every name there has to
  exist (`EhOsContract.Docs.Prose`);
- links each refusal code it names, `` [`D4`](refusals.md#refusals-d) ``, to its family's table in
  `docs/refusals.md`, with or without backticks around the code;
- may hold a generated region, `<!-- generated: config -->` … `<!-- /generated -->`, which
  `mix eh_os_contract.docs` rewrites and you do not edit.

Every top-level entity of the three DSLs and every rule of the check is covered by some prose page. A new one
that no page names fails the gate.

`docs/refusals.md` is a third kind: written by hand, with no example, and held to the code row by row. Its
tables name exactly the codes `lib/` refuses with, each with the layer that refuses it (`test/docs_test.exs`).

## When you add or change something

Run the tasks in this package with `MIX_ENV=dev`, and commit the pages they rewrite.

| You add or change | Write | Then run | The gate fails if you do not |
| --- | --- | --- | --- |
| A public function, macro or module in `lib/` | `@doc` and `@spec` for a host, or `@doc false` (the `write-docs` skill) | nothing | `test/doc_coverage_test.exs`; `docs --warnings-as-errors` on a reference to something hidden or missing |
| A DSL entity, argument or option | its `describe:` or `doc:` | `mix eh_os_contract.docs` | `docs_test` (an undescribed declaration); `eh_os_contract.docs --check` |
| A new **top-level** DSL entity | as above, and a prose page that explains it: its name in that page's `covers:` | `mix eh_os_contract.docs` | `docs_test`: covered by no prose page |
| A configuration key | its `doc:` in `EhOsContract.Config`'s schema | `mix eh_os_contract.docs` | `eh_os_contract.docs --check` |
| A mix task or a behaviour callback | its `@moduledoc` and `@shortdoc`, or its `@doc` | `mix eh_os_contract.docs` | `eh_os_contract.docs --check` |
| A rule of `mix eh_os_contract.check` | its entry in `EhOsContract.Check.Catalog`, and its name in a prose page's `covers:` | `mix eh_os_contract.rules` | `eh_os_contract.rules --check`; `docs_test`: covered by no prose page |
| A compile refusal code | its row in its family's table in `docs/refusals.md`, with the layer that refuses it, and a test in `test/dsl/` asserting it | nothing | `docs_test`: the table names exactly the codes the library raises, and where, each tested |
| A new family of refusal codes (a new letter) | a table of its own in `docs/refusals.md`, after `<a id="refusals-<letter>"></a>` and a heading, and a line in its list of families | nothing | `docs_test`: a family without its anchor |
| A sentence in a prose page that names a code | the code as a link to its family | nothing | `docs_test`: a bare code, a link to another family, or a link to a code no row has |
| A guide or concept page | see below | `mix eh_os_contract.docs` | `docs_test`, the link and anchor tests |
| A diagram | its source in `docs/diagrams/<id>.svg`, by the `ehos-dev:diagrams` skill, and a link to `img/<id>.svg` from a page | `mix ehos_diagrams.gen` | `ehos_diagrams.gen --check`: an output not current, a label outside the glossary, a diagram over the budget, an output no page links, a Mermaid block |

What the gate cannot see, a reviewer reads for: whether a page still says what the code does after a change in
behaviour, not in shape. A behaviour change is the moment to search the prose pages for what it changes
(`grep -rn` the function or option in `docs/` and `README.md`).

## Adding a page

1. Write it under `docs/`, or `docs/concepts/` for a concept: what it is for, how it behaves at run time, what
   the compiler refuses and what the check reports, with an example that compiles. The existing concept pages
   are the pattern.
2. Name what it covers in its `<!-- covers: … -->` comment.
3. Add it to `EhOsContract.Docs.prose/0` (a concept to `concepts/0`, in the order a reader takes them), and to
   `extras` in `mix.exs`, with its group in `groups_for_extras`. `docs_test` fails if one lists it and the other
   does not.
4. Link it from the pages that lead to it (`README.md`, the introduction, the page before it).
5. Run `mix eh_os_contract.docs`; `--coverage` lists what no page covers yet.

## The other three packages

`eh_os_contract_web`, `eh_os_contract_auth` and `eh_os_contract_graph` have no generated pages and no prose pages beyond their
`README.md`. Their `mix check` builds their docs with `--warnings-as-errors` and runs their own
`test/doc_coverage_test.exs`. They publish only what a host calls or implements; a module the host never names
is `@moduledoc false`, and why it is built the way it is goes in a comment.

## Reading the built documentation

The Markdown pages read as they are in the repository. The HTML, with the API reference and search, is built
by the `docs` workflow (`.github/workflows/docs.yml`) into one archive: the four packages' ExDoc HTML, the
Markdown it is made from, and an `index.html` linking them.

- **By hand**, for any branch, tag or full 40-character commit SHA (a short one is read as a branch): Actions →
  docs → Run workflow, or `gh workflow run docs.yml -f ref=main`. The archive is the run's artifact, kept 30
  days (`gh run download <run id>`). A ref from before the workflow existed (#237) cannot be built: the build
  script is the ref's own.
- **With a release**: publishing one attaches the archive to it, and so does a run by hand on a tag that has
  a release. A draft does not. A release created by a workflow with its `GITHUB_TOKEN` starts no workflow, so
  `release.yml`'s Publish job starts that run by hand.
- **Locally**: `.github/scripts/build-docs.sh <directory> <ref>`, after `mix deps.get` in each package
  (`--only test` for the dashboard). The directory is replaced, so the script refuses one that exists and is
  not an earlier build of its own.

"View source" links to the commit built: `EH_OS_CONTRACT_DOCS_SOURCE_REF`, which the script sets, overrides
each package's `source_ref`, `main` otherwise. Not a version tag: the repository's tag follows the engine's
version, each package keeps its own, and a `-dev` version has no tag.

Nothing is published to a site: a GitHub Pages site of this private repository would be public (#201).
