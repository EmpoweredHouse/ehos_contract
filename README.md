# ehos_contract

[![check](https://github.com/EmpoweredHouse/ehos_contract/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/EmpoweredHouse/ehos_contract/actions/workflows/ci.yml)

This repository holds `ehos_contract`, an engine for event-driven Elixir applications, and three
packages around it. You describe a business process as Elixir modules. The application runs on these
modules, and the engine checks if what occurred agrees with them. This page is for a person who
meets the repository for the first time. [The glossary](packages/ehos_contract/docs/glossary.md)
defines each word of the engine.

## Which problem does it solve?

The engine finds where the running system does not do what the business agreed, also when no error
occurs.

![The application runs on the contracts and appends events, and conformance compares the log with what the contracts and process modules declare.](packages/ehos_contract/docs/img/conformance-flow.svg)

[What is ehos_contract?](packages/ehos_contract/docs/introduction.md) tells each step of this
picture, and what the engine does not do.

## What does the report show?

A process module declares a promise: after a case is opened, within 3 days its invoice is filed, or
the case is flagged for review. In one month, 40 cases were opened. The code filed 39 of them, and
did not file or flag one. This is a part of what `mix ehos_contract.report` prints for the month:

```
PROCESS: Invoice filing
  Runs in this period: 40, one per case_id.
  Rule: after "Case opened" within 3 days, "Invoice filed" follows, or else "Invoice flagged for manual review".
    BREACHED in 1 of 40 runs.
```

The report does not show a stack trace or the contents of the invoice. It shows that the system did
not do what the business agreed, one time in 40.

## Which packages does it hold?

| Package | What it does |
| --- | --- |
| [`ehos_contract`](packages/ehos_contract) | The engine: the domain and contract languages, dispatch, the log, conformance. |
| [`ehos_contract_web`](packages/ehos_contract_web) | A dashboard that an application mounts. It shows the conformance and the graph of each contract. |
| [`ehos_contract_graph`](packages/ehos_contract_graph) | Draws the graph of a contract or a domain in a LiveView. |
| [`ehos_contract_auth`](packages/ehos_contract_auth) | Connects an application to EHOS, the platform that hosts it: it verifies the credentials that EHOS issues. |

The packages install from git. [Getting started](packages/ehos_contract/docs/getting-started.md)
installs the engine. The README of each other package tells how to install it.

## Is there help for an assistant?

This repository is also a Claude Code marketplace. Its plugin `ehos-contract` gives an assistant
skills that write contracts by the rules of the engine.
[Enable the ehos-contract plugin](plugins/ehos-contract/README.md) tells how.

## Which version is it?

The packages are before version 1.0. A release is a tag of this repository, `vX.Y.Z`, and the
`CHANGELOG.md` of each package tells what changed. Applications install the packages from git.
Until 1.0, a minor version can break an application, and its changelog tells how to upgrade.
[`ROADMAP.md`](ROADMAP.md) tells what is planned.

## Next steps

- [What is ehos_contract?](packages/ehos_contract/docs/introduction.md): what the engine does,
  and what it does not do.
- [Getting started](packages/ehos_contract/docs/getting-started.md): install the engine and
  dispatch a first command.
- [Write a domain, a contract and a process module](packages/ehos_contract/docs/contract.md): the
  full task.
- [Contributing](CONTRIBUTING.md): the layout of the repository, its gate, and how work goes to
  `main`. Also the [code of conduct](CODE_OF_CONDUCT.md).
- [Security](SECURITY.md): report a security problem privately, not in an issue.

## Background

The design record holds the first decisions and the alternatives that they rejected:

- [The starting assumptions](docs/adr/architecture.md), written under the earlier name `pns`.
- [The contract language, version 2](docs/adr/contract-v2.md).
- [Design rationale](docs/adr/design-rationale.md) and [technology notes](docs/adr/technology-notes.md).

Licence: [Apache 2.0](LICENSE). [`NOTICE`](NOTICE) lists the third-party software that the packages
bundle.
