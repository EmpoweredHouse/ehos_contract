# Contributing

How work is planned, recorded and reviewed in this repository, for a person joining it. An assistant working
here follows the same scheme; `CLAUDE.md` and the skills in `.claude/skills/` give it the details.

## Where things live

Each place answers one question. Copying an answer into a second place makes two versions, and one of them goes
stale, so each place links to the next instead.

| Place | The question it answers | When it changes |
| --- | --- | --- |
| `PLAN.md` | Where are we, and what comes next? The programmes, their waves, each stage's status, a short paragraph per stage, the link to its issue | When a stage starts or ends |
| A GitHub issue | Why and how was this stage done? In short for anyone, then the technical detail, scope, expected result, decisions with the options they beat, the review | While the stage is worked on; closed by the pull request that says `Closes #N`, or by hand after its closing comment |
| `docs/adr/` | What is the library meant to be? Its assumptions, the contract's rules and shapes, alternatives rejected for the design | When a stage changes an assumption or a rule later stages and applications rely on; always as a dated amendment that links the issue, never a silent rewrite |
| A pull request | What changed in the code, how it was tested, what the review found | Once, when it is opened and as review comments are settled |
| A package's `CHANGELOG.md` | What changed for a host, version by version | In the pull request that changes what a host sees ("Changelogs and releases", below) |
| The code and its tests | What the library does | — |
| `packages/eh_os_contract/docs/`, the READMEs, the `@doc`s | How does a host use the library? | With the change that alters what they describe; what is generated, what is written and what to run is in [`MAINTAINING-DOCS.md`](packages/eh_os_contract/MAINTAINING-DOCS.md) |

`PLAN.md` is written for an assistant that needs the whole context in one file; it is long, and its history
before 6 October 2026 is in Polish. A person starts from the issues: the labels `dd` and `wave-<n>` list the
current programme's stages.

A decision belongs in `docs/adr/` when someone reading the library in six months would misunderstand it
without it — a rule of the contract, the shape of an identifier other stages build on. A decision about how a
stage was carried out stays in its issue.

## From an idea to `main`

1. **The stage's paragraph in `PLAN.md`** says, in a few lines, what it changes and what it depends on. A stage
   not yet started may be rewritten; one already done is not.
2. **An issue** from the "Programme stage" template, with the programme's label and, where there are waves,
   the wave's. Its first section, "In short", is for a reader outside the team who may not be technical: no
   module names, codes or file paths. The technical detail that follows has no such limit, except that a rule
   or refusal code stands in parentheses after its meaning, and it names files without line numbers.
3. **A branch** named after the issue: `dd/165-contract-id`.
4. **Commits** end with `Part of #N`, so `git blame` on any line leads to the issue. Commit messages are in
   English.
5. **Decisions go on the issue as comments when they are made**, with the options that lost and why.
6. **A pull request** from the template. Its first line is `Closes #N` on the pull request that finishes the
   issue, `Part of #N` on earlier ones, or `No issue: <why>` for a change that needs none — a typo, a
   dependency bump. A check (`.github/workflows/pr-links-issue.yml`) fails a pull request that says none of
   them; it does not decide which one is right. A change a host can see has its line in the package's
   `CHANGELOG.md`, or the description says why not on a line `No changelog: <why>` (below).
7. **Before it is opened**, the author reviews it (`.claude/skills/pre-pr-review/SKILL.md`), and `mix check` in
   `sandbox/` passes (`README.md`, "Working on it").
8. **When it is merged**, `PLAN.md` gets ☑ and the pull request's number, and the issue gets a closing comment:
   what changed for a user of the library, what was left for later and where, and what an application has to do
   when it upgrades.

## Changelogs and releases

Each package keeps a `CHANGELOG.md`, written by hand for whoever uses the package — a host application's
developer — in [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), as EHOS's other repositories do
(eh-os D-91).

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

How a release is made is written once, for the three repositories, in eh-os's
[`docs/releases.md`](https://github.com/EmpoweredHouse/eh-os/blob/main/docs/releases.md); the `ehos-dev:release`
skill makes one (the `ehos-dev` plugin from ehos-tools, once enabled here). In this repository:

- **One tag, `vX.Y.Z`, follows the engine's version; each package keeps its own.** An application requires
  `eh_os_contract_auth` `~> 0.1.0-dev` while the engine is at 0.3.0, and one shared number would break it.
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
  nothing a host sees, so its description says so on a line `No changelog: <why>`.

## Following a line back to its reason

- From the code: `git blame` → the commit → `Part of #N` → the issue, with its decisions and pull requests.
- From a code comment: a comment that cites a stage cites its issue too, `plan DD, ID1 (#165)`.
- From `PLAN.md`: the "Issue" column of the progress table → the issue → its pull requests → the code.

## Writing

- Code, commit messages, pull requests, issues, `README.md` and `docs/` are in English. The only Polish is
  text the client reads in sentences, inside strings: labels, glossary terms, scenario descriptions
  (`CLAUDE.md` lists them).
- Codes are for the compiler and the tests. In prose a code never stands alone: the meaning first, the code in
  parentheses — "a reaction to another context's event that leaves delivery out (X10)".
- Plain writing: the problem before the solution, a concrete example over an adjective, active voice, no
  filler.
