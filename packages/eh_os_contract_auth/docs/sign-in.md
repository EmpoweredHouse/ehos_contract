# Sign people in through EHOS

This page tells a developer how to let a person sign in to the pages of the application. The person
signs in at EHOS, with OpenID Connect, and the application keeps a session for them. The page also
tells how to protect the routes behind that session from forgery.

## Prerequisites

- You did the steps of [Get started](getting-started.md): the key process runs, and the migration of
  the package is at version 3 or later.
- The `ehos.yaml` of the application has the key `sign_in`, and an entry `web` that is
  `public: true`. EHOS then gives the workload the variables of the table below.
- The host is a Phoenix application with a cookie session.

| Variable | What it holds |
| --- | --- |
| `EHOS_CLIENT_ID`, `EHOS_CLIENT_KEY_FILE` | the client of the application at EHOS, and the file of its private key |
| `EHOS_SIGN_IN_APPLICATIONS` | the other applications that the pages call as the person, as a JSON object of names and addresses |
| `EHOS_SIGN_IN_ABSOLUTE` | how long a session lasts, in seconds |

EHOS also gives `EHOS_CLIENT_ID` and `EHOS_CLIENT_KEY_FILE` to an application that only reads the
people or only sends mail. Only `EHOS_SIGN_IN_APPLICATIONS` tells that the application signs people
in.

## How does a person sign in?

![The application sends the browser to EHOS, the person signs in there, the application exchanges the code for tokens and keeps them encrypted in its database, and renews the credential through EHOS while the session lasts.](img/sign-in.svg)

1. The person opens a page that needs a session. Without a session, the application sends the
   browser to `/auth/ehos/sign-in`.
2. The application redirects the browser to EHOS, with PKCE and a nonce.
3. The person signs in at EHOS.
4. EHOS redirects the browser to the callback of the application, with a code.
5. The browser sends the code to the callback. The application refuses the callback if the `iss` of
   EHOS is not the configured issuer.
6. The application exchanges the code at EHOS. It signs the request with its client key
   (`private_key_jwt`), and uses no other method.
7. EHOS issues an ID token, a refresh token and a credential for the application.
8. The application verifies the credential as it verifies a bearer credential. Then it writes the
   session to its database, with each token encrypted.
9. The application redirects the browser back to the page, with a new session cookie.
10. The browser sends the session cookie with each next request.
11. If the credential expires in 30 seconds or less, the application renews it through EHOS before
    it uses it.

## 1. Configure the sign-in

Configure `sign_in:` only when EHOS gives `EHOS_SIGN_IN_APPLICATIONS`:

```elixir
# config/runtime.exs, beside issuer: and audience:
if ehos_sign_in_applications = System.get_env("EHOS_SIGN_IN_APPLICATIONS") do
  config :eh_os_contract_auth,
    sign_in: [
      client_id: System.fetch_env!("EHOS_CLIENT_ID"),
      client_key_file: System.fetch_env!("EHOS_CLIENT_KEY_FILE"),
      address: "https://" <> System.fetch_env!("PHX_HOST"),
      secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
      applications: Jason.decode!(ehos_sign_in_applications),
      # How long a session lasts from the sign-in at EHOS: the value of the installation.
      absolute_limit: String.to_integer(System.get_env("EHOS_SIGN_IN_ABSOLUTE", "43200"))
    ]
end
```

The sign-in reads no environment variable itself. `config/runtime.exs` maps each one.

| Key | What it is |
| --- | --- |
| `client_id` | the client of the application at EHOS |
| `client_key_file` | the file of the private key, one Ed25519 JWK, as the operator of EHOS writes it |
| `address` | the public address of the application, `https://<host>` |
| `secret_key_base` | the key that encrypts the tokens of each session |
| `applications` | the other applications, by name: `%{"ledger" => "https://ledger.example.org"}` |
| `absolute_limit` | how long a session lasts from the sign-in at EHOS, in seconds; 12 hours when not given or `nil` |

The callback is `address <> "/auth/ehos/callback"`, and sign-out returns to `address <> "/"`. The
package makes these two addresses from `address`, and you do not configure them, because EHOS
compares them character by character.

