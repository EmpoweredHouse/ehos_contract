# Contributing

How work is planned, recorded and reviewed in this repository, for a person joining it. An assistant working
here follows the same scheme; `CLAUDE.md` and the skills in `.claude/skills/` give it the details, and the
maintainers' own setup is an opt-in step ("Working with Claude Code", below).

## Where the work is recorded

Each place answers one question. Copying an answer into a second place makes two versions, and one of them goes
stale, so each place links to the next instead.

| Place | The question it answers | When it changes |
| --- | --- | --- |
| [`ROADMAP.md`](ROADMAP.md) | Where are we, and what comes next? The programmes, each stage's status, a short paragraph per stage being planned, the link to its issue | When a stage starts or ends |
| A GitHub issue | Why and how was this stage done? In short for anyone, then the technical detail, scope, expected result, decisions with the options they beat, the review | While the stage is worked on; closed by the pull request that says `Closes #N`, or by hand after its closing comment |
| `docs/adr/` | What is the library meant to be? Its assumptions, the contract's rules and shapes, alternatives rejected for the design | When a stage changes an assumption or a rule later stages and applications rely on; always as a dated amendment that links the issue, never a silent rewrite |
| A pull request | What changed in the code, how it was tested, what the review found | Once, when it is opened and as review comments are settled |
| A package's `CHANGELOG.md` | What changed for a host, version by version | In the pull request that changes what a host sees ("Changelogs and releases", below) |
| The code and its tests | What the library does | — |
| `packages/eh_os_contract/docs/`, the READMEs, the `@doc`s | How does a host use the library? | With the change that alters what they describe; what is generated, what is written and what to run is in [`MAINTAINING-DOCS.md`](packages/eh_os_contract/MAINTAINING-DOCS.md) |

`ROADMAP.md` is short on purpose: the reasons are in the issues, whose labels list each programme's stages
(`publication` for the current one, `dd` and `wave-<n>` for the one before it). The working plan the
maintainers kept until 20 October 2026, long and partly in Polish, is archived outside this repository; the
issues carry what it decided.

A decision belongs in `docs/adr/` when someone reading the library in six months would misunderstand it
without it — a rule of the contract, the shape of an identifier other stages build on. A decision about how a
stage was carried out stays in its issue.

## From an idea to `main`

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
6. **A pull request** from the template. Its first line is `Closes #N` on the pull request that finishes the
   issue, `Part of #N` on earlier ones, or `No issue: <why>` for a change that needs none — a typo, a
   dependency bump. A check (`.github/workflows/pr-links-issue.yml`) fails a pull request that says none of
   them; it does not decide which one is right. A change a host can see has its line in the package's
   `CHANGELOG.md`, or the description says why not on a line `No changelog: <why>` (below).
7. **Before it is opened**, the author reviews it (what to look at is in `.claude/review.md`, and the
   maintainers run the `ehos-dev:pre-pr-review` skill on it), and `mix check` in `sandbox/` passes
   (`README.md`, "Working on it").
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
  [`packages/eh_os_contract/CHANGELOG.md`](packages/eh_os_contract/CHANGELOG.md).
- **The format is Keep a Changelog as written**: one `## [Unreleased]`, `## [X.Y.Z] - YYYY-MM-DD` for a release
  (a version never published, as the engine's 0.1.0, has no date: `## [X.Y.Z]` and "Never published."),
  only the subsections `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed` and `Security`, prose only between a
  version's heading and its first subsection, and no link references at the end.
- **Between releases a package's version ends in `-dev`**, and a feature's pull request never changes it.
- **A package that depends on another of this repository's names the version it needs** in its `mix.exs`
  (`@eh_os_contract_requirement` in the dashboard and the verifier, `@eh_os_contract_graph_requirement` in the
  dashboard), and Mix holds the sibling to it even by path. A pull request that makes a package use something
  its sibling has not released yet raises the requirement to the sibling's `-dev` version, `~> 0.9.2-dev` (a
  plain `~> 0.9.2` refuses `0.9.2-dev`), and the release turns it into `~> 0.9.2`. A release that moves a
  sibling to a new minor raises every requirement on it in the same pull request, or nothing resolves:
  `0.10.0` does not satisfy `~> 0.9.1`.
