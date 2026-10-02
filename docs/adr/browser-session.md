# A browser session in `eh_os_contract_auth` — what the package decides beside D-64

> **Status: proposed**, 2 October 2026. Becomes *accepted* when the product owner says so. Where the code
> proves part of it wrong, that part is corrected in place, with a date.
>
> Follows `eh-os` [D-64](https://github.com/EmpoweredHouse/eh-os/blob/main/docs/adr/0064-people-sign-in-to-applications-through-ehos-with-oidc.md)
> and [D-66](https://github.com/EmpoweredHouse/eh-os/blob/main/docs/adr/0066-pkce-stays-required-and-the-conformance-gate-runs-the-basic-modules-with-private-key-jwt.md)
> (both accepted, 1 October 2026). Those records decide the protocol: the code flow with PKCE and `iss`,
> `private_key_jwt`, one credential per application named by `resource`, strict refresh rotation, renewal on
> demand under a lease, and RP-initiated logout. This file does not restate them. It records what they leave
> to the relying party, which is this package. The work is
> [eh-os-contract#78](https://github.com/EmpoweredHouse/eh-os-contract/issues/78), Stage 9's step 6 in `eh-os`.

## The problem

`eh_os_contract_auth` verifies a bearer credential. An application's pages have no bearer credential: a
person signs in through EHOS in a browser, and the pages need a credential behind that session, renewed
every ten minutes while the person works, for this application and for any other the pages call.

D-64 fixes the protocol and names the libraries, `oidcc` and `oidcc_plug`. It leaves to the package:

- what the browser holds;
- what the table holds;
- how one renewal per session is enforced;
- what each refusal leaves;
- which defaults of `oidcc` it overrides;
- the interface a host wires.

Reading `oidcc` 3.9.0 and `oidcc_plug` 0.5.1 against EHOS's `main` (2 October 2026) also found two things:

- **`oidcc` degrades silently.** If the discovery document does not say so, it skips the `iss` check, drops
  PKCE, and moves from `private_key_jwt` to another client authentication.
- **Renewal fails against EHOS as built.** `oidcc` refuses a refresh response without an ID token, and EHOS
  sends none.

## Drivers

1. **The refresh token never reaches the browser** (D-64).
2. **A refresh token is presented once.** EHOS rotates with no grace window, and a token presented twice
   revokes the sign-in. Every rule about concurrency, timeouts and failures follows from this one.
3. **No database transaction is open while EHOS is called** (D-64). A slow EHOS must not hold a connection
   or a lock.
4. **EHOS down is not the application down** (FM-19). A credential already held is used until it expires,
   and the application starts without EHOS.
5. **Security properties are explicit, not inherited from defaults.** A check `oidcc` would skip on a
   discovery document's silence is enforced in this package's own options.
6. **The engine does not change** (D-64). It gets the same `EhOsContract.Actor`, from the same
   `EhOsContract.Auth.verify/2`, that the bearer Plug gives it.
7. **The host writes no sign-in code.** It wires a child, a route and a plug, as D-64's "an application
   gets sign-in from a library and the template" asks.

## Decisions

### S1 — It lives in `eh_os_contract_auth`, with `oidcc` and `oidcc_plug` as plain dependencies

`{:oidcc, "~> 3.9"}` and `{:oidcc_plug, "~> 0.5.1"}` are added to the package's dependencies, without
`optional: true`. `oidcc` is pinned directly, because `oidcc_plug` 0.5.1 accepts `oidcc ~> 3.7`, and only
3.9.0 fixes CVE-2026-75759. `oidcc` runs a supervised provider worker, which the package starts only when
the host adds the sign-in child (S7). So an application that only verifies bearer credentials carries the
code but runs none of it.

*Rejected:*

- **Optional dependencies.** Every module that names `Oidcc` would need a guard, and a host that forgot the
  dependency would learn it at the first sign-in instead of at compile time.
- **A fourth package.** D-64 asks for a second Plug in this one. A separate package would configure the
  issuer, the audience and the key store a second time, and hand the engine an actor it had to build
  through this package anyway.

*Cost:* `oidcc` needs OTP 27, so every host of this package does too, bearer-only ones included. This goes
in the README's installation section.

*Amended, 2 October 2026, at EB1's review: the package keeps the provider itself, not `oidcc`'s worker.*
EB1 started `Oidcc.ProviderConfiguration.Worker`. Its two reviews found four defects in that worker, each
read in its source (3.9.0):

- **Its default backoff, `stop`, ends it at the first failed fetch.** With EHOS down, a few restarts would
  take the application with it (FM-19).
- **A relative URI makes it crash in a loop.** Its decoder raises `case_clause` on a relative URI where it
  wants https, outside its backoff, so one malformed document crash-loops it up to the host's supervisor.
- **A failed key-set fetch is never retried while the document is held.** The worker reports the provider
  ready, and every token check fails with `provider_not_ready`.
- **Its table is a `bag` that only grows.** After the document or keys change once, every read falls back
  to a call into the worker. That call is serialized, waits up to five seconds while the worker fetches, and
  answers "unavailable" although a document is held.

It also fetches through `httpc`, which follows redirects (to plain http too), buffers a body of any size, and
adds a connect timeout to each call's timeout.

So `EhOsContract.Auth.SignIn` is itself the process that keeps the provider, on the pattern of
`EhOsContract.Auth.Keys`:

- **It fetches** the document and its key set through the package's own transport,
  `EhOsContract.Auth.SignIn.Http`, which `oidcc` is also given as its HTTP adapter for every call. The
  transport goes over https only, follows no redirect, reads at most 64 KiB, and ends a call at one deadline.
- **It decodes** with `Oidcc.ProviderConfiguration.decode_configuration/2`, and an exception there is a
  refused document, never a crash.
- **It holds both, or neither,** in a table of its own, which goes with the process.
- **It retries** from one second, doubling to thirty, and keeps what it holds when a refetch fails.

EB2 builds the client context from what is held, with `Oidcc.ClientContext.from_manual/5`, and hands it
to `oidcc_plug` through its `client_store`. `oidcc`'s protocol code is used as before; only the keeping of
the provider is the package's.

*Amended, 2 October 2026, at EB2a:* the context holds the client's private key, and neither `oidcc`'s struct
nor `JOSE.JWK` leaves the key out of an inspection. So `EhOsContract.Auth.SignIn.client_context/1` builds the
context for the call that needs it, from the child's name. It is never kept, logged or assigned to a
connection. What `oidcc` itself prints when it fails is outside the package's reach, and is the one place the
key could still appear.

### S2 — The browser holds one opaque token, and the table holds its hash

- **What the cookie carries.** The host's cookie session carries one random 32-byte token under one key, and
  nothing else of the package's.
- **What the table carries.** The table keys the session by the token's SHA-256, so someone who can read the
  table cannot turn a row back into a cookie, as with `phx.gen.auth`'s session tokens.
- **A new token per sign-in.** Every callback writes a new token and renews the Plug session, so a token
  planted before sign-in names nothing after it (session fixation).

`oidcc_plug` keeps the authorization request's `state`, `nonce` and PKCE verifier in the same cookie session
between the redirect and the callback. In a session that is only signed, the person can read them, and so
can anything that reads the cookie. The README therefore tells the host to encrypt its cookie session
(`encryption_salt`), and the template in `ehos-tools` does it.

*Rejected:*

- **The refresh token or the credential in the cookie.** D-64 rules it out, and the cookie's 4 KB would not
  hold the credentials of several applications.
- **The token stored as it is.** It would make the table a list of live sessions.

### S3 — The refresh token, the ID token and the credentials are encrypted with a key from `SECRET_KEY_BASE`

Chosen by the user, 2 October 2026. It replaces "stored as they are", which the user chose first and which
the review of this record's pull request (#79) reopened.

**Why encrypt.**

- **The credentials can be replayed.** Every credential in the table is a bearer credential. A reader of the
  table could replay it as the person whose session holds it until it expires, within ten minutes. That
  applies to this application, and to every other application the pages call (S8).
- **Nothing else shortens that window.** EHOS cannot revoke a credential once issued (D-33). Short of a
  shorter credential, which D-64 rejected, only keeping the reader from the plaintext does anything.
- **The refresh token alone is worth less.** EHOS authenticates the client with `private_key_jwt`, and the
  private key is a file mounted in the workload (`EHOS_CLIENT_KEY_FILE`), never in the database. It is
  encrypted anyway, because it costs nothing more.

**How.**

- **The key.** It is derived from the host's `SECRET_KEY_BASE`, which EHOS gives every workload (D-56), with
  `Plug.Crypto.KeyGenerator` and a salt of this package's own. `plug_crypto` already comes with `plug`, so
  this adds no dependency.
- **The cipher.** Each value is encrypted with `Plug.Crypto.MessageEncryptor`, which in `plug_crypto` 2.x
  is XChaCha20-Poly1305. The associated data is its row's session hash and its column, so a ciphertext
  copied to another row or column does not decrypt.
- **What stays plain.** The session hash, `subject`, `sid`, `auth_time`, the lease columns and the expiry
  times stay plain. The package selects, locks and expires by them.
- **A value that does not decrypt** is a session that is over. Its row is deleted, and the caller gets
  `{:error, :signed_out}`.
- **The host passes the secret** as `secret_key_base:` among the sign-in options (S7). The sign-in child
  refuses to start without it, or with one shorter than 64 bytes, Phoenix's own minimum.

**What it protects, and what it does not.**

- **It protects** against anyone who has the database without the workload:
  - a backup, which may leave the environment's namespace;
  - a replica or a dump;
  - an SQL injection elsewhere in the application that reads any table.

  Those are the readers who would otherwise get other applications' credentials.
- **It does not protect** against anyone who holds the workload, since the workload holds the key.

**Rotating `SECRET_KEY_BASE` signs everybody out.** That costs nothing new. The cookie session that carries
the session token (S2) is signed with the same secret, so rotating it already ends every session. For the
same reason, no list of older keys is kept.

*Rejected:*

- **Stored as they are.** Chosen first, on the argument that the refresh token cannot be presented without
  the client key. That argument holds for the refresh token only. It left the credentials replayable from
  any copy of the database. It also counted the rotation above as a new cost, and it is not one.
- **A key of its own**, for example a further variable from EHOS. It would mean a second secret to deliver
  and rotate, for no reader that `SECRET_KEY_BASE` does not already keep out.
- **The engine's vault.** It exists to crypto-shred personal data (v2 §17), which is not this.
- **`pgcrypto`.** The key would travel to the database with every query, and appear in its logs.

*Revisit if* EHOS ever accepts a refresh without client authentication, or if `SECRET_KEY_BASE` is ever
given to something other than the workload.

*Amended, 2 October 2026, at EB2a:*

- **What the associated data is.** A credential's column is named with the application's address it is for, so
  a credential moved to another application's row of the same session does not decrypt either.
- **When the key is derived.** Once, when the sign-in child starts, with a salt of the package's own. The child
  holds it beside the client key, left out of every inspection.
- **Where it is read.** The storage functions read it from the child by its name, and check what they are
  given before encrypting it. `Plug.Crypto.MessageEncryptor.encrypt/4` guards on a binary outside its own
  rescue, so a value of another type would otherwise print the key as its argument.
- **Whose session a row is.** The ID token's associated data also holds the row's `subject`, `sid` and
  `auth_time`. A writer who changes one of them makes a row that does not decrypt, not another person's
  session. S3 is about readers; this costs nothing and keeps a writer from turning a row into someone else's.

### S4 — One renewal per session: a lease on the session's row, taken and released by single statements

D-64 asks for a lease with an expiry, the row read again after taking it, and no transaction across the
call. Concretely:

1. **The fast path.** If the credential the request needs is good for more than 30 seconds by
   `EhOsContract.Clock`, it is used. Nothing is written.
2. **Take the lease** with one statement in autocommit:
   `UPDATE … SET lease_holder = $me, lease_until = clock_timestamp() + 15 s WHERE session = $1 AND (lease_until IS NULL OR lease_until < clock_timestamp()) RETURNING …`.
   The expiry is measured by the database's clock, so replicas whose clocks disagree still agree on it.
3. **Read the row again.** If a predecessor renewed meanwhile, release the lease and use its credential.
4. **Call EHOS**, with `request_opts: %{timeout: 10_000}`, shorter than the lease.
5. **Write the result and release the lease** in one short transaction after the call, guarded by
   `WHERE lease_holder = $me`. If no row matches, the lease was lost (S5).
6. **A waiter** that cannot take the lease reads the row again every 200 ms. It uses its predecessor's
   credential as soon as one is good, takes the lease if it is free and the credential is still stale, and
   gives up after 15 seconds.

The numbers are the package's defaults and are options. The order between them is checked at boot: the
call's timeout must be shorter than the lease.

*Rejected:*

- **`SELECT … FOR UPDATE` around the call.** It holds a transaction and a lock across the call, which D-64
  forbids.
- **An advisory lock.** A session-level advisory lock holds a pooled connection for the whole call. A
  transaction-level one is the transaction D-64 forbids.
- **One process per session, by registry.** Across replicas it needs a cluster, which EHOS's workloads are
  not.
- **`LISTEN/NOTIFY` for waiters.** It needs a dedicated connection per replica. Polling, bounded at 15
  seconds, is enough at one renewal per session per ten minutes.

### S5 — What each outcome of a renewal leaves

| Outcome | The refresh token | The session | The caller gets |
| --- | --- | --- | --- |
| Renewed | the new one | renewed, lease released | the new credential |
| `invalid_target` (D-64: not for this application) | kept, unchanged — EHOS did not consume it | lives on; the refusal for that application is remembered for 10 minutes | `{:error, :refused}` for that application only |
| `invalid_grant` (the sign-in is over for this client) | — | deleted, with its credentials | `{:error, :signed_out}`; a page is sent to sign in |
| Timeout, connection reset, 5xx, or another error response (logged) | kept — whether EHOS rotated is unknown, and an error response consumes nothing | lives on, lease released | the held credential while it is unexpired, else `{:error, :ehos_unavailable}` |
| A 2xx response that `oidcc` refuses (`sub_invalid`, an ID token that does not validate) | lost — EHOS rotated it, and the successor is in the refused response | deleted | `{:error, :signed_out}` |
| The lease was lost before the write | the new one is in hand but cannot be stored safely | deleted | `{:error, :signed_out}` |
| A waiter gave up | — | unchanged | `{:error, :renewal_busy}` |

- **Why a refusal is remembered.** Without it, a person with no role in a second application would send one
  refused request to EHOS, and leave one audit row there, on every page they open. Ten minutes is a
  credential's lifetime: a role granted meanwhile is seen as soon as a credential issued now would be.
- **Why a timeout keeps the old token.** No better choice exists under strict rotation. If EHOS had rotated,
  the next renewal presents a used token, gets `invalid_grant`, and the person signs in again. D-64 accepts
  this ("a token response lost in transit ends the sign-in").
- **Why a lost lease ends the session.** A lease is lost only when the holder overran its 15 seconds despite
  a 10-second timeout, a paused BEAM for instance. By then another holder may have presented the same token.
  Ending the session costs one sign-in. Guessing could revoke the sign-in in every application of that
  browser.

### S6 — The defaults of `oidcc` and `oidcc_plug` that the package overrides

| Option | Set to | Default, and why not |
| --- | --- | --- |
| `require_pkce` (`Authorize`) | `true` | `false`: without `code_challenge_methods_supported` in discovery, PKCE is silently omitted |
| `preferred_auth_methods` (callback, refresh) | `[:private_key_jwt]` | all six: a failed `private_key_jwt` falls through to the next method silently |
| `client_secret` | a random value made at each start, never written down (amended at EB1's review, 2 October 2026; first "a fixed non-secret binary") | `:unauthenticated` refuses every method but `none`. A fixed value would be worse than it looks: `oidcc` turns the client secret into an `oct` key for any `HS*` algorithm a document names, so an ID token signed with a publicly known secret would validate |
| `check_peer_ip` (callback) | `false` | `true`: behind an ingress with several pods, the redirect and the callback may arrive from different peers, and an IP that changes refuses a real person. The user-agent check stays on. |
| `retrieve_userinfo` (callback) | `false` | `true`: EHOS's userinfo says only `sub`, which the ID token already says, and that call ignores `request_opts`, so it waits up to 60 s |
| `request_opts.timeout` (every call) | 10 s, one deadline for the whole call | 60 s, longer than the lease, with a connect timeout on top |
| `request_opts.http_adapter` (every call) | the package's own (S1, as amended) | `httpc`, which follows redirects and reads a body of any size |
| client profiles | none | `fapi2_security_profile` would strip `Ed25519` from the ID token's algorithms |

**The discovery document is checked before the first sign-in.** Whether `iss` is checked depends on
`authorization_response_iss_parameter_supported`, so the package does not rely on the document saying so.
It refuses to sign anyone in, and logs why, unless the document has:

- `authorization_response_iss_parameter_supported: true`;
- `S256` among `code_challenge_methods_supported`;
- `Ed25519` among `id_token_signing_alg_values_supported`, and no `none` or `HS*` beside it (added at EB1's
  review, 2 October 2026: `oidcc` accepts an ID token in any algorithm the document names);
- `private_key_jwt`, with `Ed25519` or `EdDSA`, for the token endpoint.

The check runs on the document the package holds, not at boot, so the application starts while EHOS is down
(driver 4). It is logged once for each document that changes the answer, not on every refused sign-in. A
document whose `issuer` is not the configured one, or whose endpoints are not https, is not held at all.

### S7 — The interface: a child, a router, a plug and two functions

```elixir
# config/runtime.exs
config :eh_os_contract_auth,
  # the verifier's, as today: sign-in verifies this application's credential with them
  issuer: System.fetch_env!("EHOS_ISSUER"),
  audience: System.fetch_env!("EHOS_AUDIENCE"),
  sign_in: [
    client_id: System.fetch_env!("EHOS_CLIENT_ID"),
    client_key_file: System.fetch_env!("EHOS_CLIENT_KEY_FILE"),
    address: "https://" <> System.fetch_env!("PHX_HOST"),
    # what the stored tokens are encrypted with (S3)
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    # other applications the pages call, by name: their addresses (D-68),
    # e.g. {"ledger": "https://ledger.production.ehos.localhost"}
    applications: Jason.decode!(System.get_env("EHOS_SIGN_IN_APPLICATIONS", "{}"))
  ]

children = [MyApp.Repo, EhOsContract, EhOsContract.Auth, EhOsContract.Auth.SignIn]

# router
forward "/auth/ehos", EhOsContract.Auth.SignIn.Router   # GET sign-in, GET callback, POST sign-out
pipeline :signed_in, do: plug EhOsContract.Auth.Session  # or a redirect to sign in

# a controller, a LiveView event, anything that calls with the person's authority
{:ok, actor} = EhOsContract.Auth.Session.actor(session)
{:ok, token} = EhOsContract.Auth.Session.credential(session, "ledger")
```

- **The redirect URI** is `address <> "/auth/ehos/callback"`, as D-64 fixes it.
- **Where renewal happens.** Only in `actor/1` and `credential/2`, the two places a request needs a
  credential, so a page that calls nothing never renews (D-64: on demand). The plug checks that the person
  is signed in and assigns the session. Assigning `eh_os_contract_actor`, for a pipeline that forwards to
  `EhOsContract.Plug`, is an option of the plug.
- **LiveView** reads the session map in `mount` and calls the same functions. The package does not depend
  on Phoenix LiveView, and two LiveView processes of one session meet at the lease (S4).
- **The path after sign-in** travels in `oidcc_plug`'s `state`. It is accepted only as a local path, so the
  callback is not an open redirect.
- **Sign-out** is a `POST` behind CSRF protection. It deletes the row and redirects to EHOS's end-session
  endpoint, built by `Oidcc.initiate_logout_url/4` with `id_token_hint`. Its `post_logout_redirect_uri` is
  exactly `address <> "/"` (D-68). It is derived, never configured.
- **The client key** (D-68) is the file at `EHOS_CLIENT_KEY_FILE`, one private Ed25519 JWK, loaded as it is
  and handed to `oidcc` as `client_jwks`. Its `kid` and `use` are kept, because `oidcc` copies the `kid` into
  every client assertion and EHOS checks an assertion only against the key with that `kid`. The sign-in
  child refuses to start on a file of any other shape:
  - a PEM;
  - a JWK that lacks any of `kty: "OKP"`, `crv: "Ed25519"`, `x`, `d`, `use: "sig"`, `alg: "Ed25519"`;
  - a `kid` that is not the RFC 7638 thumbprint of its public half.
- **Environment variables.** The package reads none itself, as with `issuer` and `audience`. The host maps
  `EHOS_SIGN_IN_APPLICATIONS` in `config/runtime.exs`, as above, and so does the `ehos_app` template.

*Accepted by the user, 2 October 2026.*

*Amended, 2 October 2026, at EB2b:*

- **The routes** are `GET /sign-in?return_to=<path>`, `GET /callback` and `POST /sign-out` under the forward.
  `GET /sign-in` answers 503 while `provider/1` refuses.
- **The plug** assigns `eh_os_contract_session` with the session's `subject`, `sid` and `auth_time`, and nothing
  of EHOS's tokens. A request without a session is redirected to sign in when it is a `GET` or `HEAD`, and
  answers 401 otherwise.
- **Sign-out** wraps itself in `Plug.CSRFProtection`, so it is protected even in a pipeline without
  `protect_from_forgery`.
- **`actor/2`** takes the session map or the connection, and an option list (`sign_in:` and `verify/2`'s).

*Amended again at EB2b's review, the same day:*

- **The callback verifies the credential** as every request will, and requires it to name the person the ID
  token names. Otherwise a credential every page refuses (another audience, keys not yet held) sends the
  browser round EHOS's single sign-on for ever.
- **A new sign-in starts the Plug session empty and ends the browser's previous session.** `renew: true` alone
  re-signs the cookie store's cookie with every key kept, a planted CSRF token included. This is what S2 meant
  by "renews the Plug session".
- **The plug redirects only a browser's navigation**, and only when signing in helps (no session, or an expired
  credential). A page's `fetch()` gets 401, not a redirect across origins to EHOS.
- **Known limits:**
  - two sign-ins begun in one browser at once, in two tabs, overwrite each other's request in `oidcc_plug`'s
    single session entry, and the earlier callback is refused with 401;
  - a sign-out while EHOS's document is not held ends the session here only, so the next sign-in at EHOS is
    silent.

*Amended, 2 October 2026:* the key file, the post-logout address and `EHOS_SIGN_IN_APPLICATIONS` follow
`eh-os` D-68. It answers [eh-os#134](https://github.com/EmpoweredHouse/eh-os/issues/134) and
[#135](https://github.com/EmpoweredHouse/eh-os/issues/135) (eh-os-contract#81), and was accepted by the user
that day; its acceptance is [eh-os#141](https://github.com/EmpoweredHouse/eh-os/pull/141). They replace the
interim this section planned first: PEM or JWK, and the post-logout address as an option.

### S8 — Another application's credential is handed out as it is, not verified here

`actor/1` returns an actor verified by `verify/2` against the application's own audience: driver 6, the
same actor the bearer Plug gives. `credential/2` for another application returns the raw token EHOS issued,
to be sent as a bearer token to that application, which verifies it. The package reads only `expires_in`
from the token response, to know when it goes stale.

*Rejected: verifying it here.* Its `aud` is not this application's, and the mapping from an address to an
audience is EHOS's (D-64). Verifying here would need either that mapping, or a `verify/2` that skips `aud`.
A `verify/2` that skips `aud` is the one switch this package must never offer.

### S9 — An ID token as a bearer credential stays `:bad_signature`, and `client_id` is ignored

- **An ID token is refused** the way any token without `cap` is refused today. D-64 makes that refusal a
  security property, so a test pins it, with an ID token whose `aud` equals the application's audience. No
  new reason is added: a new reason is visible to hosts, and "not a credential in EHOS's form" is what
  `:bad_signature` already means.
- **The `client_id` claim** (RFC 9068 §2.2) in a credential issued through sign-in is ignored, and a test
  pins that it is accepted. Recording it in decision rows is G-3's, later.

### S10 — Renewal goes through `Oidcc.refresh_token/5`, and EHOS returns an ID token on refresh

**The problem.** `oidcc` refuses a refresh response without an ID token. It returns `{error, sub_invalid}`
after the HTTP call, so the rotated refresh token in that response is lost. When this record was written,
EHOS sent no ID token on refresh, so every session would have ended at its first renewal.

**Asked of EHOS** in [eh-os#133](https://github.com/EmpoweredHouse/eh-os/issues/133): return one, as OpenID
Connect Core §12.2 allows. Chosen by the user, 2 October 2026.

*Rejected: sending the refresh request ourselves.* That would mean:

- a `private_key_jwt` assertion through JOSE;
- a form POST through Req;
- the credential checked by `verify/2`.

It would not have waited for EHOS. But it moves protocol code that D-64 gives to a certified library into
code written here, and departs from D-64 as written.

*Done, 2 October 2026:* EHOS returns the ID token since
[eh-os#137](https://github.com/EmpoweredHouse/eh-os/pull/137) (`801f758`, in `main`, in no release yet:
`v0.3.0` lacks it), as eh-os-contract#80 describes. The token is minted as the code exchange's:

- `iss`, `sub` and `aud` (the `client_id`) are the code exchange's;
- `auth_time` and `sid` are the sign-in's;
- `iat` is new, and it lives 600 s;
- it carries no `nonce` and no `at_hash`;
- it is signed `Ed25519`.

A renewal for another application returns the same kind of token, with `aud` still the `client_id`. So:

- **Renewal no longer waits.** The work tests against EHOS's `main` until a release carries #137.
- **The session keeps each renewal's ID token.** Keeping the first would work as well, because EHOS checks
  an `id_token_hint`'s `sub`, `sid` and `auth_time`, never its `iat` or `exp` (#80). Replacing it costs
  nothing and keeps the row's one ID token the latest one EHOS signed.
- **S5's row for a 2xx response that `oidcc` refuses stays**, as a defence. It can still happen, for example
  when the clocks disagree past `oidcc`'s leeway. The session ends there, and the old token is never
  presented again.

### S11 — Rows end with the sign-in, without a job

A session's row is deleted at sign-out, at `invalid_grant` and when its lease is lost. Rows past the
absolute limit (12 hours from `auth_time`, D-66) are deleted by the next sign-in, as EHOS prunes its
refresh store. No job renews or cleans: D-64 forbids renewing without the person, and a cleanup job would
be the first job this package asks a host to run.

*Amended, 2 October 2026, at EB2a's review:* a session past the absolute limit is also refused when it is read,
whether or not a sign-in has deleted its row yet. Otherwise, on a quiet deployment, an old cookie would name a
person for as long as nobody else signed in. The deletion at the next sign-in is a statement of its own, outside
the new sign-in's transaction.

## Not decided here

- **The client recorded in an application's decision rows** — G-3, later (Stage 9's "Deliberately later").
- **Back-channel logout** — deferred by D-64. Other applications' sessions end at their next renewal.
- **A LiveView `on_mount` hook in the package** — only if a second host writes the same one.

## Confirmation

The criteria of eh-os-contract#78, each a test in the package's suite against an EHOS played by the test
through `oidcc`'s HTTP adapter (no port, no network):

- **Sign-in.** A browser signs in through the router and returns signed in, and the session's actor
  reaches `EhOsContract.Plug`. A callback whose `iss` is not the issuer's is refused.
- **Renewal.**
  - It happens past ten minutes, under `EhOsContract.Clock.at/2`.
  - Two processes of one session, on separate connections, whose credentials expire together, make exactly
    one refresh, and the sign-in survives.
  - EHOS's fake revokes the sign-in when a refresh token is presented twice.
  - An unmocked `Oidcc.refresh_token/5` returns `{:ok, %Oidcc.Token{}}` for a refresh response whose ID token
    has exactly the claims eh-os-contract#80 lists (S10). This is the test #133 left to this suite. Its proof
    stops at the shape of the response: the fake mints the token, not EHOS. EHOS's own endpoint is proven by
    Stage 9's closing test, step 8, on a cluster.
- **No transaction during the call.** When the fake EHOS is called, the caller is not in a transaction, and
  no connection of the repo is `idle in transaction`. The tests that check this, and the concurrency tests,
  run against committed data, outside the Ecto sandbox.
- **Refusals.** After `invalid_target`, the same refresh token renews for the session's own application.
  After `invalid_grant`, the session is gone.
- **Several applications.** Two `resource`s give two credentials, each with one `aud`.
- **ID tokens and `client_id`.** An ID token presented as a bearer credential is refused (S9). A credential
  carrying `client_id` is accepted.
- **Sign-out.** It redirects to `end_session` with `id_token_hint`, and the row is gone.
- **Encryption (S3).**
  - No refresh token, ID token or credential appears in plain text in the table.
  - A ciphertext moved to another row does not decrypt.
  - A session whose values do not decrypt under the configured `secret_key_base` is signed out.
- **D-68.**
  - A key file of exactly D-68's shape loads, and the client assertion's header carries its `kid`.
  - A PEM is refused at boot, and so is a JWK without `use` or whose `kid` is not its thumbprint.
  - Sign-out sends exactly `https://<host>/`.
- **The overrides.** A discovery document without `authorization_response_iss_parameter_supported`, or
  without `S256`, refuses sign-in (S6).