**Result:** the configuration is ready for the child of the next step, which checks it.

## 2. Start the sign-in process

Add `EhOsContract.Auth.SignIn` to the supervision tree, after `EhOsContract.Auth`, only where
`sign_in:` is configured:

```elixir
sign_in = if Application.get_env(:eh_os_contract_auth, :sign_in), do: [EhOsContract.Auth.SignIn], else: []
children = [MyApp.Repo, EhOsContract, EhOsContract.Auth] ++ sign_in
```

Without `sign_in:`, the child refuses to start, so a host without the condition does not boot in
development or in tests.

If EHOS uses a certificate authority of its own, give its file to this child too:
`{EhOsContract.Auth.SignIn, cacertfile: ca}`.

The child refuses to start, and the boot of the host stops, in each of these cases:

- `config :eh_os_contract_auth, :sign_in` is missing, is not a keyword list, or has a key that the
  table above does not list.
- The issuer is not `https://<host>[:port]` alone: a host in lower case, and no user, path, query or
  fragment.
- `client_id` is not a string with text.
- `address`, or an address in `applications`, is not exactly `https://<host>` in lower case: no
  port, no path, no trailing slash and no query.
- An address in `applications` is `address`. `applications` names only the other applications.
- `secret_key_base` has fewer than 64 bytes.
- `absolute_limit` is not a whole number of seconds from 1 minute to 366 days.
- The key file is not one private Ed25519 JWK. The JWK has exactly `kty`, `crv`, `x`, `d`,
  `use: "sig"`, `alg: "Ed25519"` and `kid`. The `kid` is the RFC 7638 thumbprint of its public half.
  The child refuses a PEM file.

The error does not show a secret.

**Result:** the child runs. It fetches the discovery document of EHOS and its keys, and fetches
them again every 5 minutes. If EHOS is down, the child starts all the same. It tries again after 1
second, and doubles the wait up to 30 seconds. A failed fetch keeps what the child had.

Each call to EHOS uses https, follows no redirect, reads 64 KiB or less, and stops after 10 seconds.

## 3. Add the routes and protect the session

Encrypt the cookie session, and give it `same_site: "Lax"` and `secure: true`:

```elixir
# endpoint.ex
plug Plug.Session,
  store: :cookie,
  key: "__Host-my_app",
  signing_salt: "...",
  encryption_salt: "...",
  same_site: "Lax",
  secure: true
```

The cookie keeps the `state`, the nonce and the PKCE verifier of the sign-in between the redirect
and the callback, so encrypt it. `Plug.Session` sets no `SameSite` attribute by default, and
browsers do not agree on what to do without one. With `"Lax"`, a browser does not send the cookie
with a form that a page of another site posts. If EHOS is on another site than the application,
do not use `"Strict"`. A browser then does not send the cookie when EHOS redirects back to the
callback, and the sign-in fails.

Plug marks the cookie `Secure` by itself only when the request uses https. TLS can end before the
application, so set `secure: true`. Without it, a browser can send the session cookie over plain
http. With the prefix `__Host-` in the name, the browser refuses this cookie from another host of the
same domain, such as another application.

Forward `/auth/ehos` to the routes of the package, in a scope that fetches the session and protects
from forgery:

```elixir
# router.ex
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :protect_from_forgery
end

scope "/" do
  pipe_through :browser
  forward "/auth/ehos", EhOsContract.Auth.SignIn.Router
end
```

| Route | What it does |
| --- | --- |
| `GET /auth/ehos/sign-in?return_to=/visits/7` | redirects the browser to EHOS, with PKCE and a nonce |
| `GET /auth/ehos/callback` | EHOS returns here; the application exchanges the code and signs the person in |
| `POST /auth/ehos/sign-out` | ends the session here and at EHOS |

Put `EhOsContract.Auth.Session` in front of each route that needs a person. Keep
`protect_from_forgery` in that pipeline:

```elixir
pipeline :signed_in do
  plug EhOsContract.Auth.Session
end

scope "/visits" do
  pipe_through [:browser, :signed_in]
  post "/:id/close", MyAppWeb.VisitController, :close
end
```

