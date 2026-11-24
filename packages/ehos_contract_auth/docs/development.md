# Sign a person in on a developer's computer

This page tells a developer how to open the pages of the application as a person with a role, on
their own computer, where no EHOS runs. Without EHOS, nobody can sign in through EHOS, so each page
behind `EhosContract.Auth.Session` sends the browser to a sign-in that answers 503. In the
development mode, the application signs the credential itself, with a key that it makes when it
starts. The [glossary of the engine](https://github.com/EmpoweredHouse/eh-os-contract/blob/main/packages/ehos_contract/docs/glossary.md)
defines the words of the contract language that this page uses.

The credential goes through the same checks as a credential from EHOS: `EhosContract.Auth.verify/2`,
`EhosContract.Auth.Session`, `EhosContract.Auth.Plug` and the check of the engine. A capability
that the domain does not grant to the actors that you choose is refused on the computer, as in
production.

## Prerequisites

- You did the steps of [Get started](getting-started.md). In development, `issuer` and `audience`
  are set, and `EhosContract.Auth` is in the supervision tree after the repo.
- In development, `issuer` is the address of a local EHOS, such as `https://ehos.localhost`. The
  mode works when no EHOS answers at that address.
- The pages use `EhosContract.Auth.Session`: [Sign people in through EHOS](sign-in.md).

## 1. Turn the mode on in development

```elixir
# config/dev.exs, and no other file
config :ehos_contract_auth, development: true
```

```elixir
# the supervision tree, after EhosContract.Auth, in each environment
children = [MyApp.Repo, EhosContract, EhosContract.Auth, EhosContract.Auth.Development]
```

Without the line, the `EhosContract.Auth.Development` child starts nothing. So the same list of
children is correct in each environment.

**Result:** `mix phx.server` prints the address of the page with a token:

```text
[ehos_contract_auth] Development sign-in, with a key made at this start:
    http://localhost:4000/dev/sign-in?token=…
  This address is printed once. To see it again while the application runs:
    cat _build/dev/ehos_contract_auth/dev_sign_in
```

The application prints the address 1 time, at start. It also writes the address to the file
`ehos_contract_auth/dev_sign_in` in the build directory of the project, `_build/dev`. To get the
address again, for example after a sign-out or in a new browser, show the file:

```bash
cat _build/dev/ehos_contract_auth/dev_sign_in
```

Only your user can open the directory of the file (mode 0700), and git ignores `_build/`. If the
application cannot write the file, it starts, and the terminal tells you so. Then keep the address
that the terminal shows.

- When the application stops normally, it removes the file. After Ctrl+C and `a`, or a kill, the
  file stays, with a token that does not work. The next start replaces the file.
- A second start of the application in the same project, such as `mix run priv/repo/seeds.exs`
  while `mix phx.server` runs, does not change the file. It prints its own address only. The
  first start keeps the file. On Windows, the second start replaces the file.

To print the full address, give the child the address of the application:
`{EhosContract.Auth.Development, url: "http://localhost:4000"}`.

## 2. Mount the page and the endpoint in the router

```elixir
# the router: Phoenix compiles the `dev_routes` block only in development
if Application.compile_env(:my_app, :dev_routes) do
  scope "/dev" do
    pipe_through :browser
    live_dashboard "/dashboard", metrics: MyAppWeb.Telemetry
  end

  forward "/dev", EhosContract.Auth.Development.Router
end
```

Put the line after the other `/dev` routes of the block. The router answers each path under
`/dev` that reaches it, so a route after the line, such as the dashboard, does not open. Without
the token, that route answers 403, as each request that the router refuses. With the token, it
answers 404. Put the line outside each pipeline: the router fetches the session, checks the token
and the CSRF token of its form, and parses the body itself. Mount it at `/dev`, because
`EhosContract.Auth.Session` sends the browser to `/dev/sign-in`.

The page `/dev/sign-in` lists the actors that the contracts grant capabilities to, and a field for
each scope of those capabilities. Choose one or more actors, give a value for each scope that they
need, and send the form. The router signs the person in, and sends the browser back to the page
that asked for a sign-in.

**Result:** open the address that the terminal shows. After you sign in, the pages behind
`EhosContract.Auth.Session` open with the actor of the credential.

A link to `/auth/ehos/sign-in`, such as the "Sign in" link of a layout, also goes to this page:
`EhosContract.Auth.SignIn.Router` sends the browser to `/dev/sign-in`, with the same `return_to`.
The page opens when the browser opened the address with the token after the last start. After a
restart or a sign-out, the page answers 403: open the address in
`_build/dev/ehos_contract_auth/dev_sign_in` again.

The page links the stylesheet of the application, at `/assets/css/app.css`. A Phoenix 1.8
application serves its CSS at this path in development. If the stylesheet imports the
EmpoweredHouse design system (`ehos_design`), the page uses the fonts, colours, buttons and fields
of the application. If the stylesheet does not exist, the page uses a plain look of its own. To
link another stylesheet, or none, give the router the `stylesheet` option:

```elixir
forward "/dev", EhosContract.Auth.Development.Router, stylesheet: "/assets/app.css"
forward "/dev", EhosContract.Auth.Development.Router, stylesheet: nil
```

The option takes a path of the application only. If the stylesheet has Tailwind but not the
`btn`, `input` and `checkbox` classes of daisyUI, the button and the text fields have no border
and no background: give `stylesheet: nil`. The page has no script. It ignores the theme that the
theme toggle of the application keeps, and uses the colour scheme of the system.

## 3. Get a credential for `curl`

```bash
mix ehos_contract.dev.credential --actor clinic.receptionist --scope clinic_id=clinic-1
```

Run the command in the project of the application, while the application runs. The command reads
the token and the address of the application from `_build/dev/ehos_contract_auth/dev_sign_in`.
To give another token, set it in the environment, not as `--token`. Other users of the computer
can see a command line, and the shell keeps it in its history:

```bash
export EHOS_CONTRACT_DEV_TOKEN=<token>
```

The command asks the running application for the credential, and prints it. The key stays in the
memory of the application.

**Result:** `curl -H "authorization: Bearer <credential>"` reaches the API as that person.

## What does the mode do?

| Part | What it does |
| --- | --- |
| The key | An Ed25519 key, made when the mode starts, and kept only in memory. A restart makes a new key. |
| The credential | It grants the capabilities that the domain grants to the chosen actors. It lives 10 minutes. |
| Renewal | When the credential of a session expires, the mode signs a new one with the same claims. |
| A restart | Each session from before the restart is signed out, and the browser goes to `/dev/sign-in`. The application stops trusting the old key. |
| The token | A random value, made at start and printed. The page and the endpoint need it. |
| The file | The address of the page, with the token, in `_build/dev/ehos_contract_auth/dev_sign_in` while the application runs. Only your user can read it. |

## Who can reach the page?

`EhosContract.Auth.Development.Router` answers a request only when all of these are true. It
answers 403 for each other request.

- The request comes from a loopback address, `127.0.0.0/8` or `::1`. The router reads the address
  of the socket, and also `conn.remote_ip`, which a plug that reads `X-Forwarded-For` sets. The
  address on which the endpoint listens does not change this.
- The `Host` of the request is `localhost`, `127.0.0.1` or `[::1]`. The router reads the header
  that the browser sent, and also `conn.host`. This also refuses a page that DNS rebinding sends
  to `localhost`.
- The request has the token, as the `token` parameter or in the `x-dev-sign-in-token` header. After
  the first request, the session of the browser keeps a hash of the token.

If the browser opens `/dev/sign-in` with the `token` parameter, the router keeps the hash of the
token in the session. Then it sends the browser to the same address without `token`, with each
other parameter. The address bar does not show the token after that. The history of the browser
can still keep the first address, with the token. The browser must keep the cookies of the host
of the page, such as `localhost`: if it does not, the address without the token answers 403.

The form of the page also needs its CSRF token. A form without a valid CSRF token gets 403. If
the router cannot read the query string or the body of a request that passes the checks above, it
answers with the status that Plug gives: for example 400, or 413 when the body is too large.

The router removes each `Access-Control-Allow-` header from the answers of the page and of the
endpoint. It cannot remove the headers of a CORS plug in the endpoint that answers a preflight
`OPTIONS` itself, or that adds its headers when the answer is sent. Keep such a plug off the
`/dev` paths.

## What can go wrong

**The mode refuses to start where EHOS could run the application.** If the line of step 1 is set,
the child raises, and the application does not start, in each of these cases:

- the `:mix` application is not started, no Mix project is loaded, or the environment of Mix is not
  `:dev`;
- `RELEASE_NAME` or `RELEASE_ROOT` is set, as in a release;
- `EHOS_ISSUER` or `EHOS_AUDIENCE` is set, as in each container that EHOS starts;
- `sign_in:`, `workload:` or `people:` is configured.

The message names each case that applies. Remove the line from each file but `config/dev.exs`, and
start the application with `mix phx.server` or `iex -S mix`.

**The application logs a warning about the key set at start.** Without a local EHOS, the
application cannot get the key set from the `issuer`, and logs this:

```text
[warning] ehos_contract_auth could not fetch the key set from https://ehos.localhost/.well-known/jwks.json (…); 0 keys stay in force
[warning] ehos_contract_auth has never seen a key set from https://ehos.localhost/.well-known/jwks.json; until a fetch succeeds, it refuses every credential but those of the development mode, once EhosContract.Auth.Development has started
```

This is correct. The mode signs its credentials with its own key, and the application trusts that
key. Each five minutes, the application tries again, and logs the first line again.

**The mode does not trust another key.** `EhosContract.Auth.Keys.pin/2` admits only the key of the
mode, after the mode starts. `pin_keys: true` does not start the mode. The mode does not let the
`Testing` stand-ins or a `plug:` option answer for EHOS.

**A credential of the mode is not a credential of EHOS.** Another application does not trust the
key of the mode, and refuses the credential. OpenID Connect, a sign-out at EHOS, a real grant and a
real message do not occur. Check them with EHOS before a pull request. For people, grants and mail
in development: [Use people, grants and mail where EHOS does not answer](without-ehos.md).

## Next steps

- [Use people, grants and mail where EHOS does not answer](without-ehos.md): the stand-ins for
  development.
- [Test the application without EHOS](testing.md): credentials and a signed-in browser in a test.
