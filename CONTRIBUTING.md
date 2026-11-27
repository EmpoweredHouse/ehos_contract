# Contributing

How work is planned, recorded and reviewed in this repository, for a person joining it. An assistant working
here follows the same scheme; `CLAUDE.md` and the skills in `.claude/skills/` give it the details, and the
maintainers' own setup is an opt-in step ("Working with Claude Code", below).

## Your first contribution

You do not need the maintainers' tools or their planning process for a fix or a small feature:

1. **Say what you want to change.** For a bug, open an issue from the "Bug" template. For a question
   or an idea, start a [discussion](https://github.com/EmpoweredHouse/ehos_contract/discussions). For a
   larger change, open an issue from the "Feature" template before you write code, so that a maintainer
   can say whether it fits ("What we do not build", in `CLAUDE.md`).
2. **Fork the repository and make a branch.** Any branch name works for a contribution from a fork.
3. **Run the gate** ("Run the gate", below). It needs Elixir, Erlang/OTP and Docker. It has to pass.
4. **Add a changelog line** if a user of a package can see the change ("Changelogs and releases", below).
5. **Open a pull request from the template.** Its first line is `Closes #N` for the issue it fixes, or
   `No issue: <why>`. Fill the sections that apply to your change; a small fix needs a few lines.

A maintainer reviews it. The rest of this page is how the maintainers plan and record their own work:
read it when a pull request of yours needs it.

## What does each directory hold?

| Directory | What it holds |
| --- | --- |
| [`packages/ehos_contract`](packages/ehos_contract) | The engine: the domain and contract languages, dispatch, the log, conformance, and its documentation in `docs/`. |
| [`packages/ehos_contract_web`](packages/ehos_contract_web) | The dashboard that a host mounts. |
| [`packages/ehos_contract_auth`](packages/ehos_contract_auth) | The verifier of EHOS's credentials, the sign-in through EHOS, and the application manifest. |
| [`packages/ehos_contract_graph`](packages/ehos_contract_graph) | The renderer of a `graph.v1` document in a LiveView. It depends on no other package of this repository. |
| [`sandbox`](sandbox) | The development host `:ehos_contract_host`, with three invented case studies as test material. |
| [`docs`](docs) | The design record, `docs/adr/`. |
| [`plugins/ehos-contract`](plugins/ehos-contract), [`.claude-plugin`](.claude-plugin) | The Claude Code plugin that applications use, and the marketplace that publishes it. |

Each package and `sandbox/` is a Mix project of its own. A package builds and tests without
`sandbox/`. `sandbox/` is the first consumer of the packages, not a part of them: it depends on them
by path, and no package depends on it. Inside `sandbox/`,
[`boundary`](https://hex.pm/packages/boundary) keeps the case studies, their parts and the web part of the
host apart.

`CLAUDE.md`, "What we do not build", lists what the repository does not build, and why.

The case studies are `sandbox/lib/lending/`, `sandbox/lib/billing/` and `sandbox/lib/fulfilment/`: a
library that lends copies, a company that bills subscriptions, and a shop that fulfils orders. Each
has a domain, contracts, and implementations that decide and react.

<a id="run-the-gate"></a>

## Run the gate

You need these:

- Elixir 1.18 or later, and Erlang/OTP 27.
- Docker, for PostgreSQL. PostgreSQL listens on port 5433.
- Optional: read access to EmpoweredHouse's private repository `ehos-tools`. The engine, the
  credential verifier and the graph renderer take their diagram generator from there, in `:dev` only. Without access, the gate does not check the
  diagrams, and CI's `diagrams` job checks them, for every pull request.

The gate runs the `mix check` of each package in that package, so each package needs its own
dependencies. From the root of the repository, fetch them as CI does:

```bash
(cd packages/ehos_contract && mix deps.get --only test)
```

```bash
(cd packages/ehos_contract_web && mix deps.get --only test)
```

```bash
(cd packages/ehos_contract_auth && mix deps.get --only test)
```

```bash
(cd packages/ehos_contract_graph && mix deps.get --only test)
```

If you have access to `ehos-tools`, fetch all of the dependencies of the engine, the credential
verifier and the graph renderer instead. Then the gate also checks the diagrams:

```bash
(cd packages/ehos_contract && mix deps.get)
```

```bash
(cd packages/ehos_contract_auth && mix deps.get)
```

```bash
(cd packages/ehos_contract_graph && mix deps.get)
```

Then start PostgreSQL and run the gate:

```bash
docker compose up -d
cd sandbox
mix deps.get
mix ecto.setup
mix check
```

`mix check` in `sandbox/` runs these steps, in order:

1. `format --check-formatted`.
2. `compile --force --warnings-as-errors`. `boundary` reports a crossed boundary as a warning, so
   without this flag the boundaries are not checked.
3. `ehos_contract.check` and `ehos_contract.schema --check`, against `sandbox/ehos_contract.lock`.
4. The tests of the sandbox.
5. `mix check` of each package, each in its own run, so that each package stands alone. Each
   package builds its docs with `--warnings-as-errors` and runs `test/doc_coverage_test.exs`. The
   engine also runs `ehos_contract.docs --check`, `ehos_contract.rules --check` and
   `test/docs_test.exs`. These hold the generated pages and the examples of the prose pages to the
   code.
6. After the engine, `ehos_diagrams.gen --check` in `:dev`, in the engine, the credential verifier
   and the graph renderer, if the diagram generator is fetched there. It holds the diagrams to their sources.
   Without the generator, the gate prints that it did not check the diagrams of that package.

Check the exit code of `mix check` itself. If you pipe the output into `tail`, the exit code is the
exit code of `tail`.

The gate must pass before a pull request is opened. CI runs the same gate on each pull request that
is ready for review. A draft waits until it is marked ready. A pull request that changes only
`README.md`, `CLAUDE.md`, `ROADMAP.md` or `docs/` skips the gate, except for
`docs/adr/contract-v2.md`, whose examples a test compiles.

<a id="run-the-development-host"></a>

## Run the development host and the dashboard

The sandbox host mounts the dashboard of `packages/ehos_contract_web` at `/dashboard`. From the
root of the repository:

```bash
cd sandbox
mix phx.server
```

Then open `http://localhost:4010/dashboard`. If you set `PORT`, the server uses that port instead. The sandbox host lets each person in, read-only, to
the dashboard and to its JSON API. The server listens on each network interface of the machine.
Run it only on a network that you trust. A host decides who can see its dashboard with an
`EhosContract.Web.Resolver`.

An empty log gives empty screens. `mix sandbox.traffic` fills a log with about 6 weeks of runs of
the case studies. The runs include drift:

- broken and suspended promises;
- a deadline that passed;
- stages out of order;
- a transition that the lifecycle does not allow;
- a step that fails.

Each checkout on the machine shares the default development database. Use a database of your own,
because `mix ecto.reset` deletes the database first. Give the two variables on each command, in
`sandbox/`:

```bash
MIX_ENV=dev EHOS_CONTRACT_DEV_DB=ehos_contract_host_dev_traffic mix ecto.reset
```

```bash
MIX_ENV=dev EHOS_CONTRACT_DEV_DB=ehos_contract_host_dev_traffic mix sandbox.traffic
```

```bash
MIX_ENV=dev EHOS_CONTRACT_DEV_DB=ehos_contract_host_dev_traffic mix phx.server
```

The same answers are JSON under the `/api` mount of the host:
[the JSON API of the dashboard](packages/ehos_contract_web/docs/api.md) lists the routes.

## Change the script or the stylesheet of a package

The dashboard, `packages/ehos_contract_web`, and the graph renderer,
`packages/ehos_contract_graph`, each commit their built script and stylesheet under
`priv/static/`. A host and the gate use the committed files, so only the person who changes
`assets/` builds them.

You need read access to the private repository `ehos-tools`. The build runs in `:dev`, and both
packages take `:dev` dependencies from there:

- the dashboard, its design system;
- the graph renderer, its diagram generator and the design system that the generator reads.

Without that access, `mix deps.get` in the package fails.

1. Change the files in `assets/` of the package.
2. Fetch all the dependencies of the package, `:dev` included. Example, for the graph renderer:

   ```bash
   (cd packages/ehos_contract_graph && mix deps.get)
   ```

3. Build the script and the stylesheet in the same package. The build uses esbuild, a downloaded
   binary, and needs no Node. Example, for the graph renderer:

   ```bash
   (cd packages/ehos_contract_graph && mix assets.build)
   ```

   If you changed the graph renderer, also build the dashboard. Its script and stylesheet carry
   those of the graph renderer.

4. Look at the change in a browser, under a Content-Security-Policy of `default-src 'self'`. The
   development host serves the dashboard under this policy. Some defects of the drawing layer
   pass each check that reads the files, and show only on the screen
   ([`docs/adr/graph-renderer.md`](docs/adr/graph-renderer.md)). On the development host, the
   dashboard draws each document of the case studies with the graph renderer.
5. Commit the files in `assets/` and the built files in `priv/static/` together.

The graph renderer carries 2 libraries in its script: dagre and d3-zoom. They are in
`assets/vendor/`. `NOTICE` says what each one is, its licence, and how it was taken.

The dashboard takes its look from the EmpoweredHouse design system, `ehos_design`. That package
is in the private repository `ehos-tools`, and the dashboard pins it in `mix.exs` as a `:dev`
dependency, at one commit. `mix assets.build` imports its tokens,
`priv/css/colors_and_type.css`, into the stylesheet, and copies its fonts beside the stylesheet,
into `priv/static/assets/fonts/`. A host gets nothing from `ehos_design`. To take a new version of
the design system:

1. Move the `ref` of `ehos_design` in `packages/ehos_contract_web/mix.exs` to the commit of the new
   tag.
2. Fetch it and build the assets:

   ```bash
   (cd packages/ehos_contract_web && mix deps.get && mix assets.build)
   ```

3. Commit `mix.exs`, `mix.lock` and `priv/static/assets/`.

Without access to `ehos-tools`, fetch the dependencies of the dashboard with
`mix deps.get --only test`. A plain `mix deps.get` fetches the dependencies of each environment,
`ehos_design` included. The tests read only the committed build.

## Where the work is recorded

Each place answers one question. Copying an answer into a second place makes two versions, and one of them goes
stale, so each place links to the next instead.

| Place | The question it answers | When it changes |
| --- | --- | --- |
| [`ROADMAP.md`](ROADMAP.md) | Where are we, and what comes next? The programmes, each stage's status, a short paragraph per stage being planned, the link to its issue | When a stage starts or ends |
| A GitHub issue | Why and how was this stage done? In short for anyone, then the technical detail, scope, expected result, decisions with the options they beat, the review | While the stage is worked on; closed by the pull request that says `Closes #N`, or by hand after its closing comment |
| `docs/adr/` | What is the library meant to be? Its assumptions, the contract's rules and shapes, alternatives rejected for the design | When a stage changes an assumption or a rule later stages and applications rely on; always as a dated amendment that links the issue, never a silent rewrite |
| A pull request | The problem and its fix in short for anyone, its risks, then what changed in the code, why, how it was tested, what the review found | Once, when it is opened and as review comments are settled |
| A package's `CHANGELOG.md` | What changed for a host, version by version | In the pull request that changes what a host sees ("Changelogs and releases", below) |
| The code and its tests | What the library does | — |
| `packages/ehos_contract/docs/`, the READMEs, the `@doc`s | How does a host use the library? | With the change that alters what they describe; what is generated, what is written and what to run is in [`MAINTAINING-DOCS.md`](packages/ehos_contract/MAINTAINING-DOCS.md) |

`ROADMAP.md` is short on purpose: the reasons are in the issues, whose labels list each programme's stages
(`publication` for the current one, `dd` and `wave-<n>` for the one before it). The working plan the
maintainers kept until 20 October 2026, long and partly in Polish, is archived outside this repository; the
issues carry what it decided.

A decision belongs in `docs/adr/` when someone reading the library in six months would misunderstand it
without it — a rule of the contract, the shape of an identifier other stages build on. A decision about how a
stage was carried out stays in its issue.

## From an idea to `main`

This is how the maintainers carry out a planned stage of the roadmap. A contribution from outside
follows "Your first contribution", above.

1. **The stage's paragraph in `ROADMAP.md`** says, in a few lines, what it changes and what it depends on. A stage
   not yet started may be rewritten; one already done is not.
2. **An issue** from the "Programme stage" template, with the programme's label and, where there are waves,
   the wave's: `publication` for the publication programme, `dd` and `wave-0` … `wave-6` for the DD
   programme ("domain-driven design checked by code") before it.
   The template applies none, so that a stage of another programme, which gets a label of its own and the same
   waves, or none if it has one, does not get `dd` by default. There are no milestones: the labels list a programme's stages. Its first section, "In short", is for a reader outside the team who may not be technical: no
   module names, codes or file paths. The technical detail that follows has no such limit, except that a rule
   or refusal code stands in parentheses after its meaning, and it names files without line numbers.
3. **A branch** named after the programme and the issue: `pb/393-community`, `dd/165-contract-id`.
4. **Commits** end with `Part of #N`, so `git blame` on any line leads to the issue. Commit messages are in
   English. A code comment that cites the stage cites the issue too: `plan DD, ID1 (#165)`.
5. **Decisions go on the issue as comments when they are made**, with the options that lost and why. One that
   changes what the library is meant to be also gets its dated amendment in `docs/adr/`, linking the issue,
   and the issue names it under "Changes to the design record".
6. **A pull request** from the template, whose sections go from the problem in plain words to the review. The
   maintainers' `ehos-dev:pull-request` skill writes its description and opens it, with the rules that
   `.claude/review.md` gives in "The pull request". Its first line is `Closes #N` on the pull request that
   finishes the issue, `Part of #N` on earlier ones, or `No issue: <why>` for a change that needs none — a typo, a
   dependency bump. A check (`.github/workflows/pr-links-issue.yml`) fails a pull request that says none of
   them; it does not decide which one is right. A change a host can see has its line in the package's
   `CHANGELOG.md`, or the description says why not on a line `No changelog: <why>` (below).
7. **Before it is opened**, the author reviews it (what to look at is in `.claude/review.md`, and the
   maintainers run the `ehos-dev:pre-pr-review` skill on it), and `mix check` in `sandbox/` passes
   ("Run the gate", above).
8. **When it is merged**, `ROADMAP.md` gets ☑ and the pull request's number, and the issue gets a closing comment:
   what changed for a user of the library, what was left for later and where, and what an application has to do
   when it upgrades.
9. **When a wave or a programme closes**, nothing more is written: the maintainers decide whether it is
   released ("Changelogs and releases"), and the next stages start from `ROADMAP.md`.

The `ehos-dev:stage-issue` skill is the same procedure for an assistant, with how an issue is written. It comes
from the maintainers' `ehos-dev` plugin ("Working with Claude Code"), which reads this section and the one
before it for what is this repository's.

## Changelogs and releases

Each package keeps a `CHANGELOG.md`, written by hand for whoever uses the package — a host application's
developer — in [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/).

- **Every change a user of a package can see gets a line under `## [Unreleased]` in that package's
  `CHANGELOG.md`, in its own pull request.** What a host sees is the package's public API, its Mix tasks, what it
  writes (the manifest, the pages, the graph documents, its tables), what it verifies and what the dashboard
  reports, and the engine's `docs/`, the DSL reference a host writes contracts by. Its tests, its README,
  `sandbox/` and CI are not.
- **A pull request with no such line says why** on a line of its description: `No changelog: <why>`. The
  Changelog check (`.github/workflows/changelog.yml`) fails a pull request that changes a package's code with
  neither, naming each package; it does not judge the line.
- **A breaking change**, one a host has to act on when it upgrades, starts its line with `**Breaking:**`, under the
  subsection it belongs to. In the engine, a change that can move a verdict starts its line with
  `**Moves a verdict:**` and raises the minor version: the rule at the top of
  [`packages/ehos_contract/CHANGELOG.md`](packages/ehos_contract/CHANGELOG.md).
- **The format is Keep a Changelog as written**: one `## [Unreleased]`, `## [X.Y.Z] - YYYY-MM-DD` for a release
  (a version never published, as the engine's 0.1.0, has no date: `## [X.Y.Z]` and "Never published."),
  only the subsections `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed` and `Security`, prose only between a
  version's heading and its first subsection, and no link references at the end.
- **Between releases a package's version ends in `-dev`**, and a feature's pull request never changes it.
- **A package that depends on another of this repository's names the version it needs** in its `mix.exs`
  (`@ehos_contract_requirement` in the dashboard and the verifier, `@ehos_contract_graph_requirement` in the
  dashboard), and Mix holds the sibling to it even by path. A pull request that makes a package use something
  its sibling has not released yet raises the requirement to the sibling's `-dev` version, `~> 0.9.2-dev` (a
  plain `~> 0.9.2` refuses `0.9.2-dev`), and the release turns it into `~> 0.9.2`. A release that moves a
  sibling to a new minor raises every requirement on it in the same pull request, or nothing resolves:
  `0.10.0` does not satisfy `~> 0.9.1`.
- **A package is built for Hex with `EHOS_CONTRACT_HEX=1` on the command line** of `mix hex.build` or
  `mix hex.publish`, which then see its siblings by version rather than by path; installed from Hex, the
  package finds the same by the `hex_metadata.config` beside its `mix.exs`. Left exported in a shell, the
  variable makes the sandbox and the packages look for the siblings on Hex. CI's `hex-build` job builds and
  reads all four that way.

Releases are made by the maintainers, with the `ehos-dev:release` skill ("Working with Claude Code"), which
follows the same procedure in this repository and EHOS's others. In this repository:

- **One tag, `vX.Y.Z`, follows the engine's version; each package keeps its own.** An application requires
  `ehos_contract_auth` `~> 0.2.0` while the engine is at 0.4.0, and one shared number would break it.
- **At a release, each package with lines under `## [Unreleased]` moves to its next version**, its lines under
  `## [X.Y.Z] - YYYY-MM-DD`, in the release's pull request; a package with none stays at its `-dev` and is not
  released at that tag, though `release.json` names its version.
- **Every release moves the engine**, since the tag is its version. A release of other packages alone moves the
  engine by a patch from its last release, and that version's section says so under `### Changed`: "Released
  with ehos_contract_auth 0.1.1; nothing in the engine changed."
- **The tag runs `.github/workflows/release.yml`.** Its Prepare job, which can only read, checks the tag, writes
  `release.json` (`mix contract.release_file` in `sandbox/`) and takes each released package's section of its
  changelog; its Publish job, in the environment `release`, creates the GitHub release and has the documentation
  attached to it (`docs.yml`). Who may approve a release and which tags may be released are that environment's
  settings.
- **Preview a release before tagging it**: `gh workflow run release.yml -f ref=main` writes into the run's
  summary what a release of that commit would publish (a package at `-dev` shows its `## [Unreleased]`), and
  publishes nothing.
- **The pull request after the tag moves each released package to its next `-dev`.** It changes `mix.exs` and
  nothing a host sees, so its description says so on a line `No changelog: <why>`. While applications follow
  this repository's `main` through git, that is the next patch's `-dev`, not the next minor's: an application
  requires `~> 0.7.0` of the engine and `~> 0.4.0` of the verifier, and `0.8.0-dev` or `0.5.0-dev` on `main`
  would refuse its next `mix deps.update`.
- **The `ehos-contract` Claude Code plugin** is the repository's skills an application uses, in
  `plugins/ehos-contract/skills/` and linked from `.claude/skills/` for work here; `review-pr` and
  `write-docs` stay this repository's alone. The plugin is a directory of its own so that nothing else
  in the repository reaches an application through it: a hook or an MCP server added at the root for
  work here is not the plugin's. `.claude-plugin/marketplace.json` publishes it. The plugin is not a
  package and has no `-dev`: raise its `version` (`plugins/ehos-contract/.claude-plugin/plugin.json`)
  in the pull request that changes one of its skills, then tag that pull request's merge commit
  `ehos-contract-plugin-vX.Y.Z` and push the tag; it publishes no GitHub release. The tag rulesets
  must hold it as they hold `v*`, since applications' settings name it. An application takes a new
  version by moving the `ref` in its `.claude/settings.json`, which `ehos_app`'s installer is to do. A
  skill it carries says, at its top, where its paths are in an application.

## Working with Claude Code

The repository works without any of this: `CLAUDE.md` and the skills in `.claude/skills/` are read by any
Claude Code session opened here, and nothing the repository configures asks for a plugin or blocks a command.

The maintainers add three things on their own machines, in `.claude/settings.local.json`, which git ignores:

- the `ehos-dev` plugin, from EmpoweredHouse's private `ehos-tools` marketplace, which carries the procedures shared
  with EHOS's other repositories, among them `pre-pr-review`, `pull-request`, `stage-issue`, `release`,
  `elixir`, and `voice` and `diagrams` for text a person reads and its diagrams;
- the `diagram-design` plugin, from the same marketplace at one commit, which `diagrams` lays a diagram out with;
- a hook that refuses `gh pr create` while `HEAD` has no review note (`.claude/review.md`).

All three are in `.claude/settings.team.json`. A maintainer with no `.claude/settings.local.json` yet copies it;
one who has one merges its keys in by hand, since Claude Code keeps its "always allow" rules in that file:

```bash
cp -n .claude/settings.team.json .claude/settings.local.json
```

Git does not carry an ignored file into a new worktree, so a worktree needs its own copy.

ehos-tools is private, so the plugin needs a GitHub credential that can read it. On a machine without an SSH key,
set `CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1` and store one with `gh auth setup-git`. A new version of the plugin is
taken by moving the `ref` in that file. A maintainer who copied the file before merges the new `ref` in by hand,
as above. Claude Code applies a `ref` only when it adds the marketplace: a machine that has the marketplace keeps the
tag it added it at, and its sessions keep loading that tag. To move a machine to the new tag:

1. In a directory outside every checkout, run `claude plugin marketplace remove ehos-tools`. In a checkout, this
   command also deletes the marketplace from the checkout's settings.
2. Run `claude plugin marketplace add <repo>#<ref>`, with the `repo` and `ref` that `settings.team.json` gives.
3. In each worktree, run `claude plugin install ehos-dev@ehos-tools --scope local` and
   `claude plugin install diagram-design@ehos-tools --scope local`.
4. Restart Claude Code. `claude plugin list` then shows the new version of `ehos-dev`.

A maintainer who also has `diagram-design` from its own marketplace disables that copy, or a session may use another
version.

## Following a line back to its reason

- From the code: `git blame` → the commit → `Part of #N` → the issue, with its decisions and pull requests.
- From a code comment: a comment that cites a stage cites its issue too, `plan DD, ID1 (#165)`.
- From `ROADMAP.md`: a stage's issue → its pull requests → the code.

## Writing

- Code, commit messages, pull requests, issues, `README.md` and `docs/` are in English, and so are the
  sandbox's case studies. A string in another language is there only where a test of the packages needs a
  second language or non-ASCII text, and only in text a client reads in sentences: labels, glossary terms,
  scenario descriptions (`CLAUDE.md` lists them).
- Codes are for the compiler and the tests. In prose a code never stands alone: the meaning first, the code in
  parentheses — "a reaction to another context's event that leaves delivery out (X10)".
- Plain writing: the problem before the solution, a concrete example over an adjective, active voice, no
  filler.
