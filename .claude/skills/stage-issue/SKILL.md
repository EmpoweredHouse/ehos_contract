---
name: stage-issue
description: Run a stage of a planned programme in this repository (today the DD programme in `PLAN.md`) through a GitHub issue — tighten the stage's paragraph in `PLAN.md` before it starts, open the issue in plain English for a reader outside the team, record each decision on it as it is made, link every pull request with `Closes #N`, and close it with what came of the stage. Use when starting a stage from the "Postęp" table, when a decision about a stage is made, when opening a stage's pull request, and when a stage is merged. Not for one-off fixes outside a programme, which need no issue.
---

# A stage as a GitHub issue

`PLAN.md` is what a model reads first: it has to say what the programme is, where it stands and what comes
next, in a few lines a stage. It cannot also hold every decision, every review and every rejected option: it
had grown past 11 000 lines when this skill was written (6 October 2026), and a stage's "co wyszło" ran to
40 lines in the middle of it. So the record of a stage moves to its issue, and `PLAN.md` points there.

**One rule keeps the two from drifting: status lives only in `PLAN.md`, reasons live only in the issue.**
`PLAN.md` says ☐ / ◐ / ☑ and links the issue; the issue says what was decided and why. Copying either into
the other makes two versions, one of which goes stale — the reason this repository does not write to the
context repository (`CLAUDE.md`).

## What goes where

| `PLAN.md` | the stage's issue |
| --- | --- |
| the programme's outline, waves and order | the problem the stage solves, for a reader outside the team |
| the "Postęp" table: stage, wave, scope in a few words, dependencies, status, issue | what is in scope and what is deliberately left out |
| the stage's paragraph: two to five lines of what it changes, written before it starts | the expected result, and how anyone can see it |
| decisions that bind several stages (a user's choice before a wave) | every decision taken during the stage, with the options it beat |
| the migration note after a wave | the review: what each review found and what happened to it |
| | what a host has to do, one line for the migration note |
| | the pull requests, linked by GitHub through `Closes #N` |

`PLAN.md` stays in Polish, as `CLAUDE.md` says. **Issues, their comments and pull requests are in English**:
the project will be international, and what is left on GitHub is read by people outside this team.

Stages finished before this skill existed keep their "co wyszło" sections in `PLAN.md`: history is not
rewritten. Their issues are closed ones that link the pull request and the section.

## Steps

1. **Before the stage starts, tighten its paragraph in `PLAN.md`.** A stage not yet started may be rewritten:
   say in two to five lines what it changes and what it depends on, drop line numbers that have gone stale,
   and move anything that turned out to belong to another stage there. Do not touch stages already done.
2. **Open the issue** from `.github/ISSUE_TEMPLATE/stage.md`, with the labels `dd` and `wave-<n>` (the
   programme's and the wave's). The title names the change, not the stage code: "Contracts can name themselves",
   not "ID1". The stage code goes in the first line of the body.
3. **Mark the start in `PLAN.md`:** ◐, the branch, and the issue number in the "Postęp" table, in the stage's
   first commit.
4. **Record each decision on the issue when it is made**, as a comment: what was decided, the options that lost
   and why, and who decided (the user, or the assistant on a mechanical question). Not at the end, from memory.
5. **Every pull request of the stage says `Closes #N`** (or `Part of #N` when the stage takes several), so
   GitHub links it and closes the issue on merge. The review note (`pre-pr-review`) goes on the issue as a
   comment too, in the plain form below.
6. **When the stage is merged:** ☑ and the pull request in `PLAN.md`; a closing comment on the issue with what
   came of it — what changed for a user of the library, what is left for later and where, the line for the
   migration note. No new "co wyszło" section in `PLAN.md`.

## How an issue reads

Someone outside the team, not necessarily technical, should understand from the issue what was wrong and what
changes. Write for that person.

- **The problem first, in the reader's terms.** What goes wrong today, for whom, with one example from the
  test material (a clinic, an accounting firm, an equipment store). Not the module that will change.
- **No implementation names.** No module or function names, no refusal codes (`X10`, `D11`), no file paths,
  no line numbers. Say what the library will refuse or warn about and when ("the contract will not compile",
  "the check will warn"). The pull request carries the code; the issue links it.
- **Concrete over abstract.** "Two contracts could record events that look identical in the log" beats
  "improves identity guarantees". A number, a name or an example beats an adjective.
- **Scope as two short lists:** what is in, and what is deliberately out, with why for each "out".
- **The expected result as something checkable:** what a person will see — a warning, a refusal, a page, a
  test that passes.
- **Plain writing.** No filler words or phrases ("leverage", "robust", "it's worth noting", "seamless"), no
  "not X but Y" constructions, no colon reveals, no bold scattered mid-sentence, no closing summary. Active
  voice, direct verbs, sentences that each say one thing. The user's `no-ai-slop` skill has the full list; run
  its detect mode on a draft when in doubt.
- **Decisions in the same plain form:** "We chose A. B would have meant …; C would have meant …."

## Labels

- `dd` — every stage of the DD programme ("domain-driven design checked by code").
- `wave-0` … `wave-5` — the programme's wave.

A new programme gets its own label and the same waves, or none if it has one.
