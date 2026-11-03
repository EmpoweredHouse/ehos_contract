# EhOsContract.Auth

This package connects an application built on
[`eh_os_contract`](https://github.com/EmpoweredHouse/eh-os-contract/tree/main/packages/eh_os_contract)
to EHOS, the platform that hosts it. This page is for a developer who connects such an application.
It says what the package does, and links to the pages that tell you how to use it.

## What does the package do?

People and systems call the application with a *credential*: a signed token that EHOS issues. The
engine verifies no credential. It asks an *Authorizer* what the actor of a credential can do. This
package is that Authorizer for the credentials of EHOS. The engine does not depend on it.

The package verifies each credential in the application, against the public keys of EHOS. It keeps
the keys in the database of the application. After one fetch succeeds, the application accepts
credentials while EHOS is down, also after a restart. The package then writes a row for each
decision, a refusal too.

The [glossary of the engine](https://github.com/EmpoweredHouse/eh-os-contract/blob/main/packages/eh_os_contract/docs/glossary.md)
defines each word of the contract language that these pages use. The words of the platform, such as
*installation* and *environment*, are the words of EHOS.

## What are its parts?

| Part | What it does |
| --- | --- |
| `EhOsContract.Auth.verify/2`, with the key process `EhOsContract.Auth.Keys` | verifies a credential and gives its actor |
| `EhOsContract.Auth` | the Authorizer of the engine, with a row for each decision |
| `EhOsContract.Auth.Plug` | verifies the bearer token of a request in front of `EhOsContract.Plug` |
| `mix eh_os_contract.manifest` | writes the application manifest that EHOS deploys from |
| `EhOsContract.Auth.SignIn`, `EhOsContract.Auth.Session` | signs people in to the pages of the application through EHOS, and keeps their sessions |
| `EhOsContract.Auth.Workload` | holds the credential of the application itself, for the people and for mail |
| `EhOsContract.Auth.People` | reads the people of the company |
| `EhOsContract.Auth.Mail` | sends mail through EHOS |
| `EhOsContract.Auth.Grants` | lets a person grant a role that their rule lets them give |
| `EhOsContract.Auth.Egress` | sends a call to a host outside the installation through the proxy that EHOS gives |
| `EhOsContract.Auth.Testing` | gives credentials and stand-ins to the tests of the application |

## Next steps

- [Get started](docs/getting-started.md): install the package, configure it, and accept a call with
  a credential.
- [The credential](docs/credential.md): what a credential holds, and when `verify/2` and the plug
  refuse it.
- [How is each decision recorded?](docs/decisions.md): the row for each decision, what it costs, and
  how long to keep it.
- [Sign people in through EHOS](docs/sign-in.md): the pages of the application, with a session for
  each person, and how to protect them from forgery.
- [Call another application as the person](docs/call-another-application.md): the credential of the
  person for another application of the installation.
- [Read the people of the company](docs/people.md): a list of employees for a form.
- [Send mail](docs/mail.md): mail from the application, through EHOS.
- [Let a person grant a role](docs/grants.md): invite a person with a role from a page.
- [Call a host outside the installation](docs/egress.md): the proxy that EHOS gives.
- [Use people, grants and mail where EHOS does not answer](docs/without-ehos.md): the stand-ins for
  development and tests.

## The sections that follow are moving

The sections below move to pages of their own in `docs/`. Until then, they stay here as they are.

## Generating the EHOS application manifest

EHOS deploys an image with its `ehos.manifest/v2`, `v3` for an `ehos.yaml/v3`, `v4` for an
`ehos.yaml/v4` (which may name a seed and secrets), `v5` when a role may grant another, `v6` for
an `ehos.yaml/v5` (which may name the hosts outside the installation it reaches), `v7` for an
`ehos.yaml/v6` (which may ask to send mail through EHOS), or `v8` for an `ehos.yaml/v7` (which may
ask for CPU and memory): the application's
`ehos.yaml`, which says what the workload needs, extended with what its contracts offer. In CI,
beside the image:

```bash
mix eh_os_contract.manifest --output ehos.manifest.json
# --ehos-yaml deploy/ehos.yaml when the file is not ehos.yaml in the project's directory
```

Or the whole bundle EHOS takes with the image: the same manifest, every graph
document as `mix eh_os_contract.graph --output-dir` writes them, and `bundle.json`, which names
each file with its size and SHA-256, into an empty directory:

```bash
mix eh_os_contract.bundle --output-dir bundle
```

The index is checked against EHOS's own schema of `ehos.bundle/v1`, carried unchanged, and the
rules EHOS keeps beside it, and a bundle EHOS would refuse is not written.

`ehos.yaml` is EHOS's format alone, and the task reads it as
EHOS reads it: YAML 1.2's core schema, no anchor, alias, tag or repeated key, validated against
EHOS's own JSON Schema, which this package carries unchanged. A file EHOS's reader or schema would
refuse is refused here, with every reason, its path, and its line when it is known, and no manifest
is written. The
rules EHOS checks beside its schema (names and ports unique in `serves`, the health port not among
them, each name once in `needs.secrets`) are not repeated: EHOS refuses those when the manifest is
deployed. The 2 rules for `sign_in` (below) are checked here, once the schema has passed, because adding
`sign_in` alone breaks them.

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
- `offers`, the capabilities of the commands, queries and recordings a human actor may make, each naming its
  declaration as `command`, `query` or `record`, and the human actors that hold at least one of
  them, as roles. An EHOS too old to know these kinds refuses a manifest that offers a query or a recording. System actors,
  actors who hold nothing, scopes and publications are absent: the manifest has no field for them yet, and
  EHOS refuses a field it does not know;
- `engine`, the `eh_os_contract` version that wrote it.

**An application that signs people in through EHOS** writes `ehos.yaml/v2`, which is v1 and one more
key, `sign_in`. Its presence is what makes EHOS give the workload its client
(`EHOS_CLIENT_ID`, `EHOS_CLIENT_KEY_FILE`), and the manifest carries it as written, `{}`
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
of `ehos.yaml` as written, a `migrate` or `seed` argument too; what the workload needs at run time
comes from its environment, below.

**Secrets and a seed, from `ehos.yaml/v4`**, which makes an `ehos.manifest/v4`:

```yaml
schema: ehos.yaml/v4
needs:
  database:
    engine: postgres
    migrate: ["/app/bin/migrate"]
    # Run after the migration in an ephemeral environment only, never in production; idempotent.
    seed: ["/app/bin/seed"]
  secrets:
    - name: smtp_password
    - name: gus_api_key
      version: 2
```

`needs.secrets` names secrets and holds no value: people set each value in EHOS, per environment or
as a template's default for its ephemeral environments, and EHOS refuses a deployment while one it
names has none there. The workload is given each as an environment variable named after it in
upper case (`smtp_password` becomes `SMTP_PASSWORD`), which `config/runtime.exs` reads like any
other. Without `version`, the newest value, and setting a new one rolls the workload; with it, that
version through every setting. A name EHOS gives every workload or the runtime reads (`ehos_*`,
`database_*`, `phx_*`, `secret_key_base`, `path` and the like) is refused.

**Hosts outside the installation, from `ehos.yaml/v5`**, which makes an `ehos.manifest/v6`:

```yaml
schema: ehos.yaml/v5
needs:
  egress:
    - host: registry.example.org      # port 443 when left out
    - host: mail.example.net
      port: 587
```

Each host is a DNS name in lowercase, never an address or a pattern such as `*.example.org`, and the manifest
carries the list as written: a port left out stays left out. The hosts are part of the application's authority in
EHOS: a deployment that adds, removes or changes one asks for `ehos.application.register`, as a new role does.
EHOS also refuses, at deploy, a host under a name only a network inside answers, such as `*.svc.cluster.local`,
and a host and port named twice, which this task leaves to it.

**Mail sent through EHOS, from `ehos.yaml/v6`**, which makes an `ehos.manifest/v7`:

```yaml
schema: ehos.yaml/v6
needs:
  mail:
    level: internal                     # or external, to any address as well
    reply_domains: [reply.office.example.org]
```

The manifest carries `needs.mail` as written. Each reply domain is a DNS name in lowercase, never an
address or a pattern; EHOS also refuses, at deploy, a domain named twice and one only a network inside
answers, such as `*.svc.cluster.local`, which this task leaves to it. Asking grants nothing: EHOS sends
only once someone agrees, per environment, and [Send mail](docs/mail.md) says how the application
sends.

**The CPU and memory the workload asks for, from `ehos.yaml/v7`**, which makes an `ehos.manifest/v8`:

```yaml
schema: ehos.yaml/v7
needs:
  compute:
    cpu: 500m                           # a request; EHOS sets no CPU limit
    memory: 1Gi                         # the request, and the most each container may use
```

The manifest carries `needs.compute` as written, `1Gi` stays `1Gi`. EHOS gives the values to the serving
container, the migration and the seed, and a key left out takes the environment's default. It is no part of the
application's authority: changing it asks only for the right to deploy. EHOS also refuses, at deploy, a memory
below 16Mi and a deployment that does not fit its environment's quota, which this task leaves to it.

**A role that may grant another**: an actor's `may_grant:` in the domain,
`actor :office_employee, :human, "Office employee", may_grant: [:client]`, gives its role `may_grant`, the
roles a person holding it may grant through the application, and makes the manifest an `ehos.manifest/v5`,
whatever the version of `ehos.yaml` before v5; an `ehos.yaml/v5` makes an `ehos.manifest/v6`, an
`ehos.yaml/v6` an `ehos.manifest/v7`, and an `ehos.yaml/v7` an `ehos.manifest/v8`, rule or none. A
domain without a rule keeps its manifest's version and digests. An actor a rule names, and one that has a
rule, has to hold a capability, or it is no role and the task says so.

`contracts` is not written: EHOS counts it in the authority digest, and a contract's version moves
with any edit, so a new label would ask for `ehos.application.register` at every deploy. yamerl and JSV, which read and validate the file, are `runtime: false`: a release carries
neither.

## Configuration from EHOS's environment

EHOS starts the workload with its settings in the environment, and the package reads none of
them itself, but for the proxy of [Call a host outside the installation](docs/egress.md), which it
reads at each call. `config/runtime.exs` and the
supervision tree map them:

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

`EHOS_SIGN_IN_APPLICATIONS` and `EHOS_SIGN_IN_ABSOLUTE` are for signing people in to the
application in a browser, through EHOS: [Sign people in through EHOS](docs/sign-in.md). EHOS also
gives `EHOS_CLIENT_ID` and `EHOS_CLIENT_KEY_FILE` to an application that only reads the people or
sends mail. Only `EHOS_SIGN_IN_APPLICATIONS` tells that the application signs people in. Such an
application maps them to `workload:`: [Read the people of the company](docs/people.md).

## In a host's tests

```elixir
use EhOsContract.Auth.Testing

test "every entry point refuses a credential without the capability" do
  assert_every_entry_refuses([Clinic.Contracts.VisitSettlement], %{
    "clinic.record_payment" => fn token -> post_command(token, "clinic.record_payment", ...) end,
    # ... one entry per capability the contracts declare
  })
end

token = credential("u-anna", ["clinic.record_payment"])
```

The engine cannot call a host's entry points itself, so the host maps every capability its contracts declare to a
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

A page behind `EhOsContract.Auth.Session` is tested with a browser signed in without EHOS:

```elixir
token = sign_in("u-anna", ["clinic.record_payment"])

conn =
  build_conn()
  |> Plug.Test.init_test_session(%{EhOsContract.Auth.Session.session_key() => token})
  |> get("/visits/7")

:ok = sign_out(token)
```

`sign_in/3` writes the session row a sign-in through EHOS writes, with a credential `credential/3`
issued. The session plug lets the request through, and `EhOsContract.Auth.Session.actor/2` answers
that credential's actor; after `sign_out/1` the browser is signed out. When no
`EhOsContract.Auth.SignIn` child runs, a stand-in that never calls EHOS takes its name for the rest
of the run, so the test configuration needs no `sign_in:`, and a test that starts a child of its own
names it and passes `sign_in: name`. The stand-in cannot renew: a test that moves
`EhOsContract.Clock` past the credential's ten minutes, or asks `Session.credential/3` for another
application, gets `:ehos_unavailable`, and the plug answers 503.

With the three stand-ins configured, a test says whom EHOS knows and what it answers, and sees the
mail the application asked to send:

```elixir
stub_people([%{id: "6f1c0a1e-0000-4000-8000-000000000001", email: "ada@example.com", name: "Ada"}])
stub_people({:error, :not_agreed})
stub_grants({:error, :beyond_rule})
stub_mail({:error, :not_agreed})

assert_received {:ehos_mail, message}
assert message[:to] == [{:person, "6f1c0a1e-0000-4000-8000-000000000001"}]
```

What a test says holds for it and the processes it starts, a LiveView's included, and for no other
test, so tests stay `async: true`. A host on Mox or Hammox can `defmock` the three behaviours instead
and `stub_with/2` them with `Static`, `Grants.Local` and `Mail.Local`. The callbacks are typed with
`People`'s, `Grants`' and `Mail`'s own types, so a Hammox mock refuses an answer EHOS never gives, such as
`{:error, :timeout}`; this package's tests hold every implementation it ships to those types.

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

`cacerts:` takes the certificates themselves (DER) instead of a file. Those are the only fetch
options the package accepts. It does not take Req's options: the fetch **follows no redirect**, is not
retried, reads at most 64 KB, and waits 2 seconds to connect and 3 for each part of the
answer, and Req has options that would undo each of these, or the check of the certificate. An
option the package does not take fails the boot. A proxy or a client certificate is not supported.

However long each part takes, a fetch that has not finished in 5 seconds is abandoned as a failed
one, and the keys in force stay.

Req still merges an application's own `config :req, default_options` into this request, under the
package's options: what the package sets (the connection with its authority, the timeouts,
retries and redirects) replaces the application's, and the rest reaches the fetch. A global
`plug:` or `adapter:` replaces the network here too, `auth:` or `headers:` are sent to EHOS, and
`finch:` makes every fetch fail, since the package always sets the connection. Keep those out of
the global defaults.

Certificate verification cannot be turned off through the package, so a first integration cannot
be made to work that way: the keys would then come from whoever answers. For the same reason the package refuses to boot
when the key set would be fetched over anything but `https` (plain `http` is allowed for
`localhost`, `127.0.0.1` and `::1` only), whether `EhOsContract.Auth` starts the key process or the
application lists `EhOsContract.Auth.Keys` itself, and takes the address only from the configuration.
The address, `issuer` and sign-in's addresses must also be ones every parser reads alike, as EHOS
requires of its issuer: each reads back as written, with a lowercase host and no user, query or
fragment, and `issuer` has no path. Otherwise `http://evil.example\@localhost` would pass as
`localhost`, while EHOS and a browser read its host as `evil.example`. `issuer` is checked at boot even
beside `jwks_url`, since each credential's `iss` must equal it.

**What the application configures, and nothing else:** `issuer`, which must be exactly the `iss`
EHOS writes, `audience` (`<application>/<environment>`, exactly the `aud` EHOS issues for this
application), `jwks_url` only if the JWKS is not at the issuer's well-known path, and the authority
above if it is not a public one.

**The application in `audience` is a domain's name.** Every name the application publishes, and
every contract id it stores, begins with its domain's `name:`, and EHOS lets an application publish
only under the name it registered. So `audience` must be `<application>/<environment>` with both
parts present. Its application part must equal exactly the `name:` of one domain with contracts:
`audience: "my-shop/prod"` for `name: :"my-shop"`. A domain named `:my_shop` does not match, since
EHOS never names an application with `_`, and the manifest generator refuses it too. Any other
domain with contracts in the same application must declare no `publish`, since it would publish
under a name that is not the application's. Otherwise `EhOsContract.Auth` refuses to start, naming
what it found and how to fix it.

**Rotation** is manual in v1 and happens on EHOS's side:

1. `current` moves to `previous`, and a new `current` is added;
2. EHOS is rolled out. It signs with the new key, and the JWKS publishes both;
3. after 1 credential lifetime, 10 minutes, `previous` is removed.

The application does nothing. A credential signed with the new key names a `kid` it has not seen,
which triggers an early fetch, and the refresh every 5 minutes drops `previous` once the JWKS no
longer has it.

**How the key store behaves** (`EhOsContract.Auth.Keys`):

- at start it loads the last good key set from its table, then fetches the JWKS;
- it fetches again every 5 minutes, so a key removed from the JWKS, a compromised one for
  instance, stops being trusted within that interval without a restart;
- an unknown `kid` triggers an early fetch, at most once every 30 seconds;
- a failed fetch changes nothing: it is logged and the last good set stays in force. A key set with
  no Ed25519 key in it counts as a failed fetch, and so does a redirect, a body over 64 KB and more
  than 16 keys (a rotation holds 2);
- a successful fetch puts the keys in force first, then writes the table, and a table locked by a
  migration or `VACUUM FULL` is not waited for longer than a second: the write is logged as failed,
  and the next fetch writes it again;
- an application that has never seen a key set refuses every credential with `:no_keys`, and logs
  it at start. This is the one case where "EHOS is down" becomes "nobody gets in", and
  `EhOsContract.Auth.ready?/0` answers `false` for it, for the host's health check.

Tests need neither EHOS nor a network: the package's own suite plays the JWKS endpoint with a
function plug handed to Req.

<!-- Decisions behind this page:
contract v2 §16, D14 (docs/adr/contract-v2.md): the contract declares who may act; a separate package, this one, verifies who is acting.
EHOS's decisions this package follows:
- the credential, a ten-minute Ed25519 JWT with the key's thumbprint as kid; manual key rotation;
- keys kept in the application's own table; every decision recorded, a refusal as carefully as an acceptance;
- the claims cap and scp, scope values carried in the credential;
- ehos.yaml is EHOS's format, versioned by JSON Schema;
- ehos.manifest/v2, ehos.yaml extended with what the contracts offer;
- EHOS hands the workload its settings in the environment;
- signing a person in through EHOS with OpenID Connect; the callback address;
- the client key as a JWK, addresses as exact strings, an application's address as resource;
- sign_in in ehos.yaml/v2, and applications naming only the others;
- a capability names its declaration's kind, command, query or record;
- contracts left out of the manifest, so an edit does not ask for registration.
S2 (docs/adr/browser-session.md): the browser holds a random token, the row its SHA-256; the cookie session encrypted.
S3 (docs/adr/browser-session.md): EHOS's tokens encrypted, each bound to its row and column.
#89: the issuer and every address read alike by every parser.
-->
