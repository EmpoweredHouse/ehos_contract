# EhOsContract.Auth

Verifies the credentials EHOS issues, for an application built on
[EhOsContract](../eh_os_contract). It checks the signature locally, against keys it keeps in the
application's own database, so the application goes on accepting credentials while EHOS is
down, and after a restart while EHOS is down.

The engine verifies nothing: it asks an `EhOsContract.Authorizer` what a credential's actor may
do, and this package is the implementation for EHOS's credentials (contract v2 §16, D14; `eh-os`
D-33, D-34). The engine does not depend on it.

Four parts: `EhOsContract.Auth.verify/2` and the key store behind it, `EhOsContract.Auth` as the
engine's `Authorizer` with a row for every decision, `EhOsContract.Auth.Plug` for a bearer token in
front of `EhOsContract.Plug`, and `EhOsContract.Auth.Testing` for a host's tests.

## Installation

From git, beside the engine, with the same `git:` and `sparse:` shape:

```elixir
def deps do
  [
    {:eh_os_contract,
     git: "https://github.com/EmpoweredHouse/eh-os-contract.git",
     sparse: "packages/eh_os_contract"},
    {:eh_os_contract_auth,
     git: "https://github.com/EmpoweredHouse/eh-os-contract.git",
     sparse: "packages/eh_os_contract_auth"}
  ]
end
```

## Wiring it

```elixir
# config/config.exs
config :eh_os_contract, authorizer: EhOsContract.Auth

config :eh_os_contract_auth,
  issuer: "https://ehos.example.com",
  audience: "rehmed/production"
  # jwks_url: defaults to the issuer's "/.well-known/jwks.json"

# the application's supervision tree, after the repo
children = [MyApp.Repo, EhOsContract, EhOsContract.Auth]

# a migration
defmodule MyApp.Repo.Migrations.AddEhOsContractAuth do
  use Ecto.Migration

  def up, do: EhOsContract.Auth.Migrations.up()
  def down, do: EhOsContract.Auth.Migrations.down()
end
```

The repo is the engine's, `config :eh_os_contract, :repo`.

```elixir
EhOsContract.Auth.verify(token)
#=> {:ok, %EhOsContract.Actor{kind: :credential, subject: "u-81", capabilities: ..., scopes: ...}}
#   | {:error, :expired | :unknown_key | :bad_signature | :wrong_audience | :wrong_issuer | :no_keys}
```

## Deciding, and recording every decision

`EhOsContract.Auth` is the `EhOsContract.Authorizer` the engine asks about every command and query
that arrives with a credential. It decides with `EhOsContract.Authorizer.check/2` alone — the
capability in `cap`, a scoped value among the values in `scp` — and writes one row to
`eh_os_contract_auth_decisions` for every decision, a refusal as carefully as an acceptance (`eh-os`
D-34): who, which capability, which contract and version, the scope value asked for, `allowed` or
`refused`, and the reason.

The row records the authorization, not the command. A command allowed here may still be rejected on
an invariant, and that is the engine's row in `eh_os_contract_commands`: two facts, two rows. The row
goes through the connection the call is on, so a caller that wraps `EhOsContract.dispatch/3` in a
transaction of its own and rolls it back rolls the row back too. A row that cannot be written fails
the call.

**What it costs.** Every command and query that arrives with a credential writes that row: one
`INSERT`, committed on its own before the engine's transaction starts, and for a query the only write
the call makes. `eh-os` D-34 asks for exactly this — a refusal recorded as carefully as an acceptance,
and a refusal cannot be written inside a transaction that never starts. Budget for one extra write per
call; the table carries no index beyond `decided_at` and `(subject, decided_at)`.

**How long rows are kept is the application's decision.** Nothing here deletes them. The index on
`decided_at` makes a periodic cleanup cheap, for instance from a job:

```elixir
MyApp.Repo.query!("DELETE FROM eh_os_contract_auth_decisions WHERE decided_at < now() - interval '400 days'")
```

