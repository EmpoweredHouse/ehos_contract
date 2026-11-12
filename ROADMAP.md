# Roadmap

Where the library stands and what comes next. Each stage is a GitHub issue that holds its scope, its decisions
with the options they beat, its review and its pull requests; this file holds only the status and a link
(`CONTRIBUTING.md`, "Where the work is recorded").

☐ not started · ◐ in progress · ☑ in `main` · ✕ dropped

## Where things stand (12 November 2026)

- **Released:** v0.14.2, with `eh_os_contract_auth` 0.13.1 (in the development mode, "Sign in" opens
  `/dev/sign-in` and a start without a local EHOS logs no false key error; a form of `/dev/sign-in` without
  its CSRF token gets 403; `pin_keys: true` is refused in a release and in a container EHOS started) and the
  engine 0.14.2, which changes nothing; the dashboard stays at 0.9.0 and the graph renderer at 0.9.1, from
  v0.14.0. The plugin's skills are at 0.14.3. Applications install them from git. The pull request after the
  tag moves each released package to its next patch's `-dev`.
- **Now:** the publication programme, which makes this repository public and the packages installable from
  Hex. PB6 is in progress (#421).
- **Open questions for the maintainers:**
  - the library's name before its first Hex release, since a name on Hex is permanent;
  - whether `eh_os_contract_auth` is published under the library's name;
  - whether the design record keeps the people it names and its links into private repositories (#379);
  - whether the graph's overlays, which read the whole log on each request, get a default window or a cache
    (raised in the review of #311).

## The publication programme (from 18 October 2026)

Issues labelled [`publication`](https://github.com/EmpoweredHouse/eh-os-contract/issues?q=label%3Apublication).

| Stage | What | Issue | Status |
| --- | --- | --- | --- |
| PB1 | The sandbox host owns its database connection and test helpers | #366 | ☑ #367 |
| PB2 | Invented case studies (library loans, subscription billing, order fulfilment) cover what only client material tested | #369 | ☑ #370, #372, #373, #374 |
| PB3 | English in the packages, their tests and the skills; no client named in published docs | #375 | ☑ #376, #378, #380–#384 |
| PB4 | The client material moves to a private repository | #386 | ☑ #387, #388 |
| PB4b | The sandbox fills its development log with drift on the invented case studies | #389 | ☑ #390 |
| PB5 | The repository reads for someone outside the team | #393 | ☑ #394, #395, #396 |
| PB6 | Hex readiness: dependencies by version, `esbuild` dev-only, Spark's range, `hex.build` and an Elixir/OTP matrix in CI | #421 | ◐ |
| PB7 | Publication: the scan, GitHub settings, Hex | — | ☐ |

**PB6.** The packages' `mix.exs` stop depending on each other by `path:` or `git:` when published, the
dashboard's asset build stops needing a private dependency, and CI builds each package as Hex would and runs the
suite on the oldest and newest supported Elixir and OTP.

**PB7.** A secret scan of the final tree; the repository's GitHub settings, among them private vulnerability
reporting (`SECURITY.md` relies on it), reported content sent to the maintainers (Moderation options →
Reported content, which `CODE_OF_CONDUCT.md` relies on) and actions pinned by SHA; the open issues that describe a security
weakness triaged before they become public; then the packages on Hex in dependency order, and the
applications moved to them.

## Stages outside a programme

| Stage | What | Issue | Status |
| --- | --- | --- | --- |
| Docs by the writing rules | Each hand-written page rewritten by `ehos-dev:voice` and `ehos-dev:diagrams`, `contract.md` first | #517 | ☑ #523, #532, #535, #538, #540, #545, #546, #554, #556, #564, #574, #577, #585, #588, #590 |

## Earlier programmes

- **DD, "domain-driven design checked by code"** (5–18 October 2026): seven waves, in which each rule of the
  model that can be written down got something that checks it. Done but for #287; its stages are the issues
  labelled [`dd`](https://github.com/EmpoweredHouse/eh-os-contract/issues?q=label%3Add), by wave (`wave-0` …
  `wave-6`), released from v0.3.0 to v0.7.0.
- **Before DD** (August to early October 2026): the engine, the second contract language (`docs/adr/contract-v2.md`),
  the dashboard, the credential verifier and the graph renderer. Their record is `docs/adr/`, the packages'
  changelogs and the closed issues.
