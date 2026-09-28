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
  failed fetch — and a redirect, a body over 64 KB or more than 16 keys is a failed fetch. The key set
  must come over `https` (`http` only for `localhost`), or the boot fails. A credential whose `exp` is
  more than fifteen minutes away, or whose header carries `crit`, is `:bad_signature`.
  `EhOsContract.Auth.ready?/0` answers whether any key is held, for the host's
  health check. `EhOsContract.Auth.Migrations` creates the table.
- **`EhOsContract.Auth` is an `EhOsContract.Authorizer`** (`config :eh_os_contract, authorizer:
  EhOsContract.Auth`): `EhOsContract.Authorizer.check/2`'s answer, and one row per decision in
  `eh_os_contract_auth_decisions` — subject, kind, capability, contract and version, the scope
  dimension and value, `allowed` or `refused`, the reason. Migration version 2 creates the table.
- **`EhOsContract.Auth.Plug`** verifies a bearer credential in front of `EhOsContract.Plug`, and
  answers 401 with `no_credential` or the reason `verify/2` refused it.
- **`EhOsContract.Auth.Testing`**: `credential/3` signs with a test key pinned in the running key
  store (`EhOsContract.Auth.Keys.pin/2`), and `assert_every_entry_refuses/3` calls a host's entry
  point for every capability its contracts declare with a credential that lacks it.
- **`req_options: [connect_options: …]` keeps the two-second connect timeout.** A host's
  `:connect_options` are merged over the package's key by key instead of replacing them, so naming
  an internal certificate authority (`transport_opts: [cacertfile: …]`) no longer drops the fetch's
  connect timeout to Mint's thirty seconds. A `timeout:` given there still replaces it, and
  `connect_options: nil` is read as none.
- **`req_options` takes only what an integration needs, and the boot fails on anything else**:
  `connect_options` with `timeout` and `transport_opts` naming a certificate authority
  (`cacertfile`, `cacerts`), `receive_timeout`, `inet6`, and `plug` or `adapter` only with
  `config :eh_os_contract_auth, pin_keys: true` — each once. Before, any option was accepted, and
  several quietly took a guarantee away: `redirect: true` or its old name `follow_redirects`,
  `into:`, `url:`, `transport_opts: [verify: :verify_none]`, `verify_fun`, `server_name_indication`,
  `hostname`, `finch_request`, a proxy. The fetch no longer takes Req's own defaults either
  (`config :req, default_options`, plugins included), which reached it from the application's
  configuration for its other requests. The child's
  own options are checked too: `url:`, which replaced the address the boot had checked, and any
  name `EhOsContract.Auth.Keys.start_link/1` does not take, which was dropped without a word.
  `start_link/1` checks all of it, the https address included, so starting it directly is no way
  around. `transport_opts: nil` is read as none, where it broke every fetch.
