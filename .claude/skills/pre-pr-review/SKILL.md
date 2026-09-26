---
name: pre-pr-review
description: Review your own change to this repository with /code-review, settle what it finds, pass the gate and record the review as a git note, before opening a pull request or pushing new commits to one. Use whenever you are about to run `gh pr create`, when the hook in `.claude/settings.json` refuses `gh pr create` because HEAD has no review note, and when the user asks to review a change before it is sent. Not for reviewing someone else's pull request — that is `review-pr`.
---

# Reviewing a change before its pull request

Every pull request to this repository is reviewed by its author before it is opened: run
`/code-review`, settle what it finds, pass the gate, record it. A Claude Code hook
(`.claude/settings.json`) enforces the last step: `gh pr create` (and its alias `gh pr new`) is
refused until `HEAD` carries a note in `refs/notes/review`. The note belongs to one commit, so a
new commit, amend or rebase leaves the new `HEAD` without one.

The hook is a reminder for this workflow, not access control. It reads the local `HEAD`, not the
branch the pull request will carry (`--head`), it does not see an invocation behind `env`,
`bash -c` or a shell keyword, it lets everything through on a machine without `jq`, and it
refuses `--help` too (`gh help pr create` works). Keeping to the steps is what makes the note
mean something.

This is the author's half. The reviewer's half is `.claude/skills/review-pr/SKILL.md`; read it
before step 3, because what it tells the reviewer to look at is what your review should have
found first.

Skip `/code-review` only for a change to documentation alone, and say so in the pull request.
Documentation alone means Markdown that no part of `mix check` reads: `PLAN.md`, `CLAUDE.md`,
`README.md`, `docs/`, `.claude/skills/`. `packages/eh_os_contract/docs/contract.md` does not
qualify, because `eh_os_contract.docs --check` compares it with the schema. The hook still asks
for the note: record it once you have checked the diff is documentation only
(`git diff --stat origin/main..HEAD`).

## Steps

1. **Commit everything.** The review reads committed history, and the note covers one commit.
2. **Rebase onto the current `origin/main`** (`git fetch origin && git rebase origin/main`), so the
   review covers only this change.
3. **Review the exact range:** `/code-review high origin/main..HEAD`.
4. **Settle every finding** as one of:
   - **fixed**: a real problem. Fix it in its own commit, with a message stating the failure
     scenario, and a test that fails on the old code. Verify it in reverse: revert the fix and
     watch that test, and no other, go red. `review-pr` §4 has examples of how this repository
     writes that down.
   - **no change needed**: the finding is wrong. Write down why in one sentence.
   - **skipped**: real but out of scope. Say so in the pull request, with why.

   Then report the outcomes with ReportFindings (`fixed` / `no_change_needed` / `skipped`).
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
   `git notes --ref=review add -m '<what the review found and what happened to each finding>' HEAD`
   (`-f` replaces a note already on that commit). Notes stay local: `refs/notes/review` is not
   pushed.
8. **Open the pull request.** Its "How it was tested" section says what you ran, with the gate's
   exit code. A "Review" section lists what the review found and what happened to each finding,
   or says the change is documentation only.

After review comments or a failed CI run, fix, commit, and go through steps 3–7 again for the new
commits before pushing them. Before any push to an existing pull request, check it is still open: a
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
  `MIX_ENV=test mix run`, `boundary` siblings, MFA rather than capture, checks in the macro body,
  literal event names, English code and where Polish is allowed, the closing `”`,
  `encoding: :unicode`, zsh not splitting words.
- `.claude/skills/review-pr/SKILL.md`: what the gate already guarantees, and where a human
  reviewer's attention goes instead.
- On a v2 stage branch (`dsl-v2/eN-*`): the rules of every commit and the stage's acceptance
  criteria in `PLAN.md`, "Dopisek 25 września (2) — Etap 6".

Kinds of problems a review here found that neither file names yet:

- A guard over shell commands matches the invocation, not the text. The first version of this
  repository's hook refused every command that merely mentioned `gh pr create`, a heredoc and a
  file write included (fixed 25 September).

Add to this list when a review finds a new kind of problem. If it is a rule about the code, it
belongs in `CLAUDE.md` instead.
