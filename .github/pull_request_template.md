<!--
The first line says what this belongs to; keep one of them:
  Closes #N      the pull request that finishes an issue's work
  Part of #N     an earlier pull request of the same issue
  No issue: …    a change that needs none, and why (a typo, a dependency bump)
The sections go from what anyone needs to what a reviewer needs. Fill what applies to your change,
in short, plain sentences, and remove these comments as you fill the sections. A small fix needs
a few lines, not every section.
-->
Closes #

## In short

<!-- For anyone: no module names, file paths or codes. One or two sentences each. -->

- **Problem:**
- **Fix:**
- **How:**
- **Benefit:**

## Before and after

<!-- One concrete example of what changes: what a person runs, sees or gets now, and after the
merge. A command and its output, a screenshot, an error message, a diff-sketch. -->

**Before:**

**After:**

## Risks and consequences

<!-- Answer each item: "Yes, a revert undoes it" or "No" and why; who sees what; "Nothing" or the
step. -->

- **Can it be undone:**
- **What it can break, and for whom:**
- **What a user must do:**

## What

<!-- For the reviewer: what the change does in the code, with the smallest view that shows it (a
diff-sketch of a file tree or a call tree, pseudocode), and where to spend review attention. -->

## Why

<!-- The decisions and their links: the issue, a decision record, the options that lost. "In
short" has the problem; do not repeat it. -->

## How it was tested

### Automated

<!-- The tests added or changed, and the gate that ran, with its exit code. -->

### By hand

<!-- The exact steps, and what you saw. Or why the change needs none. -->

## Review

<!-- What a review before this pull request found, by you or an assistant, and what became of each
finding: fixed, no change needed (why), or a follow-up issue. `.claude/review.md` lists what a
reviewer here looks at. Or write that the change is documentation alone. -->
