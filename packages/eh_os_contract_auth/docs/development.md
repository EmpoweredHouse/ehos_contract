# Sign a person in on a developer's computer

This page tells a developer how to open the pages of the application as a person with a role, on
their own computer, where no EHOS runs. Without EHOS, nobody can sign in through EHOS, so each page
behind `EhOsContract.Auth.Session` sends the browser to a sign-in that answers 503. In the
development mode, the application signs the credential itself, with a key that it makes when it
starts. The [glossary of the engine](https://github.com/EmpoweredHouse/eh-os-contract/blob/main/packages/eh_os_contract/docs/glossary.md)
defines the words of the contract language that this page uses.

The credential goes through the same checks as a credential from EHOS: `EhOsContract.Auth.verify/2`,
`EhOsContract.Auth.Session`, `EhOsContract.Auth.Plug` and the check of the engine. A capability
that the domain does not grant to the actors that you choose is refused on the computer, as in
production.

## Prerequisites

- You did the steps of [Get started](getting-started.md). In development, `issuer` and `audience`
  are set, and `EhOsContract.Auth` is in the supervision tree after the repo.
- In development, `issuer` is an address that does not answer, such as `https://ehos.test`.
- The pages use `EhOsContract.Auth.Session`: [Sign people in through EHOS](sign-in.md).

## 1. Turn the mode on in development

```elixir
# config/dev.exs, and no other file
config :eh_os_contract_auth, development: true
```

```elixir
# the supervision tree, after EhOsContract.Auth, in each environment
children = [MyApp.Repo, EhOsContract, EhOsContract.Auth, EhOsContract.Auth.Development]
```

Without the line, the `EhOsContract.Auth.Development` child starts nothing. So the same list of
children is correct in each environment.

**Result:** `mix phx.server` prints the address of the page with a token:

```text
[eh_os_contract_auth] Development sign-in, with a key made at this start:
    http://localhost:4000/dev/sign-in?token=…
```

To print the full address, give the child the address of the application:
`{EhOsContract.Auth.Development, url: "http://localhost:4000"}`.

## 2. Add the page and the endpoint to the router

```elixir
# in the router: Phoenix compiles the `dev_routes` block only in development
if Application.compile_env(:my_app, :dev_routes) do
  scope "/dev" do
    pipe_through [:browser, EhOsContract.Auth.Development.Guard]
    get "/sign-in", MyAppWeb.DevSignInController, :new
    post "/sign-in", MyAppWeb.DevSignInController, :create
  end

  # outside the browser pipeline: the command sends no CSRF token
  forward "/dev/credential", EhOsContract.Auth.Development.Credential
end
```

The page lists the actors that `EhOsContract.Auth.Development.actors/0` gives, and a field for each
scope of their capabilities. When the developer sends the form, the controller signs the person in:

```elixir
def create(conn, %{"subject" => subject, "actors" => actors} = params) do
  case EhOsContract.Auth.Development.sign_in(subject, actors, params["scopes"] || %{}) do
    {:ok, token} ->
      conn
      |> put_session(EhOsContract.Auth.Session.session_key(), token)
      |> redirect(to: params["return_to"] || "/")

    {:error, reason} ->
      conn |> put_flash(:error, inspect(reason)) |> redirect(to: ~p"/dev/sign-in")
  end
end
```

**Result:** the page signs the person in, and the pages behind `EhOsContract.Auth.Session` open
with the actor of the credential.

## 3. Get a credential for `curl`

```bash
mix eh_os_contract.dev.credential --token <token> --actor clinic.receptionist \
  --scope clinic_id=clinic-1
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
| A restart | Each session from before the restart is signed out, and the browser goes to `/dev/sign-in`. |
| The token | A random value, made at start and printed. The page and the endpoint need it. |

## Who can reach the page?

`EhOsContract.Auth.Development.Guard` lets a request through only when all of these are true. It
answers 403 for each other request.

- The request comes from a loopback address, `127.0.0.0/8` or `::1`. The address on which the
  endpoint listens does not change this.
- The `Host` of the request is `localhost`, `127.0.0.1` or `[::1]`. This also refuses a page that
  DNS rebinding sends to `localhost`.
- The request has the token, as the `token` parameter or in the `x-dev-sign-in-token` header. After
  the first request, the session of the browser keeps a hash of the token.

The answers of the page and of the endpoint have no `Access-Control-Allow-` header.

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

**The mode does not trust another key.** `EhOsContract.Auth.Keys.pin/2` admits only the key of the
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
