# EhOsContract.Auth

Verifies the credentials EHOS issues, for an application built on
[EhOsContract](../eh_os_contract). It checks the signature locally, against keys it keeps in the
application's own database, so the application goes on accepting credentials while EHOS is
down, and after a restart while EHOS is down.

The engine verifies nothing: it asks an `EhOsContract.Authorizer` what a credential's actor may
do, and this package is the implementation for EHOS's credentials (contract v2 §16, D14; `eh-os`
D-33, D-34). The engine does not depend on it.

Five parts: `EhOsContract.Auth.verify/2` and the key store behind it, `EhOsContract.Auth` as the
engine's `Authorizer` with a row for every decision, `EhOsContract.Auth.Plug` for a bearer token in
front of `EhOsContract.Plug`, `mix eh_os_contract.manifest` for EHOS's application manifest, and
`EhOsContract.Auth.Testing` for a host's tests.

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

It needs OTP 27 or later, which `oidcc`, the OpenID Connect client behind signing people in, requires.

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

## Generating the EHOS application manifest

EHOS deploys an image with its `ehos.manifest/v2` (`eh-os` D-52): the application's `ehos.yaml`, which
says what the workload needs, extended with what its contracts offer. In CI, beside the image:

```bash
mix eh_os_contract.manifest --output ehos.manifest.json
# --ehos-yaml deploy/ehos.yaml when the file is not ehos.yaml in the project's directory
```

`ehos.yaml` is EHOS's format alone (`eh-os` D-51, `docs/ehos-yaml.md` there), and the task reads it as
EHOS reads it: YAML 1.2's core schema, no anchor, alias, tag or repeated key, validated against
EHOS's own JSON Schema, which this package carries unchanged. A file EHOS's reader or schema would
refuse is refused here, with every reason, its path, and its line when it is known, and no manifest
is written. The
rules EHOS checks beside its schema — names and ports unique in `serves`, the health port not among
them — are not repeated: EHOS refuses those when the manifest is deployed. The two of `sign_in` are
checked here, since adding `sign_in` alone breaks them (below), once the schema has passed.

```yaml
schema: ehos.yaml/v1
needs:
  database:
    engine: postgres
    version: ">= 16"
    migrate: [/app/bin/migrate]
serves:
  - name: web
    port: 4000
    public: true
health:
  port: 4001
  ready: /health/ready
  live: /health/live
```

Every key of it but `schema` is in the manifest at the same path with the same value, and no default
is filled in. The task adds:

- `application`, the contracts' domain's `name:`. A project with more than one domain with contracts
  names the one the image is in `ehos.yaml`, as `application: <name>`. EHOS takes lowercase letters,
  digits and dashes, so a domain named with `_` is refused, with a name to use when there is one EHOS
  takes;
- `offers`, the human command capabilities and the human actors that hold at least one of them, as
  roles. System actors, actors with no command, queries, recordings, scopes and publications are
  absent: the manifest has no field for them yet, and EHOS refuses a field it does not know;
- `engine`, the `eh_os_contract` version that wrote it.

**An application that signs people in through EHOS** writes `ehos.yaml/v2`, which is v1 and one more
key, `sign_in` (`eh-os` D-69). Its presence is what makes EHOS give the workload its client
(`EHOS_CLIENT_ID`, `EHOS_CLIENT_KEY_FILE`, D-68), and the manifest carries it as written, `{}`
included:

```yaml
schema: ehos.yaml/v2
serves:
  - name: web
    port: 4000
    public: true       # sign-in returns here, so sign_in needs it
sign_in: {}            # this application only; or applications: [billing] for others its pages call
health:
  port: 4001
  ready: /health/ready
  live: /health/live
```

`sign_in` is refused without an entry `web` that is `public: true`, and its `applications` are
other applications, each once, never this one: neither the `application` the file names nor the
domain's name the task finds.

**`ehos.yaml` must hold no secret.** EHOS keeps every manifest it is given, for good, with every key
of `ehos.yaml` as written, a `migrate` argument too; what the workload needs at run time comes from
its environment, below.

