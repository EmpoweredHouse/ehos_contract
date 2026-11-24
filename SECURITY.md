# Security

## Reporting a vulnerability

Please report it privately, through GitHub's private vulnerability reporting: the **Security** tab of this
repository, then **Report a vulnerability**. Do not open a public issue or pull request for it.

Say what is affected (a package and its version, or a commit), what an attacker can do, and how to reproduce it.
A minimal contract or a failing test helps most. We will acknowledge the report, keep you informed while we work
on it, and credit you in the release notes unless you would rather not be named.

## What is in scope

The four packages under `packages/`: the engine (`ehos_contract`), the dashboard (`ehos_contract_web`), the
credential verifier (`ehos_contract_auth`) and the graph renderer (`ehos_contract_graph`). For example:

- a command, recording or query that `EhosContract.call/3` or `EhosContract.Plug` lets through without the
  capability or the scope it needs;
- a credential `ehos_contract_auth` accepts that it should refuse, or a key set it can be made to take from
  somewhere else;
- personal data readable after its subject was erased, or written in the clear where it should be encrypted;
- a dashboard or API route that shows more than its host's resolver allows.

The `ehos-contract` Claude Code plugin under `plugins/` is in scope too: applications enable it, and its
skills steer their assistant. So are the workflows under `.github/workflows/`.

Not a finding: the keys, salts and `secret_key_base` values in `sandbox/config/` and in each package's
`config/` and tests. They were made for development and tests alone, on purpose, and no package ships them
(each package's `mix.exs` lists the files it publishes).

## Supported versions

The latest released version of each package. Until 1.0 a fix comes in a new minor or patch version, not as a
backport.
