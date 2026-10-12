# Reviewing a change to eh-os-contract

This repository's half of the `ehos-dev:pre-pr-review` skill: the skill holds the procedure and
reads this file first. This is the author's half of a review; the reviewer's half is the
`review-pr` skill (`.claude/skills/review-pr/SKILL.md`). Read it before the two reviews start,
because what it tells a reviewer to look at is what your review should have found first.

## Recording the review

A git note on `HEAD`. `git status --porcelain` must print nothing, since uncommitted changes are not
covered by the note. Then
`git notes --ref=review add -m '<what each review found and what happened to each finding>' HEAD`
(`-f` replaces a note already on that commit). Notes stay local: `refs/notes/review` is not pushed.

A Claude Code hook (`.claude/settings.json`) refuses `gh pr create` (and its alias `gh pr new`)
until `HEAD` carries a note in `refs/notes/review`. The note belongs to one commit, so a new commit,
amend or rebase leaves the new `HEAD` without one. The hook is a reminder for this workflow, not
access control. It reads the `HEAD` of the directory the command runs in — the one a leading
`cd <dir> &&` names, else the session's working directory, so a worktree is checked as itself and
not as the main checkout — not the branch the pull request will carry (`--head`). It does not see an
invocation behind `env`, `bash -c` or a shell keyword, it lets everything through on a machine
without `jq`, and it refuses `--help` too (`gh help pr create` works). Keeping to the steps is what
makes the note mean something.

## Documentation alone

Markdown that no part of `mix check` reads: `PLAN.md`, `CLAUDE.md`, the root `README.md`,
`.claude/` except `.claude/settings.json`, whose hook is code, and `docs/` except
`docs/adr/contract-v2.md`. The gate reads more than it seems to:

- `packages/eh_os_contract/test/docs_test.exs` compiles the examples of the package's `README.md`,
  `packages/eh_os_contract/docs/contract.md` and `packages/eh_os_contract/docs/authorization.md`,
  holds the refusal table of the first to the code, and checks the links of every ExDoc extra, the
  package's `CHANGELOG.md` included;
- `packages/eh_os_contract/test/dsl/contract_examples_test.exs` compiles the examples of
  `docs/adr/contract-v2.md`;
- `eh_os_contract.docs --check` and `eh_os_contract.rules --check` compare the generated
  `packages/eh_os_contract/docs/dsl/` and `packages/eh_os_contract/docs/rules.md` with the code.

Check the diff is documentation only with `git diff --stat origin/main..HEAD`.

## Security and performance

Authentication and authorization, injection, secrets, trust in fetched data (TLS, redirects,
sizes), personal data at rest, unbounded work or growth, synchronous writes on hot paths, missing
indexes.

## The checks

`docker compose up -d && cd sandbox && mix ecto.setup`, then `mix check` in `sandbox/`, with its own
exit code. Compare the `eh_os_contract.check` counts with the last ones recorded in `PLAN.md`'s
handoff and explain every new line.

## Verifying for real

A mix task on the dev database (`MIX_ENV=dev`, never `MIX_ENV=test mix run`, see `CLAUDE.md`), the
dashboard through the `eh_os_contract_host` preview (`.claude/launch.json`), a hook through a pipe
test with a synthesised payload. `review-pr` §4 has examples of how this repository writes the
reverse check of a fix down.

## A finding skipped

A GitHub issue, titled by the problem, naming the pull request whose review found it; when that
pull request belongs to a stage of a programme, the issue takes the programme's labels. A note in
the pull request alone is lost once it is merged (decided under
[ehos-tools#98](https://github.com/EmpoweredHouse/ehos-tools/issues/98), 12 October 2026).

## The pull request

From the template. Its first line names the issue (`CONTRIBUTING.md`, "From an idea to `main`").
Its "How it was tested" section says what you ran, with the gate's exit code. A change a host can
see has its line in the package's `CHANGELOG.md`; for one without, the description says why on a
line `No changelog: <why>`. Its "Review" section lists what each review found and what happened to
each finding, or says the change is documentation only.

## Before a fix

A finding whose fix changes a shape a host sees (configuration, a public function, a status, a
reason) goes to the user before it is fixed, as `PLAN.md`'s strategy says of every host-visible
shape.

## What reviews of this repository keep finding

The traps this repository has already paid for are written down once. Check the change against
them, not against memory:

- `CLAUDE.md`, sections "Brama" and "Konwencje, które łatwo złamać": the gate without `tail`,
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
- On a stage branch (`dsl-v2/eN-*`): the rules of every commit and the stage's acceptance
  criteria in `PLAN.md`, "Dopisek 25 września (2) — Etap 6".

Kinds of problems a review here found that neither file names yet:

- A guard over shell commands matches the invocation, not the text: a command that only mentions
  `gh pr create`, in a heredoc or a file it writes, is not that command.
- Trust in something fetched is only as good as the fetch: an HTTP client's defaults (following
  redirects, reading any size, accepting `http`) quietly widen who can answer. Found in stage EA.
- A process that owns an ETS table takes the table with it when it raises: validate in the caller,
  and treat every exception while handling outside input as a failed attempt, not a crash.

A new kind of problem goes on this list; a rule about the code goes in `CLAUDE.md` instead.