keeping them as long as the application keeps its own log is the usual choice.

## Over HTTP

```elixir
pipeline :commands do
  plug :accepts, ["json"]
  plug EhOsContract.Auth.Plug
end

scope "/api" do
  pipe_through :commands
  forward "/", EhOsContract.Plug, contracts: [Rehmed.Contracts.VisitSettlement]
end
```

`EhOsContract.Auth.Plug` reads `authorization: Bearer <credential>`, and a credential `verify/2`
accepts goes on as `conn.assigns.eh_os_contract_actor`. Anything else stops with 401 and
`www-authenticate: Bearer`: `{"error": "no_credential"}` without one, `{"error": "<reason>"}` for
a credential it refuses. A refused credential is logged with its reason and gets no row, because it
names nobody; the rows are the decisions about actors that did verify.

## In a host's tests

```elixir
use EhOsContract.Auth.Testing

test "every entry point refuses a credential without the capability" do
  assert_every_entry_refuses([Rehmed.Contracts.VisitSettlement], %{
    "rehmed.record_payment" => fn token -> post_command(token, "rehmed.record_payment", ...) end,
    # ... one entry per capability the contracts declare
  })
end

token = credential("u-anna", ["rehmed.record_payment"])
```

The engine cannot drive a host's door, so the host maps every capability its contracts declare to a
function that calls its own entry point with a token. The check calls each with a credential that
grants every other capability, and asserts a `refused` row with `missing_capability` and nothing new
in the engine's log or `eh_os_contract_commands`. A declared capability without an entry fails it,
and so does an entry for one that is not declared, so a new command cannot be added unchecked.

`credential/3` signs with a key made once per test run and pinned in the running key store: trusted
like EHOS's, never written to the table, no EHOS or network needed. Pinning is allowed only with

```elixir
# config/test.exs
config :eh_os_contract_auth, pin_keys: true
```

and raises anywhere else, so nothing in a running application can make it trust a key EHOS did not
publish.

## Where the keys come from, and what to configure at integration

Nothing about the keys is delivered to the application or configured in it, except EHOS's
address. What each side holds:

| What | Who makes it | Where it lives | Who sees it |
| --- | --- | --- | --- |
| **Ed25519 key pair** that signs credentials | EHOS's Helm chart, `genPrivateKey "ed25519"`, when the Secret is missing, or the operator through `governance.signingKeys.existingSecret` | a Kubernetes Secret: `current.pem`, and `previous.pem` during a rotation | mounted read-only into EHOS's governance plane only. It never enters a database, and no application sees it |
| **Public keys** (JWKS) | EHOS, from the Secret | `GET <issuer>/.well-known/jwks.json` | anyone. This package fetches it and keeps a copy in `eh_os_contract_auth_keys` |
| **`kid`** in a credential's header | nobody: it is the key's RFC 7638 thumbprint | computed by EHOS when signing, and by this package from the JWKS | nobody configures it. This package never trusts the `kid` a JWKS writes beside a key |
| **TLS certificate** of EHOS's URL | whoever runs the cluster: cert-manager, a public or an internal authority | EHOS's ingress | checked by every fetch of the JWKS |

**The TLS certificate is the trust anchor.** A credential is trusted because its signature checks
against a key from the JWKS, and the JWKS is trusted because it came over HTTPS from the configured
issuer. Whoever could answer for that URL could publish keys of their own. So the certificate of
the issuer's URL is the one thing an integration has to get right. The fetch checks it against the
system's certificate authorities. An EHOS behind an internal authority needs that authority named,
through the options every fetch takes:

```elixir
children = [
  MyApp.Repo,
  EhOsContract,
  {EhOsContract.Auth,
   req_options: [connect_options: [transport_opts: [cacertfile: "/etc/ehos/ca.pem"]]]}
]
```

