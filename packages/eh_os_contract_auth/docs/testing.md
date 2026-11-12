# Test the application without EHOS

This page tells a developer how to test an application that uses `eh_os_contract_auth`, with no
running EHOS. A test makes its own credentials, checks that each entry point refuses a
credential without the capability, and signs a browser in.

## Prerequisites

- You did the steps of [Get started](getting-started.md). In the test environment, `issuer` and
  `audience` are set, and `EhOsContract.Auth` is in the supervision tree after the repo.
- In `config/test.exs`, `issuer` is an address that does not answer, such as
  `https://ehos.test`. The tests need only the test key of step 2. The key process fetches the
  keys after it starts, and that fetch fails without a real EHOS. The first credential waits until
  that fetch ends, and a fetch can take 5 seconds. Use an address that no DNS resolves, so that
  the fetch ends at once.
- For tests with no network at all, give the child a plug in place of EHOS:
  `{EhOsContract.Auth, plug: {Req.Test, MyApp.Keys}}`. The child takes `plug:` only
  with `pin_keys: true` where the environment of Mix is `:test`, step 1.
- `config :eh_os_contract, authorizer: EhOsContract.Auth` is set, so the engine asks the package
  about each call.
- A test that makes a credential or signs a browser in owns a connection of the Ecto sandbox. These
  functions read and write through the repo of the engine.

## 1. Let the tests trust a test key

> **Put `pin_keys: true` only in `config/test.exs`.** The package trusts the line only where the
> environment of Mix is `:test`, as in `mix test`. If another environment sets the line, the
> children of the package do not start. The package also refuses the line in a release
> (`RELEASE_NAME` or `RELEASE_ROOT` is set) and in a container that EHOS started (`EHOS_ISSUER` or
> `EHOS_AUDIENCE` is set), whatever the environment of Mix is. With the line, code in the tests can
> make the application trust keys and answers that EHOS did not give:
>
> - `EhOsContract.Auth.Keys.pin/2` adds a key;
> - the `plug:` option of the `EhOsContract.Auth` child answers in place of the keys of EHOS;
> - the `plug:` option of the `EhOsContract.Auth.SignIn` child answers in place of the sign-in of EHOS;
> - the `plug:` option of the `EhOsContract.Auth.Workload` child answers in place of the API of EHOS;
> - `sign_in/3` starts a sign-in stand-in that never calls EHOS;
> - the `Testing` stand-ins answer for EHOS: [Use people, grants and mail where EHOS does not
>   answer](without-ehos.md).

```elixir
# config/test.exs
config :eh_os_contract_auth, pin_keys: true
```

**Result:** the test helpers work. Without the line, `credential/3`, `sign_in/3` and the `Testing`
stand-ins raise `ArgumentError`, and the message tells you to add the line.

## 2. Make a credential

Add `use EhOsContract.Auth.Testing` to the test module. Then make a credential for a subject, with
its capabilities:

```elixir
use EhOsContract.Auth.Testing

token = credential("u-anna", ["clinic.record_payment"])
```