`EhOsContract.Auth.Session` does not protect from forgery. The browser sends the session cookie with
each request to the application, also when another site makes the request. So each `POST`, `PUT`,
`PATCH` or `DELETE` route of the host behind the session needs `protect_from_forgery`. Each form or
`fetch()` of its pages then sends the CSRF token.

`protect_from_forgery` does not check a `GET` request, and with `"Lax"` a link on another site sends
the cookie. So a `GET` route behind the session must change nothing.

**Result:** a person who opens `/visits/7` without a session goes to EHOS, signs in, and comes back
to `/visits/7`.

## 4. Read the person on a page

In a controller, ask for the actor of the person:

```elixir
{:ok, actor} = EhOsContract.Auth.Session.actor(conn)
```

A LiveView gives `actor/2` the session map that `mount/3` gets.

**Result:** `actor` is the actor of the credential of the person for this application. The package
verifies it with `EhOsContract.Auth.verify/2`, as it verifies a bearer credential. It never reads the
person from the plain columns of the session.

The plug also puts `conn.assigns.eh_os_contract_session` on the connection: the `subject`, `sid` and
`auth_time` of the person. It holds no token of EHOS.

**Keep the `sub` of the person, not the email.** The `sub` of a person is their `id` in EHOS. It
never changes. The people API gives the same `id` for the same person. An email can
change, and EHOS can later give it to another person.

## 5. Send the person to the contract over HTTP

To let the pages call `EhOsContract.Plug` as the person, give the plug `assign_actor: true`:

```elixir
pipeline :signed_in_api do
  plug :accepts, ["json"]
  plug :fetch_session
  plug EhOsContract.Auth.Session, assign_actor: true
end

scope "/api" do
  pipe_through :signed_in_api
  forward "/", EhOsContract.Plug, contracts: [Clinic.Contracts.VisitSettlement]
end
```

The plug sets `conn.assigns.eh_os_contract_actor`, as `EhOsContract.Auth.Plug` does for a bearer
credential.

Do not put `protect_from_forgery` in this pipeline, and put no other route in it. It refuses each
JSON call that does not send the CSRF token in `x-csrf-token`. `EhOsContract.Plug` has its own
protection: it accepts a command or a
recorded event only with `content-type: application/json`. A browser asks the application before a
page of another origin can send that type. So do not let the CORS configuration allow credentials
for an origin that you do not trust.

**Result:** a `fetch()` from a page of the application, with `content-type: application/json`, gets
to the contract as the person.

## 6. Add sign-out

Sign-out is a `POST` with the CSRF token:

```heex
<.form for={%{}} action={~p"/auth/ehos/sign-out"} method="post">
  <button>Sign out</button>
</.form>
```

**Result:** the application deletes the session and drops the cookie session. It sends the browser
to the end-session endpoint of EHOS, with the ID token as `id_token_hint`, and EHOS sends it back to
`address <> "/"`. If the session is already gone, or EHOS is not available, the browser goes
directly to `address <> "/"`. The session here ends all the same.

The router checks the CSRF token itself. A request without a valid token gets 403.

## What occurs when the credential expires?

The credential that EHOS issues for the application lives 10 minutes. `actor/2`, and the plug with
`assign_actor: true`, renew it when it expires in 30 seconds or less. They renew it through EHOS,
with the refresh token of the session. Nothing renews it without a request.

- **One renewal for each session.** Many requests of one session can ask at the same time. One of
  them takes a lease on the row of the session, and renews. The lease uses the clock of the
  database.
- **The other requests do not wait for an unexpired credential.** They use the credential that they
  have. Only when it has expired, they wait for the renewal, for 15 seconds or less.
- **No transaction is open while the application calls EHOS.**

| What occurs | Result |
| --- | --- |
| The sign-in at EHOS has ended | The session ends. A navigation goes to sign in again. |
| EHOS is down or slow | The request uses the credential while it has not expired. After that, the request gets 503. The application keeps the refresh token, and does not call EHOS again for 5 seconds. |
| EHOS gives an answer that the application cannot use | The session ends, because EHOS has already replaced the refresh token. |

