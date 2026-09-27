# EhOsContract.Auth

Verifies the credentials EHOS issues, for an application built on
[EhOsContract](../eh_os_contract). It checks the signature locally, against keys it keeps in the
application's own database, so the application goes on accepting credentials while EHOS is
down, and after a restart while EHOS is down.

The engine verifies nothing: it asks an `EhOsContract.Authorizer` what a credential's actor may
do, and this package is the implementation for EHOS's credentials (contract v2 §16, D14; `eh-os`
D-33, D-34). The engine does not depend on it.

> **State, 27 September 2026:** verification and the key store (stage EA1). The `Authorizer`
> with its record of every decision, the bearer plug and the test helper follow in EA2.

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

Do not turn certificate verification off to make a first integration work: the keys would then come
from whoever answers. For the same reason the package refuses to boot when the key set would be
fetched over anything but `https` (plain `http` is allowed for `localhost` only), and **follows no
redirect**: a key set answered from anywhere but the configured URL is a failed fetch.

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
