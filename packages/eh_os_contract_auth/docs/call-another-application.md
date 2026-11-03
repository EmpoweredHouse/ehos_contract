# Call another application as the person

This page tells a developer how a page of the application calls another application of the
installation as the signed-in person. The other application then knows who the person is, and
decides with their roles there.

## Prerequisites

- People sign in to the application: [Sign people in through EHOS](sign-in.md).
- The `sign_in` key of `ehos.yaml` names the other application in `applications`. EHOS then gives
  its name and address in `EHOS_SIGN_IN_APPLICATIONS`, and `sign_in: [applications: ...]` holds
  them.

## 1. Get the credential of the person for the other application

Give `EhOsContract.Auth.Session.credential/3` the connection and the name of the application:

```elixir
{:ok, token} = EhOsContract.Auth.Session.credential(conn, "ledger")
```

A LiveView gives the session map that `mount/3` gets instead of `conn`.

**Result:** `token` is the credential that EHOS issued to the person for the address of that
application. The package renews it as it renews the credential for this application: when it
expires in 30 seconds or less, under the same lease. The package does not verify it. Its `aud` is
the other application, which verifies it.

## 2. Send the call from the server

Send the credential as a bearer token:

```elixir
Req.get!("https://ledger.production.ehos.localhost/visits", auth: {:bearer, token})
```

Keep the credential on the server. Do not put it in the assigns of a LiveView or in a page. The
browser then gets it, and the session otherwise keeps each token of EHOS away from the browser.

**Result:** the other application gets the call as the person.

## What can go wrong

| Answer | When | What to do |
| --- | --- | --- |
| `ArgumentError` raised | `applications` has no such name | Correct the name in the code. A new sign-in does not help. |
| `{:error, :refused}` | EHOS refused the person a credential there (`invalid_target`): they have no role there, or the application is outside the set that the sign-in granted | Tell the person. The package remembers the refusal for 10 minutes, the life of a credential, and does not ask EHOS again until then. |
| `{:error, :signed_out}` | The session names nobody, or ended at renewal | Send the person to sign in. |
| `{:error, :ehos_unavailable}` | EHOS cannot renew an expired credential | Try again later. |
| `{:error, :renewal_busy}` | Another request of the session renewed for more than 15 seconds | Try again. |

After `:refused`, the package keeps the refresh token. The session continues for this application
and for each other application.

## Next steps

- [Sign people in through EHOS](sign-in.md): the session, its renewal and its limits.
- [The credential](credential.md): what the other application checks when it verifies the
  credential.
