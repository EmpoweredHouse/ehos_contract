# Configure the package

This page lists what `eh_os_contract_auth` reads: its configuration, the options of its child, and
the environment variables that EHOS gives the workload. It is for a developer who deploys an
application on EHOS. The [glossary of the engine](https://github.com/EmpoweredHouse/eh-os-contract/blob/main/packages/eh_os_contract/docs/glossary.md)
defines each word of the contract language that this page uses. [Get started](getting-started.md) shows the configuration one time, step by
step.

## The configuration

| Key | Required | What it holds |
| --- | --- | --- |
| `issuer` | yes | the public address of EHOS, exactly the `iss` that EHOS writes in each credential |
| `audience` | yes | `<application>/<environment>`, exactly the `aud` that EHOS issues for this application |
| `jwks_url` | no | the address of the keys of EHOS. The default is `<issuer>/.well-known/jwks.json`. |
| `sign_in` | no | the sign-in of people through EHOS: [Sign people in through EHOS](sign-in.md) |
| `workload` | no | the client of the application, for the people and for mail: [Read the people of the company](people.md) |
| `people_directory`, `granter`, `mail_sender` | no | a stand-in for EHOS: [Use people, grants and mail where EHOS does not answer](without-ehos.md) |
| `pin_keys` | no | `true` lets code trust keys and answers that EHOS did not give. Set it only in `config/test.exs`: [Test the application without EHOS](testing.md) |

```elixir
config :eh_os_contract_auth,
  issuer: "https://ehos.example.com",
  audience: "clinic/production"
```

### The rules of each address

`issuer` and `jwks_url` must be addresses that each parser reads the same way:

- the scheme is `https`. Plain `http` is allowed only for `localhost`, `127.0.0.1` and `::1`;
- the host is in lowercase;
- the address has no user, no query and no fragment;
- the address reads back exactly as you wrote it.

`issuer` also has no path and no trailing slash. `jwks_url` can have a path.

The sign-in has stricter rules for its addresses: `https` only, also on loopback, and no port for
the address of an application. [Sign people in through EHOS](sign-in.md) gives them.

These rules stop an address that two parsers read differently. Example:
`http://evil.example\@localhost` could pass as `localhost`, but EHOS and a browser read its host as
`evil.example`. EHOS keeps the same rules for its issuer. The package checks `issuer` also when
`jwks_url` is set, because the `iss` of each credential must be equal to it.

### The rules of `audience`

The application part of `audience` is the name of the application in EHOS:

- Both parts are present: `clinic/production`, not `clinic`.
- The application part is a name that EHOS takes: lowercase letters, digits and dashes. It starts
  with a letter, does not end with a dash, has 63 characters or fewer, and is not `ehos`.
- The application part is exactly the `name:` of one domain with contracts. `audience:
  "my-shop/prod"` matches `name: :"my-shop"`, not `name: :my_shop`.
- Another domain with contracts in the same application declares no `publish`.

The reason: each name that the application publishes, and each contract id that it stores, starts
with the `name:` of its domain. EHOS lets an application publish only under the name that it
registered. An application without contracts publishes nothing, so the package does not check its
`audience` against a domain.

## The options of the child

`EhOsContract.Auth` is the child that starts the key process, `EhOsContract.Auth.Keys`:

```elixir
children = [MyApp.Repo, EhOsContract, {EhOsContract.Auth, cacertfile: "/etc/ehos/ca.pem"}]
```

| Option | Default | What it does |
| --- | --- | --- |
| `cacertfile:` | the certificate authorities of the system | a PEM file with the authority that the certificate of EHOS is checked against |
| `cacerts:` | — | the same authority as DER certificates, in place of a file |
| `name:` | `EhOsContract.Auth.Keys` | the name of the key process. Give the same name as `keys:` to `verify/2` and to the plug. |
| `repo:` | `config :eh_os_contract, :repo` | the repo of the key table |
| `refresh_every:` | 5 minutes | the time between two fetches, in milliseconds, 5000 or more |
| `refetch_at_most_every:` | 30 seconds | the shortest time between two early fetches, in milliseconds, 5000 or more |
| `plug:` | — | a plug that answers in place of EHOS, for a test. The child takes it only with `pin_keys: true`. |
| `clock:` | the monotonic clock | a function that gives the time, in milliseconds, for the limit of the early fetch, for a test |

The child takes no other option. The package then cannot weaken the fetch of the keys:

- The fetch follows no redirect, and is not tried again.
- It reads 64 KB or less.
- It waits 2 seconds to connect, and 3 seconds for each part of the answer.
- It stops after 5 seconds in all, and counts as a failed fetch.
- It always checks the certificate of EHOS. The package cannot turn the check off.
- It cannot go through a proxy, and cannot send a client certificate.

[Where do the keys come from?](keys.md) tells why each limit is there.

> **Keep each option that changes where a request goes, or what it sends, out of `config :req,
> default_options`.** Req adds the global options to the fetch of the keys. The package sets the
> connection with its authority, the timeouts, the retries, the redirects and the body. Its options
> replace the same global options. Each other global option gets to the fetch. Examples:
>
> - `plug:`, `adapter:` or `plugins:` can replace the answer, so the keys come from it;
> - `unix_socket:` or `finch_request:` changes where the request goes;
> - `auth:`, `headers:`, `params:` or `aws_sigv4:` goes to EHOS;
> - `finch:` makes each fetch fail, because the package always sets the connection.

### What stops the application at start

The child checks its configuration when the supervisor reads its child list. The application does
not start, and the message tells what to fix, in these cases:

- `issuer` or `audience` is missing;
- `issuer` or `jwks_url` breaks the rules of each address;
- `audience` breaks its rules;
- the child gets an option that it does not take;
- the child gets `url:`. The address of the keys comes only from the configuration;
- `refresh_every:` or `refetch_at_most_every:` is less than 5000;
- the child gets `plug:` without `pin_keys: true`;
- the domain of a contract is not loaded, so the package cannot compare its name.

If EHOS does not answer, the application starts with the keys in its table. [Where do the keys come
from?](keys.md) tells what it accepts then.

## The environment that EHOS gives the workload

EHOS starts the workload with its settings in environment variables. The package reads only
`EHOS_EGRESS_PROXY`, `NO_PROXY` and `no_proxy` itself, at each call through
`EhOsContract.Auth.Egress`. The fetch of the keys reads no variable, and uses no proxy. The host
reads the other variables in `config/runtime.exs` and in its supervision tree. The sign-in also
needs `PHX_HOST` and `SECRET_KEY_BASE`, which Phoenix uses: [Sign people in through
EHOS](sign-in.md).

| Variable | When EHOS gives it | Where the host puts it |
| --- | --- | --- |
| `EHOS_ISSUER` | always | `issuer` |
| `EHOS_AUDIENCE` | always | `audience` |
| `EHOS_CA_FILE` | when the installation uses a certificate authority of its own | `cacertfile:` of `EhOsContract.Auth`, and of the `sign_in:` and `workload:` configuration. Without it, their calls to EHOS fail. |
| `EHOS_CLIENT_ID`, `EHOS_CLIENT_KEY_FILE` | to the container that serves, when `ehos.yaml` has `sign_in`, `needs.people` or `needs.mail` | `sign_in:` or `workload:` |
| `EHOS_SIGN_IN_APPLICATIONS` | to the container that serves, when `ehos.yaml` has `sign_in` | `sign_in:`: [Sign people in through EHOS](sign-in.md) |
| `EHOS_SIGN_IN_ABSOLUTE` | always, to each container | `sign_in:`, if the application signs people in |
| `EHOS_SIGN_IN_IDLE` | always, to each container | nowhere. EHOS alone uses it. |
| `EHOS_EGRESS_PROXY`, `NO_PROXY`, `no_proxy` | when `ehos.yaml` has `needs.egress` | nowhere. `EhOsContract.Auth.Egress` reads them: [Call a host outside the installation](egress.md) |
| `HTTPS_PROXY`, `https_proxy` | when `ehos.yaml` has `needs.egress` | nowhere. The package does not read them. Other HTTP clients of the application can. |

Only `EHOS_SIGN_IN_APPLICATIONS` tells that the application signs people in. An application that
only reads the people or sends mail maps the client to `workload:`.

```elixir
# config/runtime.exs
if config_env() == :prod do
  config :eh_os_contract_auth,
    issuer: System.fetch_env!("EHOS_ISSUER"),
    audience: System.fetch_env!("EHOS_AUDIENCE")
end
```

```elixir
# the supervision tree
auth = if ca = System.get_env("EHOS_CA_FILE"), do: [cacertfile: ca], else: []
children = [MyApp.Repo, EhOsContract, {EhOsContract.Auth, auth}]
```

## Next steps

- [Where do the keys come from?](keys.md): how the key process fetches, keeps and rotates the keys
  of EHOS.
- [The application manifest](manifest.md): what `ehos.yaml` asks of EHOS, and so which variables
  the workload gets.
- [Test the application without EHOS](testing.md): the configuration of a test.

<!-- Decisions behind this page:
EHOS's decisions this package follows:
- EHOS hands the workload its settings in the environment;
- the client key as a JWK, addresses as exact strings, an application's address as resource.
#89: the issuer and every address read alike by every parser.
#180: the application of the audience is a domain's name.
-->