For a scoped capability, give its values as the third argument, as the `scp` claim carries them:
`%{"clinic.open_visits" => %{"clinic_id" => ["7"]}}`. EHOS does not issue scope values yet. So
outside a test, each call to a scoped capability through EHOS gets `{:error, :unscoped_grant}`:
[The application manifest](manifest.md#offers).

**Result:** `token` is a credential that `verify/2` accepts:

- The package signs it with an Ed25519 key that it makes one time for each test run.
- The package pins the key in the running key process. The key stays through each refresh, and the
  package never writes it to the key table.
- The claims are those of EHOS: the configured `iss` and `aud`, and 10 minutes of life from
  `EhOsContract.Clock.now/0`.

Send the token to the entry point as a client does, such as in an `authorization: Bearer` header.

## 3. Check that each entry point refuses a credential without the capability

The engine does not know the entry points of the host: an HTTP route, a LiveView event, a job that
gets a credential. So give the check a function for each capability that your contracts declare.
The function calls your entry point with the token:

```elixir
test "every entry point refuses a credential without the capability" do
  assert_every_entry_refuses([Clinic.Contracts.VisitSettlement], %{
    "clinic.record_payment" => fn token ->
      build_conn()
      |> put_req_header("authorization", "Bearer " <> token)
      |> put_req_header("content-type", "application/json")
      |> post("/api/commands/clinic.record_payment", ~s({"visit_id": "visit-anna"}))
    end
    # ... one entry for each capability that the contracts declare
  })
end
```

For each capability, the check calls its function with a credential that grants each other
capability. Then it asserts two things:

- `eh_os_contract_auth_decisions` has one `refused` row with `missing_capability` for that
  credential;
- the number of rows in the log of the engine and in `eh_os_contract_commands` did not change. The
  check counts the rows: it does not compare their content.

**Result:** the test passes when each entry point refuses. The check also fails in these cases:

- a capability that the contracts declare has no entry;
- an entry names a capability that the contracts do not declare.

So the test fails when a contract in its list gets a capability without an entry.

A capability `<name>.subscribe`, which a contract makes for each event that it takes from another
application, needs no entry. The check fails on an entry for it, because it is the capability of
the application, not of a person.

The check proves that each entry point refuses. It does not prove that each path into the domain
goes through an entry point.

## 4. Sign a browser in

To test a page behind `EhOsContract.Auth.Session`, sign a browser in without EHOS:

```elixir
token = sign_in("u-anna", ["clinic.record_payment"])

conn =
  build_conn()
  |> Plug.Test.init_test_session(%{EhOsContract.Auth.Session.session_key() => token})
  |> get("/visits/7")
```

**Result:** the session plug lets the request through. `EhOsContract.Auth.Session.actor/2` gives the
actor of a credential that `credential/3` made. `sign_in/3` writes the session row that a sign-in
through EHOS writes.

To sign the browser out, call `sign_out/1`:

```elixir
:ok = sign_out(token)
```

**Result:** the session plug treats the browser as signed out. It redirects a page to the sign-in,
and answers 401 to other requests.

If no `EhOsContract.Auth.SignIn` child runs, `sign_in/3` starts a stand-in under its name. The
stand-in never calls EHOS, and keeps the name until the test run ends. So `config/test.exs` needs no
`sign_in:`. If a test starts a sign-in child of its own, give the child another `name:`, and pass
that name to `sign_in/3` as `sign_in:`.

## 5. Give the answers of EHOS for people, grants and mail

Configure the three `Testing` stand-ins in `config/test.exs`:

```elixir
config :eh_os_contract_auth,
  pin_keys: true,
  people_directory: EhOsContract.Auth.Testing.People,
  granter: EhOsContract.Auth.Testing.Grants,
  mail_sender: EhOsContract.Auth.Testing.Mail
```

Then a test tells whom EHOS knows and what it answers, and sees the mail that the application asks
to send:

```elixir
# EHOS knows Ada; or answers as EHOS that has not agreed
stub_people([%{id: "6f1c0a1e-0000-4000-8000-000000000001", email: "ada@example.com", name: "Ada"}])
stub_people({:error, :not_agreed})

stub_grants({:error, :beyond_rule})
stub_mail({:error, :not_agreed})

# the code under test sends mail, as the application does, such as through
# EhOsContract.Auth.Mail.deliver/1; then:
assert_received {:ehos_mail, message}
assert message[:to] == [{:person, "6f1c0a1e-0000-4000-8000-000000000001"}]
```

**Result:** a stub holds for the test and for the processes that it starts, a LiveView or a task
too. It does not hold for another test, so the tests stay `async: true`. [Use people, grants and
mail where EHOS does not answer](without-ehos.md) tells what each stand-in answers without a stub.

If you use Mox or Hammox, you can use mocks in place of the `Testing` stand-ins:

1. `defmock` the three behaviours: `EhOsContract.Auth.People.Directory`,
   `EhOsContract.Auth.Grants.Granter` and `EhOsContract.Auth.Mail.Sender`.
2. `stub_with/2` each mock with `EhOsContract.Auth.People.Directory.Static`,
   `EhOsContract.Auth.Grants.Local` and `EhOsContract.Auth.Mail.Local`.

The callbacks use the types of `People`, `Grants` and `Mail`. So a Hammox mock refuses an answer that
EHOS never gives, such as `{:error, :timeout}`. The tests of the package hold each implementation
that it ships to those types.

## What can go wrong

| What you see | Cause and fix |
| --- | --- |
| `ArgumentError` that tells you to set `pin_keys: true` | `config/test.exs` does not have the line of step 1. Add it. |
| `ArgumentError`: `pin_keys: true is set where no test runs` | The line of step 1 is in a file that another environment or a release reads. Move it to `config/test.exs`. If the message names `RELEASE_NAME`, `RELEASE_ROOT`, `EHOS_ISSUER` or `EHOS_AUDIENCE`, remove that variable from the environment of `mix test`. |
| `ArgumentError`: the key process is not running | `EhOsContract.Auth` is not in the supervision tree of the test environment. Add it after the repo. |
| `assert_every_entry_refuses/3` finds no `refused` row | The entry point does not call `EhOsContract.dispatch/3` or `EhOsContract.query/3`, or the authorizer is not `EhOsContract.Auth`. |
| A stub has no effect | The stub was made in `setup_all`, which runs in another process. Make it in the test or in `setup`. |
| `:ehos_unavailable`, or the session plug answers 503 | The stand-in of the sign-in cannot renew. The test moved `EhOsContract.Clock` past the 10 minutes of the credential, or asked `Session.credential/3` for another application. |

## Next steps

- [Use people, grants and mail where EHOS does not answer](without-ehos.md): the stand-ins for
  development and tests.
- [The credential](credential.md): what `verify/2` checks, and each refusal.
- [Sign people in through EHOS](sign-in.md): what a sign-in through EHOS does, which `sign_in/3`
  copies.

<!-- Decisions behind this page:
#560, #591: pin_keys is trusted only where Mix's environment is :test, and stops the boot anywhere
else. #620: and never in a release or a container EHOS started, whatever Mix's environment is.
-->
