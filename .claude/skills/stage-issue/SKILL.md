---
name: stage-issue
description: Run a stage of a planned programme in this repository (today the DD programme in `PLAN.md`) through a GitHub issue — tighten the stage's paragraph in `PLAN.md` before it starts, open the issue with a plain "In short" for a reader outside the team and the technical detail after it, record each decision on it as it is made, link every pull request with `Closes #N`, and close it with what came of the stage. Use when starting a stage from the "Postęp" table, when a decision about a stage is made, when opening a stage's pull request, and when a stage is merged. Not for one-off fixes outside a programme, which need no issue.
---

# A stage as a GitHub issue

`PLAN.md` is what a model reads first: it has to say what the programme is, where it stands and what comes
next, in a few lines a stage. It cannot also hold every decision, every review and every rejected option: it
had grown past 11 000 lines when this skill was written (6 October 2026), and a stage's "co wyszło" ran to
40 lines in the middle of it. So the record of a stage moves to its issue, and `PLAN.md` points there.

**One rule keeps the two from drifting: status lives only in `PLAN.md`, reasons live only in the issue.**
`PLAN.md` says ☐ / ◐ / ☑ and links the issue; the issue says what was decided and why. Copying either into
the other makes two versions, and one of them goes stale.

## What goes where

`CONTRIBUTING.md`, "Where things live", has the one table of what `PLAN.md`, an issue, `docs/adr/`, a pull
request and the code each hold, and the scheme a person follows. This skill does not repeat it; it says what
an assistant does at each step. In short: `PLAN.md` holds the programme's outline, the status, a few lines a
stage and the issue's link; the issue holds the problem, scope, expected result, decisions and the review;
`docs/adr/` holds what the library is meant to be, changed only by a dated amendment.

**A decision goes to `docs/adr/` when a reader of the library in six months would misunderstand it without
it** — a rule of the contract, a shape later stages build on (an identifier's form, what a reaction across
contexts must declare). A decision about how the stage was carried out stays in the issue (which module holds
a check, which code a refusal gets). An amendment ends with the issue's link, and the issue lists the
amendments its stage made under "Changes to the design record". `PLAN.md` links only the issue.

**Issues, their comments and pull requests are in English**: the project will be international, and what is
left on GitHub is read by people outside this team. So are new entries in `PLAN.md` from 6 October 2026; its
earlier, Polish history is not translated (`CLAUDE.md`).

Stages finished before this skill existed keep their "co wyszło" sections in `PLAN.md`: history is not
rewritten. Their issues are closed ones that link the pull request and the section.

## Steps

1. **Before the stage starts, tighten its paragraph in `PLAN.md`.** A stage not yet started may be rewritten:
   say in two to five lines what it changes and what it depends on, drop line numbers that have gone stale,
   and move anything that turned out to belong to another stage there. Do not touch stages already done.
2. **Open the issue** from `.github/ISSUE_TEMPLATE/stage.md`, with the programme's label (`dd` for the DD
   programme) and, when the programme has waves, the wave's (`wave-<n>`). The template applies none, so that a
   stage of another programme does not get `dd` by default. The title names the change, not the stage code: "Contracts can name themselves",
   not "ID1". The stage code goes in the first line of the body.
3. **Mark the start in `PLAN.md`:** ◐, the branch, and the issue number in the "Postęp" table, in the stage's
   first commit. Name the branch after the issue, `dd/<issue>-<few-words>` (`dd/165-contract-id`), and end every
   commit message of the stage with `Part of #N`, so `git blame` leads from a line to the issue. A code comment
   that cites the stage cites the issue too: `plan DD, ID1 (#165)`.
4. **Record each decision on the issue when it is made**, as a comment: what was decided, the options that lost
   and why, and who decided (the user, or the assistant on a mechanical question). Not at the end, from memory.
   A decision that changes what the library is meant to be also gets its dated amendment in `docs/adr/`, linking
   the issue, and the issue's "Changes to the design record" names it.
5. **The pull request that finishes the stage says `Closes #N`**, so GitHub links it and closes the issue on
   merge. When the stage takes several, the earlier ones say `Part of #N`, which links them and closes nothing;
   only the last one says `Closes #N`. If a stage ends without such a pull request, close the issue by hand
   after the closing comment. The review note (`pre-pr-review`) goes on the issue as a
   comment too, in the plain form below.
6. **When the stage is merged:** ☑ and the pull request in `PLAN.md`; a closing comment on the issue with what
   came of it — what changed for a user of the library, what is left for later and where, the line for the
   migration note. Check the issue is closed; a comment alone does not close it. No new "co wyszło" section in
   `PLAN.md`.

## How an issue reads

An issue has two readers, and both read the same issue: someone outside the team, not necessarily technical,
who wants to know what was wrong and what changes, and an engineer who will build or review it. Neither part
is cut down for the other (6 October 2026; before that, issues carried no technical detail at all).

- **"In short" first, for anyone.** What goes wrong today, for whom, with one example from the test material
  (a clinic, an accounting firm, an equipment store), and what will be different once the stage is done:
  what the library will refuse or warn about and when ("the contract will not compile", "the check will
  warn"). No module or function names, refusal codes or file paths in this section; a reader who stops here
  knows what the stage is for.
- **The technical part has no such limit.** Modules, functions, files, refusal and rule codes, the order of
  the work — whatever an engineer needs. A code still never stands alone: its meaning first, the code in
  parentheses, "a reaction to another context's event that leaves delivery out (X10)". Line numbers stay
  out; they go stale before the issue closes.
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
