---
name: pre-pr-review
description: Review your own change to this repository with two reviews run in parallel — /code-review for correctness and a security-and-performance pass — settle what they find, pass the gate and record the review as a git note, before opening a pull request or pushing new commits to one. Use whenever you are about to run `gh pr create`, when the hook in `.claude/settings.json` refuses `gh pr create` because HEAD has no review note, and when the user asks to review a change before it is sent. Not for reviewing someone else's pull request — that is `review-pr`.
---

# Reviewing a change before its pull request

Every pull request to this repository is reviewed by its author before it is opened: run two
reviews in parallel, settle what they find, pass the gate, record it. A Claude Code hook
(`.claude/settings.json`) enforces the last step: `gh pr create` (and its alias `gh pr new`) is
refused until `HEAD` carries a note in `refs/notes/review`. The note belongs to one commit, so a
new commit, amend or rebase leaves the new `HEAD` without one.

The hook is a reminder for this workflow, not access control. It reads the `HEAD` of the directory
the command runs in — the one a leading `cd <dir> &&` names, else the session's working directory, so a
worktree is checked as itself and not as the main checkout — not the branch the pull request will carry
(`--head`), it does not see an invocation behind `env`,
`bash -c` or a shell keyword, it lets everything through on a machine without `jq`, and it
refuses `--help` too (`gh help pr create` works). Keeping to the steps is what makes the note
mean something.

This is the author's half. The reviewer's half is `.claude/skills/review-pr/SKILL.md`; read it
before step 3, because what it tells the reviewer to look at is what your review should have
found first.

Skip the two reviews of step 3 only for a change to documentation alone, and say so in the pull
request.
Documentation alone means Markdown that no part of `mix check` reads: `PLAN.md`, `CLAUDE.md`,
the root `README.md`, `.claude/skills/`, and `docs/` except `docs/adr/contract-v2.md`. The gate
reads more than it seems to:

- `packages/eh_os_contract/test/docs_test.exs` compiles the examples of the package's `README.md`,
  `packages/eh_os_contract/docs/contract.md` and `packages/eh_os_contract/docs/authorization.md`,
  holds the refusal table of the first to the code, and checks the links of every ExDoc extra, the
  package's `CHANGELOG.md` included;
- `packages/eh_os_contract/test/dsl/contract_examples_test.exs` compiles the examples of
  `docs/adr/contract-v2.md`;
- `eh_os_contract.docs --check` and `eh_os_contract.rules --check` compare the generated
  `packages/eh_os_contract/docs/dsl/` and `packages/eh_os_contract/docs/rules.md` with the code.

The hook still asks for the note: record it once you have checked the diff is documentation only
(`git diff --stat origin/main..HEAD`).

## Steps

1. **Commit everything.** The review reads committed history, and the note covers one commit.
2. **Rebase onto the current `origin/main`** (`git fetch origin && git rebase origin/main`), so the
   review covers only this change.
3. **Review the exact range with two reviews, in parallel** — unless the change is documentation
   alone (above). Then neither review has code to read: check the documentation's claims against the
   code instead, and say in the pull request how. Otherwise the two reviews look for different
   things, and neither found what the other did when both were first run on the same change (stage EA, 27
   September 2026: `/code-review` found crashes and dead ends in the key store, the
   security-and-performance pass found that an `http` issuer and a followed redirect let the key
   set be replaced). Start both as subagents in one message (the Agent tool, two calls), each told to
   report findings and change nothing:
   - **correctness** — invoke the `code-review` skill with `high origin/main..HEAD`: bugs,
     removed guards, callers, reuse, simplification, altitude, `CLAUDE.md` conventions;
   - **security and performance** — invoke the `engineering:code-review` skill on the same range,
     naming "security and performance" as the focus: authentication and authorization, injection,
     secrets, trust in fetched data (TLS, redirects, sizes), personal data at rest, unbounded work
     or growth, synchronous writes on hot paths, missing indexes. Without that plugin, the subagent
     reviews against this list itself.

   Pool what both return, drop duplicates, and settle the pool. A finding that changes a shape a
   host sees (configuration, a public function, a status, a reason) goes to the user before it is
   fixed, as `PLAN.md`'s strategy says of every host-visible shape.
