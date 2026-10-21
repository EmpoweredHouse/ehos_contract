# EhOsContract.Auth

Verifies the credentials EHOS issues, for an application built on
[EhOsContract](https://github.com/EmpoweredHouse/eh-os-contract/tree/main/packages/eh_os_contract). It checks the signature locally, against keys it keeps in the
application's own database, so the application keeps accepting credentials while EHOS is
down, even after the application restarts.

The engine verifies nothing: it asks an `EhOsContract.Authorizer` what a credential's actor may
do, and this package is the implementation for EHOS's credentials. The engine does not depend on it.

Its parts: `EhOsContract.Auth.verify/2` and the key store behind it, `EhOsContract.Auth` as the
engine's `Authorizer` with a row for every decision, `EhOsContract.Auth.Plug` for a bearer token in
front of `EhOsContract.Plug`, `mix eh_os_contract.manifest` for EHOS's application manifest,
`EhOsContract.Auth.SignIn` for signing people in, `EhOsContract.Auth.People` for reading the
company's people, `EhOsContract.Auth.Grants` for a person granting a role their rule lets them give,
and `EhOsContract.Auth.Testing` for a host's tests.

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
  audience: "clinic/production"
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

EHOS deploys an image with its `ehos.manifest/v2`, `v3` for an `ehos.yaml/v3`, or `v4` for an
`ehos.yaml/v4` (which may name a seed and secrets): the application's `ehos.yaml`, which says what the workload needs, extended with what its contracts
offer. In CI, beside the image:

```bash
mix eh_os_contract.manifest --output ehos.manifest.json
# --ehos-yaml deploy/ehos.yaml when the file is not ehos.yaml in the project's directory
```

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

**A role that may grant another**: an actor's `may_grant:` in the domain,
`actor :office_employee, :human, "Office employee", may_grant: [:client]`, gives its role `may_grant`, the
roles a person holding it may grant through the application, and makes the manifest an `ehos.manifest/v5`,
whatever the version of `ehos.yaml`. A domain without a rule keeps its manifest's version and digests. An
actor a rule names, and one that has a rule, has to hold a capability, or it is no role and the task says so.

`contracts` is not written: EHOS counts it in the authority digest, and a contract's version moves
with any edit, so a new label would ask for `ehos.application.register` at every deploy. yamerl and JSV, which read and validate the file, are `runtime: false`: a release carries
neither.

## Configuration from EHOS's environment

EHOS starts the workload with its settings in the environment, and the package reads no
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

`EHOS_CLIENT_ID`, `EHOS_CLIENT_KEY_FILE`, `EHOS_SIGN_IN_APPLICATIONS` and
`EHOS_SIGN_IN_ABSOLUTE` are for signing people in to the application in a browser, through EHOS:
"Signing people in" below.

## Signing people in

A person signs in to the application's pages through EHOS, with OpenID Connect. The
application is EHOS's client, and `EhOsContract.Auth.SignIn` holds it:

```elixir
# config/runtime.exs, beside issuer: and audience:
config :eh_os_contract_auth,
  sign_in: [
    client_id: System.fetch_env!("EHOS_CLIENT_ID"),
    client_key_file: System.fetch_env!("EHOS_CLIENT_KEY_FILE"),
    address: "https://" <> System.fetch_env!("PHX_HOST"),
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    applications: Jason.decode!(System.get_env("EHOS_SIGN_IN_APPLICATIONS", "{}")),
    # How long a session lasts from the sign-in at EHOS, the installation's.
    absolute_limit: String.to_integer(System.get_env("EHOS_SIGN_IN_ABSOLUTE", "43200"))
  ]

# the supervision tree, after EhOsContract.Auth; cacertfile: as for it
children = [MyApp.Repo, EhOsContract, EhOsContract.Auth, EhOsContract.Auth.SignIn]
```

The child checks this at boot and refuses to start otherwise:

- the key file is one private Ed25519 JWK, exactly as EHOS's operator writes it, and a PEM is
  refused;
- `address`, and each address in `applications`, is `https://<host>` in lower case, with no port, no path and no
  trailing slash;
- no address in `applications` is `address`: they are the other applications;
- the issuer is `https://<host>[:port]` alone, as every parser reads it;
- `secret_key_base` has at least 64 bytes;
- `absolute_limit`, when given, is whole seconds from a minute to 366 days.

`absolute_limit` is how long a session lasts from the person's sign-in at EHOS, renewed or not:
twelve hours when not given or nil. EHOS gives the workload its installation's as
`EHOS_SIGN_IN_ABSOLUTE` and enforces the same at its own endpoints. Sign-in asks EHOS
for no older sign-in than `absolute_limit` (`max_age`), so an application that keeps a shorter
limit than its installation asks for the password sooner, never round and round EHOS. Its idle
limit, `EHOS_SIGN_IN_IDLE`, EHOS enforces alone: a refresh token unused that long is refused, and
the session ends at the next renewal.

The browser keeps the session's token in the host's `Plug.Session` cookie. Without `max_age`
there, the cookie ends when the browser closes, and the person signs in again then, however long
`absolute_limit` is: a host that wants the session to outlast the browser gives the cookie a
`max_age` at least as long, such as EHOS's ceiling of 366 days, since the session's row, not the
cookie, decides when it ends.

Nothing it raises carries a secret. The callback is `address <> "/auth/ehos/callback"`, and a sign-out returns
to `address <> "/"`. Both are derived, never configured, because EHOS compares them as exact strings.

The child keeps EHOS's discovery document and keys, refetched every 5 minutes. It starts while EHOS is
down, retrying after 1 second and doubling up to 30 seconds. Every call to EHOS:

- goes over https;
- follows no redirect;
- reads at most 64 KiB;
- ends after 10 seconds.

These limits match the ones on the key set. `EhOsContract.Auth.SignIn.provider/1` says whether a person can be
signed in with what is held. It refuses, naming each thing that fails, a document that lacks any of these:

- the `iss` parameter in authorization responses;
- PKCE with `S256`;
- `Ed25519` ID tokens;
- `private_key_jwt`.

It also refuses a document that names a symmetric algorithm or `none` for ID tokens. `oidcc` would quietly do
without each of these, or accept such a token. A document whose endpoints are not at the issuer's own origin,
or not read alike by every parser, is not held at all: nobody can sign in until EHOS serves one that is,
and the log says which endpoints it refused.

**Where a signed-in person is kept.** Version 3 of the package's tables holds them.
A host that migrated earlier versions adds one migration, as for every version:

```elixir
defmodule MyApp.Repo.Migrations.UpgradeEhOsContractAuthToV3 do
  use Ecto.Migration

  def up, do: EhOsContract.Auth.Migrations.up(version: 3)
  def down, do: EhOsContract.Auth.Migrations.down(version: 3)
end
```

- **The browser** holds a random token, and the table only its SHA-256.
- **EHOS's tokens** (the refresh token, the ID token and every credential) are stored encrypted. The key is
  derived from `secret_key_base`, and each ciphertext is bound to its row and column, so a backup, a replica or
  a dump holds nothing that can be presented.
- **Rotating `SECRET_KEY_BASE`** signs everybody out, as it already does through the cookie session.

**The routes and the session plug.**

```elixir
# endpoint.ex: the cookie session is encrypted, since oidcc_plug keeps the
# request's state, nonce and PKCE verifier in it between redirect and callback
plug Plug.Session, store: :cookie, key: "_my_app", signing_salt: "...", encryption_salt: "..."

# router.ex
scope "/" do
  pipe_through :browser            # fetches the session, protects from forgery
  forward "/auth/ehos", EhOsContract.Auth.SignIn.Router
end

pipeline :signed_in do
  plug EhOsContract.Auth.Session   # assign_actor: true for a pipeline to EhOsContract.Plug
end

# a controller; a LiveView passes the session map mount/3 is given
{:ok, actor} = EhOsContract.Auth.Session.actor(conn)

# another application the page calls as the person, by its name in applications:
{:ok, token} = EhOsContract.Auth.Session.credential(conn, "ledger")
Req.get!("https://ledger.production.ehos.localhost/visits", auth: {:bearer, token})
```

- **`GET /auth/ehos/sign-in?return_to=/visits/7`** sends the browser to EHOS, with PKCE and a nonce. While sign-in
  through EHOS is unavailable, it answers 503.
- **`GET /auth/ehos/callback`** is where EHOS returns. EHOS's `iss` is checked, and the code is exchanged with
  `private_key_jwt` only. Then:
  - the person gets a new session token, and the Plug session is renewed;
  - the browser goes back to `return_to` when it is a path of this application, and to `/` otherwise;
  - a callback that signs nobody in answers 401, and so does one whose credential `verify/2` refuses;
  - signing in again in a signed-in browser ends the session it had, and the Plug session starts empty.
- **`POST /auth/ehos/sign-out`**, behind CSRF protection, ends the session and sends the browser to EHOS's
  end-session endpoint with `id_token_hint`, and back to exactly `address <> "/"`.
- **`EhOsContract.Auth.Session`**, the plug, lets a signed-in person through, with
  `conn.assigns.eh_os_contract_session` (`subject`, `sid`, `auth_time`). Otherwise a browser's navigation is
  redirected to sign in and back, and any other request, a page's `fetch()` for one, answers 401. A credential
  refused for anything but its expiry answers 401 too, since signing in again would not help.
- **`Session.actor/2`** is the actor of the person's credential for this application, verified as a bearer
  credential is.

**Renewal.** A credential lives 10 minutes. When one is good for less than 30 seconds, `actor/2`, and the plug
with `assign_actor: true`, renew it through EHOS with the session's refresh token (`Oidcc.Token.refresh/3`).
Nothing renews unless a request asks.

- **One renewal per session.** However many requests of the session ask at once, one takes a lease on the
  session's row, by the database's clock, and renews. The others use the credential they hold while it is
  unexpired, and wait for the renewal, for at most 15 seconds, only when it has expired.
- **No transaction is open while EHOS is called.**
- **What a failure leaves.**
  - Sign-in over at EHOS: the session ends, and a page is sent to sign in.
  - EHOS down or slow: the held credential is used while it is unexpired. After that the request answers 503,
    the refresh token is kept, and the session does not call EHOS again for 5 seconds.
  - A response that cannot be used: the session ends, since EHOS has rotated the refresh token.

**Other applications.** `Session.credential/3` is the person's credential for an application named in
`applications:`, issued by EHOS for that application's address (`resource`) and renewed
like the application's own, under the same lease. It is handed out as EHOS issued it, not verified here: its
`aud` is that application's, which verifies it. Send it from the server and keep it there: a LiveView's assigns
or a page would hand it to the browser, which the session otherwise keeps EHOS's tokens from.

- **A name `applications:` does not have** raises `ArgumentError`.
- **A person EHOS refuses there** (no role, or not in the sign-in's granted set: `invalid_target`) gets
  `{:error, :refused}`. The refusal is remembered for 10 minutes, a credential's lifetime, so EHOS is not asked
  again on every page. The refresh token is kept, and the session goes on for this application and every other.
- **The other refusals** are `actor/2`'s: `:signed_out`, `:ehos_unavailable`, `:renewal_busy`.

Why signing in and the session work this way is recorded in [`docs/adr/browser-session.md`](https://github.com/EmpoweredHouse/eh-os-contract/blob/main/docs/adr/browser-session.md).

**A person's key is `sub`.** The `sub` of a signed-in person is their `id` in EHOS. It never
changes, and the people API below returns the same `id` for the same person. Store it, never the
email: an email can change and later be given to someone else.

## Reading the company's people

A form that lets someone pick an employee, instead of typing a name into a text field, reads EHOS's
people as the application itself. The application asks for it in its
`ehos.yaml/v3`. EHOS then gives its workload `EHOS_CLIENT_ID` and `EHOS_CLIENT_KEY_FILE`, whether
or not it signs people in. EHOS answers only after someone who manages people agrees, for that
environment.

```yaml
schema: ehos.yaml/v3
needs:
  people: read
```

```elixir
# config/runtime.exs, beside issuer:
config :eh_os_contract_auth,
  people: [
    client_id: System.fetch_env!("EHOS_CLIENT_ID"),
    client_key_file: System.fetch_env!("EHOS_CLIENT_KEY_FILE")
  ]

# the supervision tree; cacertfile: as for EhOsContract.Auth
children = [MyApp.Repo, EhOsContract, EhOsContract.Auth, EhOsContract.Auth.People]
```

```elixir
{:ok, %{people: people, next: next}} = EhOsContract.Auth.People.list(q: "ad", limit: 50)
{:ok, more} = EhOsContract.Auth.People.list(after: next)   # the cursor carries q: and limit:
{:ok, person} = EhOsContract.Auth.People.get(id)
# %EhOsContract.Auth.People.Person{id: "6f1c…", email: "ada@example.com", name: "Ada Lovelace", state: :joined}
```

The process takes its own credential at EHOS's token endpoint with the client credentials
grant, signed with the client key. It keeps the credential for its 10 minutes and takes another
before it expires. Callers that need one at the same time wait for a single request. After a
refusal or an outage, the process gives the same answer for 5 seconds without asking EHOS again.
Nothing is fetched at start, so the host starts while EHOS is down. `list/1` takes `q:`, `state:`
(`:invited`, `:joined`) and `limit:` (1 to 500), or `after:` alone. An option EHOS would refuse
raises `ArgumentError` before EHOS is asked. Store a person's `id`, and show the email beside the
name, since 2 people can share a name.

A call that returns no people says why, so the page can explain it in words:

| Error | When |
| --- | --- |
| `:not_agreed` | No people manager has agreed for this environment, or the agreement was withdrawn |
| `:not_found` | `get/2` of an id that is no one's |
| `:not_asked` | The deployment does not ask `needs.people: read` |
| `:rate_limited` | EHOS's limits: 60 credentials a minute, 600 calls a minute |
| `:unavailable` | EHOS cannot be reached, fails, or answers what it never answers |

The list is never copied into the application. While EHOS cannot answer, the call fails, the
page says so, and the rest of the application keeps working.

## A person granting a role

An accountant names a client's representative on the application's page, and the representative is
invited with the client role and nothing else. The rule is the contract's:
`may_grant: [:client]` on the accountant's actor, which the manifest carries to EHOS. EHOS checks it
against a role the accountant holds there, invites by mail and records the accountant and the
application. The application decides nothing: it passes on the person's own credential.

```elixir
# a controller of a signed-in page, after the application's own command is recorded
alias EhOsContract.Auth.Grants.Grant

case EhOsContract.Auth.Grants.grant(conn, email: email, name: name, role: "clinic.client") do
  {:ok, %Grant{person_id: id, delivery: :mailed}} -> # keep the id, to revoke later; "invited"
  {:ok, %Grant{bound: :before}} -> # they had the role already
  {:error, :beyond_rule} -> # "your role may not give that role"
  {:error, :unavailable} -> # "they were not invited; try again"
  {:error, reason} -> # the module's doc lists each
end

{:ok, %{role_binding_id: _id}} = EhOsContract.Auth.Grants.revoke(conn, id, "clinic.client")
```

Each call exchanges the person's credential for this application, from their session, for a minute's
credential to EHOS (RFC 8693), authenticated as the sign-in's client: nothing more is configured than
signing in needs. It is made in the person's request, keeps no credential and retries nothing; when it
fails the page says so and the person asks again, which is safe. `docs/grants-api.md` in eh-os is the
API it calls.

## Deciding, and recording every decision

`EhOsContract.Auth` is the `EhOsContract.Authorizer` the engine asks about every command and query
that arrives with a credential. It decides with `EhOsContract.Authorizer.check/2` alone (the
capability in `cap`, a scoped value among the values in `scp`) and writes 1 row to
`eh_os_contract_auth_decisions` for every decision, a refusal as carefully as an acceptance: who, which capability, which contract and version, the scope value asked for, `allowed` or
`refused`, and the reason. A scope value the table cannot hold (invalid UTF-8, a NUL), one past 256
bytes, or one that starts `sha256:` is recorded as `sha256:` and its hex digest, so a crafted value is
refused like any other instead of failing the request.

The row records the authorization, not the command. A command allowed here may still be rejected on
an invariant, and that is the engine's row in `eh_os_contract_commands`: two facts, two rows. The row
goes through the connection the call is on, so a caller that wraps `EhOsContract.dispatch/3` in a
transaction of its own and rolls it back rolls the row back too. A row that cannot be written fails
the call.

**What it costs.** Every command and query that arrives with a credential writes that row: one
`INSERT`, committed on its own before the engine's transaction starts, and for a query the only write
the call makes. A refusal is recorded as carefully as an acceptance, and a refusal cannot be written
inside a transaction that never starts. Budget for one extra write per
call; the table carries no index beyond `decided_at` and `(subject, decided_at)`.

**How long rows are kept is the application's decision.** Nothing here deletes them. The index on
`decided_at` makes a periodic cleanup cheap, for instance from a job:

```elixir
MyApp.Repo.query!("DELETE FROM eh_os_contract_auth_decisions WHERE decided_at < now() - interval '400 days'")
```

A common choice is to keep them as long as the application keeps its own log.

## Over HTTP

```elixir
pipeline :commands do
  plug :accepts, ["json"]
  plug EhOsContract.Auth.Plug
end

scope "/api" do
  pipe_through :commands
  forward "/", EhOsContract.Plug, contracts: [Clinic.Contracts.VisitSettlement]
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

## The credential

A JWT, `alg: "Ed25519"` and nothing else, with `iss`, `sub`, `aud` (one string), `iat`, `exp`,
`jti`, `cap` (the capabilities, sorted), and `scp` when a capability is scoped:

```json
{"sub": "u-81", "aud": "clinic/production", "cap": ["clinic.open_visits_for_clinic"],
 "scp": {"clinic.open_visits_for_clinic": {"clinic_id": ["7"]}}}
```

The grants travel in the credential. The application stores none and asks EHOS about none. A
credential whose `exp` is more than 15 minutes away (EHOS's 10, and 5 for clocks that
disagree) is refused as `:bad_signature`, whoever signed it, so a key that leaked cannot mint a
credential that lives for a year; so is one whose header carries `crit`. `exp`
is measured by `EhOsContract.Clock`, so a test moves time with `EhOsContract.Clock.at/2`.

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
