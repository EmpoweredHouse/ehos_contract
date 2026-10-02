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

### S3 — The refresh token, the ID token and the credentials are stored as they are, without encryption

Chosen by the user, 2 October 2026. The refresh token alone does not renew anything:

- **The private key is needed too.** EHOS's token endpoint authenticates the client with `private_key_jwt`,
  and the private key is a file the operator mounts in the workload (`EHOS_CLIENT_KEY_FILE`). It is never
  in the database.
- **What a reader of the table can still do: replay credentials.** ID tokens grant nothing, and refresh
  tokens cannot be presented. But every credential in the table is a bearer credential. Until it expires,
  within ten minutes, it can be replayed as the person whose session holds it. That applies to this
  application, and to every other application the pages call (S8).
- **That risk is accepted, not mitigated.** A reader of this table reads the application's own tables beside
  it already. What it gains here ends with each credential's ten minutes, and it cannot renew. A reader that
  holds the workload would get through encryption too (next point). And EHOS cannot revoke a credential
  once issued (D-33), so no mitigation inside the application shortens the window. Only a shorter credential
  would, which D-64 rejected.
- **Encryption would add little.** Encrypting with a key the same process holds protects only a copy of the
  database taken without the workload: a dump or a backup. In exchange, it would bind every session to that
  key's rotation.

*Rejected:*

- **Encryption with a key derived from `SECRET_KEY_BASE`.** Rotating `SECRET_KEY_BASE` would then sign
  everybody out. For the thin protection above, it adds a key to manage and a failure to explain.
- **The engine's vault.** It exists to crypto-shred personal data (v2 §17), which is not this.

*Revisit if* EHOS ever accepts a refresh without client authentication, or the database's backups leave the
environment's namespace while the client key does not.

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
| `client_secret` | a fixed non-secret binary | `:unauthenticated` refuses every method but `none` |
| `check_peer_ip` (callback) | `false` | `true`: behind an ingress with several pods, the redirect and the callback may arrive from different peers, and an IP that changes refuses a real person. The user-agent check stays on. |
| `retrieve_userinfo` (callback) | `false` | `true`: EHOS's userinfo says only `sub`, which the ID token already says, and that call ignores `request_opts`, so it waits up to 60 s |
| `request_opts.timeout` (token calls, provider worker) | 10 s | 60 s, longer than the lease |
| client profiles | none | `fapi2_security_profile` would strip `Ed25519` from the ID token's algorithms |

**The discovery document is checked before the first sign-in.** Whether `iss` is checked depends on
`authorization_response_iss_parameter_supported`, so the package does not rely on the document saying so.
It refuses to sign anyone in, and logs why, unless the document has:

- `authorization_response_iss_parameter_supported: true`;
- `S256` among `code_challenge_methods_supported`;
- `Ed25519` among `id_token_signing_alg_values_supported`;
- `private_key_jwt`, with `Ed25519` or `EdDSA`, for the token endpoint.

The check runs on the provider worker's document, not at boot, so the application starts while EHOS is
down (driver 4).

### S7 — The interface: a child, a router, a plug and two functions

```elixir
# config/runtime.exs
config :eh_os_contract_auth,
  sign_in: [
    client_id: System.fetch_env!("EHOS_CLIENT_ID"),
    client_key_file: System.fetch_env!("EHOS_CLIENT_KEY_FILE"),
    address: "https://" <> System.fetch_env!("PHX_HOST"),
    # other applications the pages call, by name: their addresses (eh-os#134)
    applications: %{"ledger" => "https://ledger.production.example.com"}
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
  EHOS's derived one (eh-os#135).

*Accepted by the user, 2 October 2026.*

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

### S10 — Renewal goes through `Oidcc.refresh_token/5`, once EHOS returns an ID token on refresh

`oidcc` refuses a refresh response without an ID token. It returns `{error, sub_invalid}`, after the HTTP
call, so the rotated refresh token in that response is lost. EHOS sends no ID token on refresh, so every
session would end at its first renewal.

Asked of EHOS in [eh-os#133](https://github.com/EmpoweredHouse/eh-os/issues/133): return one, as OpenID
Connect Core §12.2 allows. Chosen by the user, 2 October 2026. The renewal part of the work waits for it.
Sign-in, storage and sign-out do not.

*Rejected: sending the refresh request ourselves.* That means a `private_key_jwt` assertion through JOSE, a
form POST through Req, and the credential checked by `verify/2`. It would not wait for EHOS, but it moves
protocol code that D-64 gives to a certified library into code written here, and departs from D-64 as
written.

*Until #133 is merged,* every renewal ends in S5's row for a 2xx response that `oidcc` refuses. The session
ends, and the old token is never presented again. An error response or a 5xx keeps S5's own rows: EHOS
consumed nothing.

### S11 — Rows end with the sign-in, without a job

A session's row is deleted at sign-out, at `invalid_grant` and when its lease is lost. Rows past the
absolute limit (12 hours from `auth_time`, D-66) are deleted by the next sign-in, as EHOS prunes its
refresh store. No job renews or cleans: D-64 forbids renewing without the person, and a cleanup job would
be the first job this package asks a host to run.

## Not decided here

- **The client recorded in an application's decision rows** — G-3, later (Stage 9's "Deliberately later").
- **Back-channel logout** — deferred by D-64. Other applications' sessions end at their next renewal.
- **How a workload learns other applications' addresses** — [eh-os#134](https://github.com/EmpoweredHouse/eh-os/issues/134).
  Until then, configuration.
- **The client key file's format and the post-logout address** — [eh-os#135](https://github.com/EmpoweredHouse/eh-os/issues/135).
  Until then, PEM and JWK are both read.
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
- **No transaction during the call.** When the fake EHOS is called, the caller is not in a transaction, and
  no connection of the repo is `idle in transaction`. The tests that check this, and the concurrency tests,
  run against committed data, outside the Ecto sandbox.
- **Refusals.** After `invalid_target`, the same refresh token renews for the session's own application.
  After `invalid_grant`, the session is gone.
- **Several applications.** Two `resource`s give two credentials, each with one `aud`.
- **ID tokens and `client_id`.** An ID token presented as a bearer credential is refused (S9). A credential
  carrying `client_id` is accepted.
- **Sign-out.** It redirects to `end_session` with `id_token_hint`, and the row is gone.
- **The overrides.** A discovery document without `authorization_response_iss_parameter_supported`, or
  without `S256`, refuses sign-in (S6).