4. **Settle every finding** as one of:
   - **fixed**: a real problem. Fix it in its own commit, with a message stating the failure
     scenario, and a test that fails on the old code. Verify it in reverse: revert the fix and
     watch that test, and no other, go red. `review-pr` §4 has examples of how this repository
     writes that down.
   - **no change needed**: the finding is wrong. Write down why in one sentence.
   - **skipped**: real but out of scope. Say so in the pull request, with why.

   Then report the outcomes with ReportFindings (`fixed` / `no_change_needed` / `skipped`).
   A mutation used for the reverse check has to apply in full: a substitution that matches half of
   a change, or a Perl pattern that interpolates `@module_attribute` as an empty array, breaks the
   code rather than undoing the fix, and whatever fails then proves nothing. Check the diff of the
   mutated file, or mutate with a tool that does not interpolate.
5. **Pass the gate**, checking its own exit code, never `tail`'s:
   `docker compose up -d && cd sandbox && mix ecto.setup`, then
   `out=$(mix check 2>&1); rc=$?; echo "$out" | tail -4; echo "EXIT=$rc"` in `sandbox/`. Compare
   the `eh_os_contract.check` counts with the last ones recorded in `PLAN.md`'s handoff and explain
   every new line.
6. **Verify for real** anything the tests cannot see, and note what you ran and what you saw: a
   mix task on the dev database (`MIX_ENV=dev`, never `MIX_ENV=test mix run`, see `CLAUDE.md`),
   the dashboard through the `eh_os_contract_host` preview (`.claude/launch.json`), a hook through
   a pipe test with a synthesised payload.
7. **Record the review.** `git status --porcelain` must print nothing, since uncommitted changes
   are not covered by the note. Then
   `git notes --ref=review add -m '<what each review found and what happened to each finding>' HEAD`
   (`-f` replaces a note already on that commit). Notes stay local: `refs/notes/review` is not
   pushed.
8. **Open the pull request.** Its "How it was tested" section says what you ran, with the gate's
   exit code. A change a host can see has its line in the package's `CHANGELOG.md` (below); for
   one without, the description says why on a line `No changelog: <why>`. A "Review" section
   lists what each review found and what happened to each finding, or says the change is
   documentation only. A stage of a programme links its issue: `Closes #N` on
   the pull request that finishes the stage, `Part of #N` on any before it, and the review goes on that issue as a comment too, in the plain
   form the `ehos-dev:stage-issue` skill describes.

After review comments or a failed CI run, fix, commit, and go through steps 3–7 again for the new
commits before pushing them. For a small fix-up both reviews may run on the new commits alone. Before any push to an existing pull request, check it is still open: a
commit pushed to a merged pull request's branch never reaches `main`. Test the state itself, not
the exit code of the command that prints it, because `gh pr view` exits 0 for a merged pull request
too:

```bash
[ "$(gh pr view <number> --json state --jq .state)" = OPEN ] && git push
```

The hook guards only `gh pr create`, not later pushes, so this part is yours to keep.

## What the review checks against

The traps this repository has already paid for are written down once. Check the change against
them, not against memory:

- `CLAUDE.md`, sections "Brama" and "Konwencje, które łatwo złamać": the gate without `tail`,
  `MIX_ENV=test mix run`, `boundary` siblings, implementations pointing at the contract and never
  the other way round, checks in the macro body, `emit/1` and `issue/1` taking struct literals, English code and where Polish is allowed, the closing `”`,
  `encoding: :unicode`, zsh not splitting words.
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

Add to this list when a review finds a new kind of problem. If it is a rule about the code, it
belongs in `CLAUDE.md` instead.
