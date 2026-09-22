# Changelog

## The rule this file exists for

**A change that can move a verdict raises the MINOR version and gets a line here.**

A verdict is anything the conformance report prints as a number or a state: an
overlay edge's state, a `trace` verdict, a path counted as untraversed, a run
counted as exceeding a deadline, a declaration counted as changed. Wording,
docstrings, tests and fixtures do not.

The rule exists because a report is arithmetic, and two clients running two engine
versions get two answers to the same question. `PNS.version/0` puts the version in
the report; this file says what each one changed. A version in a report that
nothing explains is decoration.

Nothing mechanical enforces this — no test can. The `review-pr` skill carries it:
a diff touching `lib/pns/{trace,graph,conformance,deployment,report}.ex` with no
entry here goes back to its author.

The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this
package follows [semantic versioning](https://semver.org/spec/v2.0.0.html).

## 0.2.0 — 2026-09-22

### Added

- Every declaration now carries its own digest, recorded per deployment
  (`PNS.Contract.declaration_digests/0`, `PNS.Migrations` v02). `PNS.Deployment.diff/2`
  reports which declaration moved, where before it could only compare event names
  and handler edges — so a changed `within`, `retain`, `identity`, `instance` or
  payload type registered as four empty lists.
- `PNS.Deployment.declaration_boundaries/1`: when each declaration last changed.
- `PNS.version/0`, and the report says which engine computed it.

### Changed

- **Verdict-moving.** A `trace` assertion's counts now cover only runs that began
  after that assertion last changed. Runs from before it are counted separately
  and named in the report with the date of the change. Previously an edit to
  `within` retroactively rejudged the whole log at the moment of deployment, with
  nothing in the report to say the rule had moved.
- **Verdict-moving.** An assertion whose every run predates its last change now
  reads as "no run was judged under the rule as it now stands" rather than as
  "there was no run on which this could be judged". The second is an absence; the
  first is not.
- `PNS.Deployment.record!/1` replaces `declaration_digests` on conflict instead of
  leaving the row alone, so a deployment recorded before v02 is backfilled rather
  than staying blind for the version actually running.

## 0.1.0 — never published

Everything up to 2026-09-22, recorded here after the fact because the rule above
did not exist while it was happening. **These entries are retroactive and carry no
version of their own** — inventing numbers for releases nobody published would be
a second source of truth about a sequence that never happened.

At least five changes at this version moved a verdict:

- A process with no runs reports `basis: :no_runs` rather than reporting every
  declared path as untraversed. Zero runs is not evidence that a path is dead.
- Work sitting in the queue counts as in flight, not as a path nobody took.
- A step that is attempted and fails was split out of "never attempted". Both were
  previously one line, and they go to different people.
- `:suspended` became a fourth `trace` verdict: a run whose window contained an
  external dependency's outage is not a breach on the client's side.
- `unverified` reaches a `trace` by name, so the sharpest assertion the engine can
  make — the one most likely to be a guess — can be declared without being counted
  as measured.
