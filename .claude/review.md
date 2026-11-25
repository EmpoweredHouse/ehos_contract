# Reviewing a change to ehos-contract

This repository's half of the `ehos-dev:pre-pr-review` skill: the skill holds the procedure and
reads this file first. This is the author's half of a review; the reviewer's half is the
`review-pr` skill (`.claude/skills/review-pr/SKILL.md`). Read it before the two reviews start,
because what it tells a reviewer to look at is what your review should have found first.

## Recording the review

A git note on `HEAD`. `git status --porcelain` must print nothing, since uncommitted changes are not
covered by the note. Then
`git notes --ref=review add -m '<what each review found and what happened to each finding>' HEAD`
(`-f` replaces a note already on that commit). Notes stay local: `refs/notes/review` is not pushed.

On a maintainer's machine, a Claude Code hook (in `.claude/settings.team.json`, copied into
`.claude/settings.local.json`; `CONTRIBUTING.md`, "Working with Claude Code") refuses `gh pr create`
(and its alias `gh pr new`) until `HEAD` carries a note in `refs/notes/review`. The note belongs to one commit, so a new commit,
amend or rebase leaves the new `HEAD` without one. The hook is a reminder for this workflow, not
access control. It reads the `HEAD` of the directory the command runs in — the one a leading
`cd <dir> &&` names, else the session's working directory, so a worktree is checked as itself and
not as the main checkout — not the branch the pull request will carry (`--head`). It does not see
the command behind `env`, `bash -c` or a shell keyword (`time`), or after a variable set before it
(`GH_REPO=… gh pr create`). It does not see it with a global flag before `pr`
(`gh -R <repo> pr …`), or split by quotes or a backslash at the end of a line. It lets everything
through on a machine without `jq`, and it refuses `--help` too (`gh help pr create` works). Keeping
to the steps is what makes the note mean something.

## Documentation alone

Markdown that no part of `mix check` reads and that sets no rule a review follows: `ROADMAP.md`, the
root `README.md`, and `docs/` except `docs/adr/contract-v2.md`. The gate reads more than it seems
to:

- `packages/ehos_contract/test/docs_test.exs` compiles the examples of the package's `README.md`
  and of each prose page of `packages/ehos_contract/docs/` (`EhosContract.Docs.prose/0`),
  holds the refusal table of `packages/ehos_contract/docs/refusals.md` to the code, and checks the
  links of every ExDoc extra, the package's `CHANGELOG.md` included;
- `mix ehos_diagrams.gen --check` in `packages/ehos_contract`, run in `:dev` by the gate where the
  private ehos-tools is fetched and by CI's `diagrams` job, holds the diagrams in `docs/img/` to
  their sources in `docs/diagrams/`, their labels to the glossary, and the pages to no Mermaid;
- `packages/ehos_contract/test/dsl/contract_examples_test.exs` compiles the examples of
  `docs/adr/contract-v2.md`;
- `ehos_contract.docs --check` and `ehos_contract.rules --check` compare the generated
  `packages/ehos_contract/docs/dsl/` and `packages/ehos_contract/docs/rules.md` with the code.

Everything else is reviewed: anything not Markdown (`.claude/settings.team.json` and its hook,
`.claude/launch.json`, which runs commands), and what sets the rules a review checks against:
`CLAUDE.md`, `CONTRIBUTING.md`, `.claude/skills/` (`review-pr` above all) and this file.

Check the diff is documentation only with `git diff --stat origin/main..HEAD`.

## Security and performance

Authentication and authorization, injection, secrets, trust in fetched data (TLS, redirects,
sizes), personal data at rest, unbounded work or growth, synchronous writes on hot paths, missing
indexes.

## The checks

`docker compose up -d && cd sandbox && mix ecto.setup`, then `mix check` in `sandbox/`, with its own
exit code. Compare the `ehos_contract.check` counts with the sandbox's pinned in
`sandbox/test/e10_outputs_test.exs` and the engine's on `main`, and explain every new line.

## Verifying for real

A mix task on the dev database (`MIX_ENV=dev`, never `MIX_ENV=test mix run`, see `CLAUDE.md`), the
dashboard through the `ehos_contract_host` preview (`.claude/launch.json`), a hook through a pipe
test with a synthesised payload. `review-pr` §2, "Verified in reverse", has the shape in which this
repository writes the reverse check of a fix down.