`:connect_options` given here are merged over the package's own, so the fetch keeps its two-second
connect timeout: without it, an EHOS address that drops packets would hold every fetch for Mint's
thirty seconds. A `timeout:` set in `connect_options` replaces the two seconds.

Do not turn certificate verification off to make a first integration work: the keys would then come
from whoever answers. For the same reason the package refuses to boot when the key set would be
fetched over anything but `https` (plain `http` is allowed for `localhost` only), and **follows no
redirect**: a key set answered from anywhere but the configured URL is a failed fetch.

**`req_options` takes only what an integration needs**, each option once, and the boot fails on
anything else:

| Option | For |
| --- | --- |
| `connect_options: [transport_opts: [cacertfile: …]]` or `[cacerts: …]` | an internal certificate authority |
| `connect_options: [proxy: …, proxy_headers: …]` | a proxy; TLS to EHOS is still checked through it |
| `connect_options: [timeout: …]`, `receive_timeout: …`, `inet6: …` | tuning the connection |
| `plug: …`, `adapter: …` | tests, in place of the network |

It is a list of what is allowed, not of what is unsafe, because Req, Finch and Mint have many
ways to undo what the key set is trusted by: an older name for `redirect`, TLS options that accept
any certificate or check it against another name, a body read past the 64 KB limit. None of them is
on the list. The address comes from the configuration only: `url:` in the child's options is refused
too.

**What the application configures, and nothing else:** `issuer`, which must be exactly the `iss`
EHOS writes, `audience` (`<application>/<environment>`, exactly the `aud` EHOS issues for this
application), `jwks_url` only if the JWKS is not at the issuer's well-known path, and the authority
above if it is not a public one.

**Rotation** is manual in v1 and happens on EHOS's side (`eh-os` D-33):

1. `current` moves to `previous`, and a new `current` is added;
2. EHOS is rolled out. It signs with the new key, and the JWKS publishes both;
3. after one credential lifetime, ten minutes, `previous` is removed.

The application does nothing. A credential signed with the new key names a `kid` it has not seen,
which triggers an early fetch, and the refresh every five minutes drops `previous` once the JWKS no
longer has it.

**How the key store behaves** (`EhOsContract.Auth.Keys`, `eh-os` D-34):

- at start it loads the last good key set from its table, then fetches the JWKS;
- it fetches again every five minutes, so a key removed from the JWKS, a compromised one for
  instance, stops being trusted within that interval without a restart;
- an unknown `kid` triggers an early fetch, at most once every thirty seconds;
- a failed fetch changes nothing: it is logged and the last good set stays in force. A key set with
  no Ed25519 key in it counts as a failed fetch, and so does a redirect, a body over 64 KB and more
  than 16 keys — a rotation holds two;
- an application that has never seen a key set refuses every credential with `:no_keys`, and logs
  it at start. This is the one case where "EHOS is down" becomes "nobody gets in", and
  `EhOsContract.Auth.ready?/0` answers `false` for it, for the host's health check.

Tests need neither EHOS nor a network: the package's own suite plays the JWKS endpoint with a
function plug handed to Req.

## The credential

A JWT, `alg: "Ed25519"` and nothing else, with `iss`, `sub`, `aud` (one string), `iat`, `exp`,
`jti`, `cap` (the capabilities, sorted), and `scp` when a capability is scoped (`eh-os` D-33,
D-40):

```json
{"sub": "u-81", "aud": "rehmed/production", "cap": ["rehmed.open_visits_for_clinic"],
 "scp": {"rehmed.open_visits_for_clinic": {"clinic_id": ["7"]}}}
```

The grants travel in the credential. The application stores none and asks EHOS about none. A
credential whose `exp` is more than fifteen minutes away — EHOS's ten, and five for clocks that
disagree — is refused as `:bad_signature`, whoever signed it, so a key that leaked cannot mint a
credential that lives for a year; so is one whose header carries `crit`. `exp`
is measured by `EhOsContract.Clock`, so a test moves time with `EhOsContract.Clock.at/2`.
