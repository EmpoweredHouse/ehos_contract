# Read the people of the company

This page tells a developer how the application reads the people of the company from EHOS. A form
can then offer a list of employees, instead of a text field for a name. The application reads the
people as itself, not as a signed-in person.

## Prerequisites

- You did the steps of [Get started](getting-started.md).
- Someone who manages people in EHOS agrees that the application reads them, for each environment.
  Until then, EHOS refuses each call.

## 1. Ask for the people in `ehos.yaml`

Add `needs.people` to the `ehos.yaml` of the application, at `ehos.yaml/v3` or later:

```yaml
schema: ehos.yaml/v3
needs:
  people: read
```

**Result:** EHOS gives the workload `EHOS_CLIENT_ID` and `EHOS_CLIENT_KEY_FILE`, also when the
application does not sign people in. The request grants nothing. EHOS answers only after someone who
manages people agrees.

## 2. Configure the credential of the application

Where EHOS gives the two variables, map them to `workload:`, and add `EhOsContract.Auth.Workload`
to the supervision tree:

```elixir
# config/runtime.exs, beside issuer:
if client_id = System.get_env("EHOS_CLIENT_ID") do
  config :eh_os_contract_auth,
    workload: [
      client_id: client_id,
      client_key_file: System.fetch_env!("EHOS_CLIENT_KEY_FILE")
    ]
end

# the supervision tree
workload =
  if Application.get_env(:eh_os_contract_auth, :workload),
    do: [EhOsContract.Auth.Workload],
    else: []

children = [MyApp.Repo, EhOsContract, EhOsContract.Auth] ++ workload
```

Without `workload:`, the child refuses to start. In development, in tests, and in a release without
EHOS, nothing is configured. The pages then get the answers of [Use people, grants and mail where
EHOS does not answer](without-ehos.md).

If EHOS uses a certificate authority of its own, give its file to this child too:
`{EhOsContract.Auth.Workload, cacertfile: ca}`.

`EhOsContract.Auth.Workload` holds the credential of the application. The people and
[mail](mail.md) use the same credential.

The child refuses to start, and the boot of the host stops, in each of these cases:

- `workload:` is missing, empty, or has a key other than `client_id` and `client_key_file`.
- The issuer is not `https://<host>[:port]` alone.
- `client_id` is not a string with text.
- The key file is not the one private Ed25519 JWK that EHOS gives.

`config :eh_os_contract_auth, :people` and the child `EhOsContract.Auth.People` are the older names
of this configuration and this child. If you keep `people:`, check that key in the condition. They still start the process, with the name
`EhOsContract.Auth.Workload`, and log a warning. If you configure `:workload` and `:people`, the
child refuses to start.

**Result:** the child runs. It fetches nothing at start, so the host starts also while EHOS is down.

## 3. Read the people

On a page, ask `EhOsContract.Auth.People.directory/0` for the people:

```elixir
directory = EhOsContract.Auth.People.directory()

{:ok, %{people: people, next: next}} = directory.list(q: "ad", limit: 50)
# next is nil on the last page
if next do
  {:ok, %{people: more, next: _}} = directory.list(after: next)
end

{:ok, person} = directory.get(id)
# %EhOsContract.Auth.People.Person{id: "6f1c…", email: "ada@example.com", name: "Ada Lovelace", state: :joined}
```

`directory/0` gives `EhOsContract.Auth.People` where `workload:` is configured. Elsewhere, it gives
a module that does not call EHOS: [Use people, grants and mail where EHOS does
not answer](without-ehos.md).

`list/1` takes these options:

| Option | Value |
| --- | --- |
| `q:` | the start of the name or the email, 2048 bytes or fewer |
| `state:` | `:invited`, `:joined`, or a list of both; both when not given |
| `limit:` | from 1 to 500 people on a page |
| `after:` | the `next` of the page before, alone: it holds the `q:`, `state:` and `limit:` of the first page; `nil` raises |

EHOS gives the people in the order of their emails, and never gives a disabled person in a list.
`get/1` also gives a disabled person, with `state: :disabled`.

An option that EHOS would refuse raises `ArgumentError` before the package asks EHOS. A changed
`after:` value raises too.

To read every person at one time, use `EhOsContract.Auth.People.all/1`. It reads pages of 500, and
answers `{:error, :too_many}` if there are more people than its `max:`, 10,000 by default. It
never gives a part of the list. It can make 21 calls one after another, so do not use it in a
request that a person waits for.

**Result:** `people` is a list of `EhOsContract.Auth.People.Person`, each with `id`, `email`, `name`
and `state`.

Keep the `id` of a person, never the email. The `id` never changes, and it is the `sub` that the
sign-in gives for the same person. An email can change, and EHOS can later give it to another
person. On the page, show the email beside the name, because 2 people can have the same name.

## How does the application get its credential?

The workload process gets the credential at the token endpoint of EHOS, with the client credentials
grant, and signs the request with the client key. EHOS issues the credential for 10 minutes.

- It keeps the credential until 60 seconds before it expires, and gets a new one in the background.
  If that fails, it keeps the credential that is still valid.
- Callers that need a credential at the same time wait for one request. A caller waits 12 seconds or
  less.
- After EHOS refuses or does not answer, the process gives the same answer for 5 seconds. It does
  not ask EHOS again in that time.
- If EHOS refuses the credential with 401, the call gets a new credential and tries one more time.

Each request to EHOS uses https, follows no redirect, reads 1 MiB or less, and stops after 10
seconds. A call answers in about 40 seconds or less when EHOS does not answer, and at once when EHOS
refuses.

The package keeps no copy of the people. When EHOS cannot answer, the call fails and the page tells
the person. The rest of the application continues to work.

## What can go wrong

A call that gives no people tells why, so that the page can tell the person in words. A call never
raises for what EHOS does, also when the workload process does not run.

| Error | When |
| --- | --- |
| `:not_agreed` | Nobody who manages people agreed for this environment, the agreement was withdrawn, or the deployment does not ask for the people now |
| `:not_found` | `get/1` of an id that names nobody. An id that is not a UUID gets this answer without a request to EHOS. |
| `:not_asked` | The deployment asks for neither the people nor mail. A deployment that asks only for mail gets `:not_agreed`. |
| `:rate_limited` | The limits of EHOS: 60 credentials a minute, 600 calls a minute |
| `:unavailable` | EHOS cannot be reached, fails, refuses the client in another way, or gives an answer that it never gives. Also when the workload process does not run, or gives no credential in 12 seconds. |

## Next steps

- [Send mail](mail.md): send mail to these people with the same credential.
- [Let a person grant a role](grants.md): invite a person with a role from a page.
- [Use people, grants and mail where EHOS does not answer](without-ehos.md): the stand-ins for
  development and tests.
