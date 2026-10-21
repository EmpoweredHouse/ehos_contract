<!--
The first line says what this belongs to; keep one of them:
  Closes #N      the pull request that finishes an issue's work
  Part of #N     an earlier pull request of the same issue
  No issue: …    a change that needs none, and why (a typo, a dependency bump)
-->
Closes #

## What

What changes, for a user of the library first. A refusal or rule code goes in parentheses after its meaning:
"a reaction to another context's event that leaves delivery out (X10)".

A change a host can see has its line under `## [Unreleased]` in the package's `CHANGELOG.md`. Otherwise write
why on a line of its own here, `No changelog: <why>` (`CONTRIBUTING.md`, "Changelogs and releases").

## How it was tested

The commands run and what they printed, with the gate's exit code (`mix check` in `sandbox/`).

## Review

What each review found and what happened to each finding (what to look at: `.claude/review.md`), or that
the change is documentation only.
