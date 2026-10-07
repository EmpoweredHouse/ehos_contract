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

**Prose** pages are written by hand: `README.md`, `docs/introduction.md`, `docs/getting-started.md`,
`docs/contract.md`, `docs/concepts/*.md` and `docs/authorization.md`. The list is
`EhOsContract.Docs.prose/0` (in `dev/`). Each of them:

- has at least one example that defines a module, and every example compiles, with the modules the page defines
  before it, and passes the rules between modules (`test/docs_test.exs`);
- says what it explains in a `<!-- covers: entities …; keys …; rules … -->` comment, and every name there has to
  exist (`EhOsContract.Docs.Prose`);
- links each refusal code it names, `` [`D4`](contract.md#refusals-d) ``, to its family's table in
  `docs/contract.md`;
- may hold a generated region, `<!-- generated: config -->` … `<!-- /generated -->`, which
  `mix eh_os_contract.docs` rewrites and you do not edit.

Every top-level entity of the three DSLs and every rule of the check is covered by some prose page. A new one
that no page names fails the gate.

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
| A compile refusal code | its row in its family's table in `docs/contract.md`, and a test in `test/dsl/` asserting it | nothing | `docs_test`: the table names exactly the codes the library raises, each tested |
| A new family of refusal codes (a new letter) | a table of its own in `docs/contract.md`, after `<a id="refusals-<letter>"></a>` and a heading | nothing | `docs_test`: a link to an anchor that is not there |
| A sentence in a prose page that names a code | the code as a link to its family | nothing | `docs_test`: a bare code, or one linked to another family |
| A guide or concept page | see below | `mix eh_os_contract.docs` | `docs_test`, the link and anchor tests |

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

## The other two packages

`eh_os_contract_web` and `eh_os_contract_auth` have no generated pages and no prose pages beyond their
`README.md`. Their `mix check` builds their docs with `--warnings-as-errors` and runs their own
`test/doc_coverage_test.exs`. They publish only what a host calls or implements; a module the host never names
is `@moduledoc false`, and why it is built the way it is goes in a comment.
