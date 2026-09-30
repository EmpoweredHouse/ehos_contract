# Changelog

The rule this package follows is the one written in `packages/eh_os_contract/CHANGELOG.md`: a
change a consumer can see gets a line here, in the same commit.

The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

- **`up/1` and `down/1` run what the host's migration queued before them first**, as the engine's do: a
  `CREATE SCHEMA` queued ahead of them left the version to be read in `public`, and with `search_path:
  "ledger, public"` nothing was created in `ledger`.

- **The tables work in a schema other than `public`** (issue #51; `eh-os` D-54, D-56).
  `EhOsContract.Auth.Migrations` read and wrote its version on `public.eh_os_contract_auth_keys` by name, and
  in a schema of the application's own failed or, where `public` had the tables, created nothing. It now
  reads it in `current_schema()`, where the tables are created, as the key store and the decisions table
  already resolved theirs through the connection's `search_path`. The role the application runs as needs
  only `SELECT`, `INSERT`, `UPDATE` and `DELETE` on the tables and `USAGE` on the sequences.

- **E11: the manifest reads `EhOsContract.Registry.contracts/0`**, the engine's one list of contracts from its
  0.3.0; `Manifest.build/2` raises "has no contracts" for a domain with none.

- **`mix eh_os_contract.manifest --output PATH`** writes the selected domain's human command
  capabilities and roles as strict `ehos.manifest/v1`. `EhOsContract.Auth.Manifest.build/2` is the same
  projection as data. System actors and actors with no command capability are not roles; query and record
  capabilities wait for a later EHOS manifest schema instead of appearing under fields v1 would reject. If
  two registered modules expose the same public domain name, `--domain` refuses the ambiguity and names both
  modules instead of silently taking the first scan result.

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
- **`cacertfile:` or `cacerts:` names an internal certificate authority, in place of
  `req_options:`**, which is gone. `req_options` handed the host all of Req's options, so
  `connect_options: [transport_opts: [cacertfile: …]]` dropped the fetch's two-second connect
  timeout to Mint's thirty seconds, and `redirect: true` or `verify: :verify_none` quietly undid
  what the key set is trusted by. The fetch's options are now the package's, with the host's
  authority beside the two seconds. An option the key process does not take — `req_options:`
  among them — fails the boot. `url:` in `EhOsContract.Auth`'s child options, which replaced the
  address after its https check, is refused, and `EhOsContract.Auth.Keys.start_link/1` checks
  the address itself, so a key process listed directly is held to https too. `plug:`, for tests,
  needs `config :eh_os_contract_auth, pin_keys: true`.