## A finding skipped

A GitHub issue, titled by the problem, naming the pull request whose review found it; when that
pull request belongs to a stage of a programme, the issue takes the programme's labels. A note in
the pull request alone is lost once it is merged (the maintainers' decision of 12 October 2026, for
EHOS's repositories alike).

## The pull request

The `ehos-dev:pull-request` skill writes the description and opens the pull request. This section
gives the rules that are this repository's own.

`.claude/settings.team.json` pins a tag of `ehos-dev` that has the skill. Claude Code does not
read that file: it reads the maintainer's copy in `.claude/settings.local.json`, one per worktree,
and the user's own settings (`CONTRIBUTING.md`, "Working with Claude Code"). If the session does
not have the skill, tell the user. Name the `ref` that each of these files gives, if it is older
than the tag in `settings.team.json`. The maintainer moves the machine to that tag, as
`CONTRIBUTING.md`, "Working with Claude Code", says. In a run with no user, stop and report it.

The skill says that its review gate refuses `--head`, `--repo`, `GH_REPO` and a commit in the same
command. This repository's hook refuses none of them. It ignores the flags, and it reads `HEAD`
before a commit in the same command runs. Do not use these flags or their short forms (`-H`,
`-R`), and open the pull request in a command of its own.

- **The base** is `main`, and the pull request is not a draft: CI's gate does not run on a draft.
- **The title** is a short sentence that says what changes for a reader, as a commit subject is.
- **The first line** is `Closes #N`, `Part of #N` or `No issue: <why>`, with `owner/repo#N` for
  an issue of another repository. CI's `pr-links-issue` check reads it (`CONTRIBUTING.md`, "From an
  idea to `main`").
- **A changelog line.** A change a host can see has its line under `## [Unreleased]` in the
  package's `CHANGELOG.md`. Otherwise the description has a line `No changelog: <why>`, at the end
  of "What", which CI's `Changelog` check reads (`CONTRIBUTING.md`, "Changelogs and releases").
- **Codes.** Outside "In short", which has none, a refusal or rule code stands in parentheses after
  its meaning: "a reaction to another context's event that leaves delivery out (X10)".
- **How it was tested**, under "Automated", gives the gate, `mix check` in `sandbox/`, with its own
  exit code.
- **No sections of its own** beyond the template's.

This repository has no CI check that reads "Review". Fill it all the same.

## Before a fix

A finding whose fix changes a shape a host sees (configuration, a public function, a status, a
reason) goes to the maintainers before it is fixed, as every host-visible shape does.

## What reviews of this repository keep finding

The traps this repository has already paid for are written down once. Check the change against
them, not against memory:

- A skill under `plugins/ehos-contract/skills/`, also reached through `.claude/skills/`, ships to
  every application that enables the plugin: a change to one raises the version in
  `plugins/ehos-contract/.claude-plugin/plugin.json`, or no application sees it, and names no path
  of this repository that the skill's "In an application" paragraph does not map.
- `CLAUDE.md`, sections "The gate" and "Conventions that are easy to break": the gate without `tail`,
  `MIX_ENV=test mix run`, `boundary` siblings, implementations pointing at the contract and never
  the other way round, checks in the macro body, `emit/1` and `issue/1` taking struct literals,
  English code and where Polish is allowed, the closing `”`, `encoding: :unicode`, zsh not splitting
  words.
- `.claude/skills/review-pr/SKILL.md`: what the gate already guarantees, and where a human
  reviewer's attention goes instead.
- **The changelog** (`CONTRIBUTING.md`, "Changelogs and releases"): each package whose public API,
  Mix tasks, what it writes or verifies, or what the dashboard reports the change touches has a line
  under `## [Unreleased]` in its `CHANGELOG.md`, saying what changed for a host. A change a host has
  to act on when it upgrades starts its line with `**Breaking:**`; an engine change that can move a
  verdict, with `**Moves a verdict:**`. A change with no line says why in the description,
  `No changelog: <why>`; the Changelog check fails the pull request otherwise. The version stays
  `-dev`: only a release changes it (`ehos-dev:release`).
- `.claude/skills/write-docs/SKILL.md`, when the change touches a public module or function: does
  its `@doc` still describe it, and does it read for a host rather than the team.

Kinds of problems a review here found that neither file names yet:

- A guard over shell commands matches the invocation, not the text: a command that only mentions
  `gh pr create`, in a heredoc or a file it writes, is not that command.
- Trust in something fetched is only as good as the fetch: an HTTP client's defaults (following
  redirects, reading any size, accepting `http`) quietly widen who can answer. Found in stage EA.