- **A package is built for Hex with `EH_OS_CONTRACT_HEX=1` on the command line** of `mix hex.build` or
  `mix hex.publish`, which then see its siblings by version rather than by path; installed from Hex, the
  package finds the same by the `hex_metadata.config` beside its `mix.exs`. Left exported in a shell, the
  variable makes the sandbox and the packages look for the siblings on Hex. CI's `hex-build` job builds and
  reads all four that way.

Releases are made by the maintainers, with the `ehos-dev:release` skill ("Working with Claude Code"), which
follows the same procedure in this repository and EHOS's others. In this repository:

- **One tag, `vX.Y.Z`, follows the engine's version; each package keeps its own.** An application requires
  `eh_os_contract_auth` `~> 0.2.0` while the engine is at 0.4.0, and one shared number would break it.
- **At a release, each package with lines under `## [Unreleased]` moves to its next version**, its lines under
  `## [X.Y.Z] - YYYY-MM-DD`, in the release's pull request; a package with none stays at its `-dev` and is not
  released at that tag, though `release.json` names its version.
- **Every release moves the engine**, since the tag is its version. A release of other packages alone moves the
  engine by a patch from its last release, and that version's section says so under `### Changed`: "Released
  with eh_os_contract_auth 0.1.1; nothing in the engine changed."
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
- **The `eh-os-contract` Claude Code plugin** is the repository's skills an application uses, in
  `plugins/eh-os-contract/skills/` and linked from `.claude/skills/` for work here; `review-pr` and
  `write-docs` stay this repository's alone. The plugin is a directory of its own so that nothing else
  in the repository reaches an application through it: a hook or an MCP server added at the root for
  work here is not the plugin's. `.claude-plugin/marketplace.json` publishes it. The plugin is not a
  package and has no `-dev`: raise its `version` (`plugins/eh-os-contract/.claude-plugin/plugin.json`)
  in the pull request that changes one of its skills, then tag that pull request's merge commit
  `eh-os-contract-plugin-vX.Y.Z` and push the tag; it publishes no GitHub release. The tag rulesets
  must hold it as they hold `v*`, since applications' settings name it. An application takes a new
  version by moving the `ref` in its `.claude/settings.json`, which `ehos_app`'s installer is to do. A
  skill it carries says, at its top, where its paths are in an application.

## Working with Claude Code

The repository works without any of this: `CLAUDE.md` and the skills in `.claude/skills/` are read by any
Claude Code session opened here, and nothing the repository configures asks for a plugin or blocks a command.

The maintainers add two things on their own machines, in `.claude/settings.local.json`, which git ignores:

- the `ehos-dev` plugin, from EmpoweredHouse's private `ehos-tools` marketplace, which carries the procedures shared
  with EHOS's other repositories: `pre-pr-review`, `stage-issue` and `release`;
- a hook that refuses `gh pr create` while `HEAD` has no review note (`.claude/review.md`).

Both are in `.claude/settings.team.json`. A maintainer with no `.claude/settings.local.json` yet copies it;
one who has one merges its keys in by hand, since Claude Code keeps its "always allow" rules in that file:

```bash
cp -n .claude/settings.team.json .claude/settings.local.json
```

Git does not carry an ignored file into a new worktree, so a worktree needs its own copy.

ehos-tools is private, so the plugin needs a GitHub credential that can read it. On a machine without an SSH key,
set `CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1` and store one with `gh auth setup-git`. A new version of the plugin is
taken by moving the `ref` in that file, and a session picks it up after `/reload-plugins` or a restart.

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