`contracts` is not written: EHOS counts it in the authority digest, and a contract's version moves
with any edit, so a new label would ask for `ehos.application.register` at every deploy (`eh-os`
issue #92). yamerl and JSV, which read and validate the file, are `runtime: false`: a release carries
neither.

## Configuration from EHOS's environment

EHOS starts the workload with its settings in the environment (`eh-os` D-56), and the package reads no
variable itself. `config/runtime.exs` and the supervision tree map them:

```elixir
# config/runtime.exs
if config_env() == :prod do
  config :eh_os_contract_auth,
    # EHOS's public address, the issuer its credentials carry.
    issuer: System.fetch_env!("EHOS_ISSUER"),
    # <application>/<environment>, the audience of the credentials the application accepts.
    audience: System.fetch_env!("EHOS_AUDIENCE")
end

# the supervision tree: EHOS_CA_FILE is set when the installation's authority is its own.
auth = if ca = System.get_env("EHOS_CA_FILE"), do: [cacertfile: ca], else: []
children = [MyApp.Repo, EhOsContract, {EhOsContract.Auth, auth}]
```

`EHOS_CLIENT_ID`, `EHOS_CLIENT_KEY_FILE` and `EHOS_SIGN_IN_APPLICATIONS` (`eh-os` D-64, D-68) are for
signing people in to the application in a browser, through EHOS: "Signing people in" below.

## Signing people in

A person signs in to the application's pages through EHOS, with OpenID Connect (`eh-os` D-64). The
application is EHOS's client, and `EhOsContract.Auth.SignIn` holds it:

```elixir
# config/runtime.exs, beside issuer: and audience:
config :eh_os_contract_auth,
  sign_in: [
    client_id: System.fetch_env!("EHOS_CLIENT_ID"),
    client_key_file: System.fetch_env!("EHOS_CLIENT_KEY_FILE"),
    address: "https://" <> System.fetch_env!("PHX_HOST"),
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    applications: Jason.decode!(System.get_env("EHOS_SIGN_IN_APPLICATIONS", "{}"))
  ]

# the supervision tree, after EhOsContract.Auth; cacertfile: as for it
children = [MyApp.Repo, EhOsContract, EhOsContract.Auth, EhOsContract.Auth.SignIn]
```

The child checks this at boot and refuses to start otherwise:

- the key file is one private Ed25519 JWK, exactly as `eh-os` D-68 says the operator writes it, and a PEM is
  refused;
- `address`, and each address in `applications`, is `https://<host>` in lower case, with no port, no path and no
  trailing slash;
- the issuer is https;
- `secret_key_base` has at least 64 bytes.

Nothing it raises carries a secret. The callback is `address <> "/auth/ehos/callback"`, and a sign-out returns
to `address <> "/"`. Both are derived, never configured, because EHOS compares them as exact strings.

The child keeps EHOS's discovery document and keys, refetched every five minutes. It starts while EHOS is
down, retrying after one second and doubling up to thirty. Every call to EHOS:

- goes over https;
- follows no redirect;
- reads at most 64 KiB;
- ends after ten seconds.

These limits match the ones on the key set. `EhOsContract.Auth.SignIn.provider/1` says whether a person can be
signed in with what is held. It refuses, naming each thing that fails, a document that lacks any of these:

- the `iss` parameter in authorization responses;
- PKCE with `S256`;
- `Ed25519` ID tokens;
- `private_key_jwt`.

It also refuses a document that names a symmetric algorithm or `none` for ID tokens. `oidcc` would quietly do
without each of these, or accept such a token.

**Where a signed-in person is kept.** Version 3 of the package's tables holds them (`eh-os` D-64, S2 and S3).
A host that migrated earlier versions adds one migration, as for every version:

```elixir
defmodule MyApp.Repo.Migrations.UpgradeEhOsContractAuthToV3 do
  use Ecto.Migration

  def up, do: EhOsContract.Auth.Migrations.up(version: 3)
  def down, do: EhOsContract.Auth.Migrations.down(version: 3)
end
```

- **The browser** holds a random token, and the table only its SHA-256.
- **EHOS's tokens** — the refresh token, the ID token and every credential — are stored encrypted. The key is
  derived from `secret_key_base`, and each ciphertext is bound to its row and column, so a backup, a replica or
  a dump holds nothing that can be presented.
- **Rotating `SECRET_KEY_BASE`** signs everybody out, as it already does through the cookie session.

The routes that sign a browser in and out, and the plug that reads the session, are the next part of this work
([#78](https://github.com/EmpoweredHouse/eh-os-contract/issues/78)). What the package decides beside D-64 is in
[`docs/adr/browser-session.md`](../../docs/adr/browser-session.md).

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
system's certificate authorities. An EHOS behind an internal authority needs that authority named:

```elixir
children = [
  MyApp.Repo,
  EhOsContract,
  {EhOsContract.Auth, cacertfile: "/etc/ehos/ca.pem"}
]
```

`cacerts:` takes the certificates themselves (DER) instead of a file. That is all the package
takes about the fetch. It does not take Req's options: the fetch **follows no redirect**, is not
retried, reads at most 64 KB, and waits two seconds to connect and three for each part of the
answer, and Req has options that would undo each of these, or the check of the certificate. An
option the package does not take fails the boot. A proxy or a client certificate is not supported.

However long each part takes, a fetch that has not finished in five seconds is abandoned as a failed
one, and the keys in force stay.

Req still merges an application's own `config :req, default_options` into this request, under the
package's options: what the package sets — the connection with its authority, the timeouts,
retries and redirects — replaces the application's, and the rest reaches the fetch. A global
`plug:` or `adapter:` replaces the network here too, `auth:` or `headers:` are sent to EHOS, and
`finch:` makes every fetch fail, since the package always sets the connection. Keep those out of
the global defaults.

Certificate verification cannot be turned off through the package, so a first integration cannot
be made to work that way: the keys would then come from whoever answers. For the same reason the package refuses to boot
when the key set would be fetched over anything but `https` (plain `http` is allowed for
`localhost` only), whether `EhOsContract.Auth` starts the key process or the application lists
`EhOsContract.Auth.Keys` itself, and takes the address only from the configuration.

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
- a successful fetch puts the keys in force first, then writes the table, and a table locked by a
  migration or `VACUUM FULL` is not waited for longer than a second: the write is logged as failed,
  and the next fetch writes it again;
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
