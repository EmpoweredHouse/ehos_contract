# Roadmap

Where the library stands and what comes next. Each stage is a GitHub issue that holds its scope, its decisions
with the options they beat, its review and its pull requests; this file holds only the status and a link
(`CONTRIBUTING.md`, "Where the work is recorded").

☐ not started · ◐ in progress · ☑ in `main` · ✕ dropped

## Where things stand (20 October 2026)

- **Released:** v0.7.0 (the engine 0.7.0, `eh_os_contract_graph` 0.4.0, `eh_os_contract_auth` 0.4.0), in use by
  applications that install it from git. `main` is at 0.7.1-dev.
- **Now:** the publication programme, which makes this repository public and the packages installable from
  Hex.
- **Open questions for the maintainers:** whether the design record keeps the people it names and its links
  into private repositories (#379); the overlays' cost on large logs, a default window or a cache (#297).

## The publication programme (from 18 October 2026)

Issues labelled [`publication`](https://github.com/EmpoweredHouse/eh-os-contract/issues?q=label%3Apublication).

| Stage | What | Issue | Status |
| --- | --- | --- | --- |
| PB1 | The sandbox host owns its repo | #366 | ☑ #367 |
| PB2 | Invented case studies (library loans, subscription billing, order fulfilment) cover what only client material tested | #369 | ☑ #370, #372, #373, #374 |
| PB3 | English in the packages, their tests and the skills; no client named in published docs | #375 | ☑ #376, #378, #380–#384 |
| PB4 | The client material moves to a private repository | #386 | ☑ #387, #388 |
| PB4b | The sandbox fills its development log with drift on the invented case studies | #389 | ☑ #390 |
| PB5 | The repository reads for someone outside the team | #393 | ◐ |
| PB6 | Hex readiness: dependencies by version, `esbuild` dev-only, Spark's range, `hex.build` and an Elixir/OTP matrix in CI | — | ☐ |
| PB7 | Publication: the scan, GitHub settings, Hex | — | ☐ |

**PB5.** The working plan leaves the tree for this file; the maintainers' Claude Code setup becomes opt-in; links
into private repositories and their decision codes become what they meant; the community files (security policy,
code of conduct, notice, issue templates) are added. Issue and plan citations in code comments wait for PB7.

**PB6.** The packages' `mix.exs` stop depending on each other by `path:` or `git:` when published, the
dashboard's asset build stops needing a private dependency, and CI builds each package as Hex would and runs the
suite on the oldest and newest supported Elixir and OTP.

**PB7.** A secret scan of the final tree, the repository's GitHub settings, then the packages on Hex in
dependency order, and the applications moved to them.

## Earlier programmes

- **DD, "domain-driven design checked by code"** (5–18 October 2026): six waves, each rule of the model that
  can be written down given something that checks it. Done; its stages are the issues labelled
  [`dd`](https://github.com/EmpoweredHouse/eh-os-contract/issues?q=label%3Add), by wave (`wave-0` …
  `wave-6`), released in v0.6.0 and v0.7.0.
- **Before DD** (August–September 2026): the engine, the second contract language (`docs/adr/contract-v2.md`),
  the dashboard, the credential verifier and the graph renderer. Their record is `docs/adr/`, the packages'
  changelogs and the closed issues.