- A process that owns an ETS table takes the table with it when it raises: validate in the caller,
  and treat every exception while handling outside input as a failed attempt, not a crash.
- A plugin skill that points at an engine page or a code newer than the engine an application pins
  sends that application's agent to nothing: say where an older engine keeps it. Found in #517.
- A page that says what the engine does in absolute words ("refuses nothing", "only reports") is
  read against the code: `mix ehos_contract.check` fails on an error. Found in #517.
- `actions/cache` archives a listed directory whole: a `!` pattern drops only an entry the list
  itself holds, so exclude from a list of children (`deps/*`), never from the directory. Found in #517.
- An installation page is read against what the sandbox host really configures (`sandbox/config/`):
  the Oban queue `:events`, `testing: :manual`, a key per environment. A host that follows the page
  and not the sandbox gets jobs that never run. Found in #517.
- A shell snippet that sets the database by `cd` and `export` before `mix ecto.reset` drops the
  shared database when one line fails or is copied alone: give the variables on each command. Found
  in #517.
- A page's example is read as the code a host copies: an upcast step against the version it reads
  from, and an example copied from another page against that page. A split page needs its own
  compiled example, and the copies drift. Found in #517.
- What the engine narrows for speed is read with its fallback: the exact `evolve/2` catch-all
  narrows what dispatch decodes and what a boundary reads, and a page that gives the rule without
  the cases where it does not apply misleads. Found in #517.
- An operator's command on a page is read against what it does to each kind it takes: `mix
  ehos_contract.subscriptions` boots the whole host, and a `--reset` is not a retry. It replays a
  policy into new commands and effects, republishes a relay's whole log, and drops a process
  manager's reactions and timers since the failure. A page that offers one remedy for every kind
  sends an operator to lose data. Found in #517.
- A number of the conformance report is read with the period it reads: with `--since` and `--until`,
  a promise is judged only on the events inside the period, while the deadline and the order of
  stages read each run whole, and the count of runs takes any run with an event in it. A page that
  gives one rule for all of them misleads. Found in #517.

- A page that says a package guards something is read against the guard's condition: `pin_keys`
  once raised when the line was missing, not when it was in the wrong environment, so "the package
  raises elsewhere" promised a guard that did not exist. Found in #517; the guard came in #591.
- A guard that should hold only in a test is read for where its condition is evaluated: a
  dependency compiles in `:prod` whatever the host's environment, so a compile-time `Mix.env()` in
  a package never sees `:test`. Read it when the guard is asked. Found in #591.
- A gate beside another test run on the shared database fails with `connection not available`,
  not on code: give each run its own `MIX_TEST_PARTITION`. Found in #591.
- A reverse check mutates a file a fix also changed: commit the fix first, mutate, then
  `git restore <file>`. `git checkout -- <file>` after an uncommitted fix removes the fix too.
  Found in #591.
- A page that names an option is read against where the code takes it: `cacertfile:` and `plug:` are
  options of a child (`EhosContract.Auth.SignIn`, `EhosContract.Auth.Workload`), not keys of its
  `config :ehos_contract_auth` block, and each refuses a key it does not take, so a host that
  follows the page does not boot. Found in #517.

- A plug a host mounts with `forward` answers every path under its prefix, and Phoenix matches
  routes in order: mounted before the host's other routes under that prefix, it answers them
  instead. The page that mounts it says where the line goes. Found in #621.
- A test conn from `Plug.Test.init_test_session/2` has its session fetched already, while an
  endpoint's `Plug.Session` fetches it on demand: a branch that reads the session without
  `fetch_session/1` passes the test and fails in the application. Found in #621.

- A file a process keeps while it runs is read with every way the process stops: Ctrl+C and `a`, the
  usual stop of `mix phx.server`, skips `terminate/2`, so the file stays; an operating system process
  id left in it may belong to another program later; and a file made 0600 after its create was
  readable for that moment, so a secret goes into a directory that is 0700 first. Found in #646.

A new kind of problem goes on this list; a rule about the code goes in `CLAUDE.md` instead.
