# Get started with `eh_os_contract_auth`

This page tells you how to connect an application to EHOS one time. You install the package,
configure it, and accept a call with a credential that EHOS issued. It is for a developer who builds an
application on [`eh_os_contract`](https://github.com/EmpoweredHouse/eh-os-contract/tree/main/packages/eh_os_contract).
A *credential* is a signed token that EHOS issues to a person or a system. The
[glossary of the engine](https://github.com/EmpoweredHouse/eh-os-contract/blob/main/packages/eh_os_contract/docs/glossary.md)
defines each word of the contract language that this page uses.

## Before you start

- Your application uses `eh_os_contract`, with its repo configured as `config :eh_os_contract, :repo`.
  The package keeps its tables in that repo.
- Your application has a domain with contracts. The `name:` of that domain is the name of the
  application in EHOS, such as `name: :clinic`. EHOS takes lowercase letters, digits and dashes.
  If the name has a dash, write it as `name: :"my-shop"`.
- You run OTP 27 or later and Elixir 1.18 or later. `oidcc`, the OpenID Connect client that signs
  people in, needs OTP 27.
- You know two values from EHOS:
  - the *issuer*: the public address of EHOS, such as `https://ehos.example.com`;
  - the *audience*: `<application>/<environment>`, such as `clinic/production`.

## 1. Add the dependency

Add the package beside the engine, with the same `git:` and `sparse:` form:

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

Run `mix deps.get`.

**Result:** `mix deps.get` fetches the two packages.

Declare `eh_os_contract` with the same `git:` and `sparse:` as the example. The package declares
the engine in this form, and Mix refuses two different declarations of one dependency.

## 2. Configure the package

Make the package the Authorizer of the engine, and give it the issuer and the audience:

```elixir
# config/config.exs
config :eh_os_contract, authorizer: EhOsContract.Auth

config :eh_os_contract_auth,
  issuer: "https://ehos.example.com",
  # jwks_url: "https://keys.ehos.example.com/jwks.json",
  audience: "clinic/production"
```

- `issuer` must be exactly the `iss` that EHOS writes: `https://<host>[:port]`. The host is in
  lowercase. The address has no path, no trailing slash, no user, no query and no fragment. Plain `http` is allowed
  only for `localhost`, `127.0.0.1` and `::1`.
- `audience` must be exactly the `aud` that EHOS issues for this application.
- Set `jwks_url` only if EHOS publishes its keys at another address. The default is the
  `/.well-known/jwks.json` of the issuer. It has the same rules as `issuer`, but it can have a
  path.

In a release, read the two values from the environment that EHOS gives the workload. The section
"Configuration from EHOS's environment" of the [README](../README.md) tells how.

**Result:** the engine asks `EhOsContract.Auth` about each call with a credential. Nothing runs
yet: the package checks this configuration when its child starts, in step 4.

## 3. Add the migration

Generate a migration, and call the migration of the package from it:

```elixir
defmodule MyApp.Repo.Migrations.AddEhOsContractAuth do
  use Ecto.Migration

  def up, do: EhOsContract.Auth.Migrations.up()
  def down, do: EhOsContract.Auth.Migrations.down()
end
```

Run `mix ecto.migrate`.

**Result:** the database has the tables of the package, at the version of
`EhOsContract.Auth.Migrations.current_version/0`:

- `eh_os_contract_auth_keys`, the public keys of EHOS;
- `eh_os_contract_auth_decisions`, a row for each decision about a credential;
- `eh_os_contract_auth_sessions` and `eh_os_contract_auth_session_credentials`, the people who
  signed in through EHOS.

When a later release of the package raises the version, add a new migration that calls
`up(version: n)`. Do not edit this migration.

## 4. Start the key process

Add `EhOsContract.Auth` to the supervision tree, after the repo and the engine:

```elixir
children = [MyApp.Repo, EhOsContract, EhOsContract.Auth]
```

If EHOS uses a certificate authority of its own, give its file to the child:
`{EhOsContract.Auth, cacertfile: "/etc/ehos/ca.pem"}`. [Where the keys come
from](../README.md#where-the-keys-come-from-and-what-to-configure-at-integration) tells the other
options.

**Result:** the application starts. The key process loads the last keys from its table, then
fetches the keys of EHOS. `EhOsContract.Auth.ready?/0` returns `true` when the process holds a key.

The application does not start, and the message tells what to fix, in these cases among others:

- `issuer` or `audience` is missing;
- `issuer` is not an address that EHOS accepts as its issuer;
- the address of the keys breaks the rules of step 2;
- the child gets an option that it does not take;
- the child gets `url:`: the address of the keys comes only from the configuration;
- `audience` is not `<application>/<environment>` with both parts, or its application part is not
  a name that EHOS gives an application;
- the application part of `audience` is not exactly the `name:` of a domain with contracts;
- another domain with contracts in the application declares a `publish`;
- the domain of a contract is not loaded, so the package cannot compare its name.

If EHOS does not answer, the application starts anyway, with the keys in its table. The table can
have no key, as at the first start, or the application cannot read it. Then the application
refuses each credential with `:no_keys` until a fetch succeeds. It logs this at start.

## 5. Verify a credential

Give `EhOsContract.Auth.verify/2` a credential that EHOS issued for this application:

```elixir
EhOsContract.Auth.verify(token)
#=> {:ok, %EhOsContract.Actor{kind: :credential, subject: "u-81", capabilities: ..., scopes: ...}}
#   | {:error, :expired | :unknown_key | :bad_signature | :wrong_audience | :wrong_issuer | :no_keys}
```

**Result:** `{:ok, actor}` gives the actor of the credential, with the capabilities that EHOS
granted. [The credential](credential.md) tells what each refusal means.

Without EHOS, a test of the application can make a credential with
`EhOsContract.Auth.Testing.credential/3`. The section "In a host's tests" of the
[README](../README.md) tells how.

## 6. Accept calls over HTTP

Put `EhOsContract.Auth.Plug` in front of `EhOsContract.Plug`:

```elixir
# router.ex
pipeline :eh_os_contract_api do
  plug :accepts, ["json"]
  plug EhOsContract.Auth.Plug
end

scope "/api" do
  pipe_through :eh_os_contract_api
  forward "/", EhOsContract.Plug, contracts: [Clinic.Contracts.VisitSettlement]
end
```

**Result:** a request with `authorization: Bearer <credential>` gets to the contract as the actor of
the credential. A request without a credential, or with one that `verify/2` refuses, gets 401. The
package writes a row for each decision about a verified actor: [How is each decision
recorded?](decisions.md)

## Next steps

- [The credential](credential.md): what a credential holds, and when `verify/2` and the plug refuse
  it.
- [How is each decision recorded?](decisions.md): the row for each decision, what it costs, and how
  long to keep it.
- [Sign people in through EHOS](sign-in.md): give the pages of the application a session for each
  person.
- [Accept calls with a credential](https://github.com/EmpoweredHouse/eh-os-contract/blob/main/packages/eh_os_contract/docs/calls.md):
  the routes of `EhOsContract.Plug` and their answers.
- [Generate the application manifest](../README.md#generating-the-ehos-application-manifest): tell
  EHOS what the workload needs and what its contracts offer.
