# Changelog

The rule this package follows is the one written in `packages/eh_os_contract/CHANGELOG.md`: a
change a consumer can see gets a line here, in the same commit.

The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

- **The package** (contract v2 §16, D14; `eh-os` D-33, D-34). `EhOsContract.Auth.verify/1,2`
  turns an EHOS credential — a JWT signed with Ed25519 — into an `EhOsContract.Actor`, or refuses
  it with `:expired`, `:unknown_key`, `:bad_signature`, `:wrong_audience`, `:wrong_issuer` or
  `:no_keys`. `EhOsContract.Auth` is a child for the application's supervision tree that keeps
  EHOS's public keys: loaded from `eh_os_contract_auth_keys` at start, fetched from the JWKS every
  five minutes and early on an unknown `kid`, at most once every thirty seconds, and unchanged by a
  failed fetch. `EhOsContract.Auth.ready?/0` answers whether any key is held, for the host's
  health check. `EhOsContract.Auth.Migrations` creates the table.