## How long does a session last?

`absolute_limit` sets how long a session lasts from the sign-in at EHOS, renewed or not. EHOS gives
the limit of the installation as `EHOS_SIGN_IN_ABSOLUTE`, and uses the same limit at its own
endpoints.

The sign-in asks EHOS for a sign-in that is not older than `absolute_limit` (`max_age`). So if the
application keeps a shorter limit than the installation, EHOS asks the person for the password
again sooner. The browser does not go between the application and EHOS again and again.

EHOS alone uses the idle limit, `EHOS_SIGN_IN_IDLE`. EHOS refuses a refresh token that nobody used
for that time. The session then ends at the next renewal.

Without a `max_age` on the cookie, the cookie ends when the browser closes, and the person signs in
again. To keep the session after the browser closes, give the cookie a `max_age` equal to
`absolute_limit`. The row of the session, not the
cookie, decides when the session ends.

## Where does the application keep a session?

The tables of version 3 of the package keep the sessions. If you migrated an earlier version, add a
migration:

```elixir
defmodule MyApp.Repo.Migrations.UpgradeEhOsContractAuthToV3 do
  use Ecto.Migration

  def up, do: EhOsContract.Auth.Migrations.up(version: 3)
  def down, do: EhOsContract.Auth.Migrations.down(version: 3)
end
```

- **The browser** holds a random token. The table holds only its SHA-256.
- **The tokens of EHOS**: the package encrypts the refresh token, the ID token and each credential.
  The key comes from `secret_key_base`. The package binds each encrypted value to its row and its
  column. So a backup, a replica or a dump holds nothing that a person can present.
- **A new `SECRET_KEY_BASE`** signs everybody out, as it does through the cookie session.

## What can go wrong

| What you see | Why |
| --- | --- |
| `GET /auth/ehos/sign-in` answers 503 | The child does not have the document and the keys of EHOS yet, or the document does not say what the sign-in needs. The log tells which. |
| `GET /auth/ehos/callback` answers 401 | The callback signed nobody in, or `verify/2` refused the credential. The log gives the name of the reason, never a token. |
| A page answers 401 instead of a redirect | The request is not a navigation, for example a `fetch()`. A redirect would take it to EHOS, to another origin. |
| A page answers 401 for a signed-in person | `verify/2` refused the credential for a reason other than its expiry. A new sign-in would give the same credential. The log tells the reason. |
| A page answers 503 | EHOS cannot renew an expired credential, or another request of the session renewed for more than 15 seconds. |
| A sign-in in a signed-in browser | The application ends the session that the browser had, and the cookie session starts empty. |

A navigation is a `GET` or `HEAD` request with `sec-fetch-mode: navigate`, or one that accepts
`text/html`. The plug sends it to `/auth/ehos/sign-in?return_to=<path>`. Give the plug
`sign_in_path:` if the routes are not at `/auth/ehos`.

The callback goes back to `return_to` only when it is a path of this application. Otherwise it goes
to `/`.

`EhOsContract.Auth.SignIn.provider/1` tells if the child can sign a person in with what it has. It
refuses a document of EHOS that does not have each of these, and names each item that is missing:

- the `iss` parameter in the authorization response;
- PKCE with `S256`;
- `Ed25519` for the ID tokens;
- `private_key_jwt` for the token endpoint.

It also refuses a document that names `none` or a symmetric algorithm for the ID tokens. The OpenID
Connect library would accept such tokens, and would continue without each of the other items. The
child does not keep a document whose endpoints are not at the origin of the issuer, or that parsers
can read differently. Then nobody can sign in until EHOS gives a correct one, and the log names the
endpoints that the child refused.

## Next steps

- [Call another application as the person](call-another-application.md): the credential of the
  person for another application of the installation.
- [Let a person grant a role](grants.md): invite a person with a role from a page.
- [The credential](credential.md): what `verify/2` checks, and what each refusal means.

## Background

Why the sign-in and the session work this way:
[`docs/adr/browser-session.md`](https://github.com/EmpoweredHouse/eh-os-contract/blob/main/docs/adr/browser-session.md).
