# The credential

This page tells what a credential of EHOS holds, what `EhOsContract.Auth.verify/2` checks, and
what each refusal means, in a function call and over HTTP. It is for a developer who accepts calls
with a credential, and for a reviewer who must know what the package trusts. A *credential* is a
signed token that EHOS issues to a person or a system, for one application. The
[glossary of the engine](https://github.com/EmpoweredHouse/eh-os-contract/blob/main/packages/eh_os_contract/docs/glossary.md)
defines the words *actor*, *capability* and *scope*.

## What does a credential hold?

A credential is a JWT. EHOS signs it with Ed25519, and it lives 10 minutes. The grants travel in
the credential: the application stores no grant, and does not ask EHOS about one.

The header:

| Field | Value |
| --- | --- |
| `alg` | `"Ed25519"`, and nothing else |
| `kid` | the RFC 7638 thumbprint of the key that signed it |

The claims that EHOS writes:

| Claim | What it holds | Checked by `verify/2` |
| --- | --- | --- |
| `iss` | the issuer: the public address of EHOS | equal to the configured `issuer` |
| `sub` | who the credential is for: an opaque identifier | a string that is not blank and has no NUL |
| `aud` | `<application>/<environment>`, as one string | equal to the configured `audience` |
| `iat` | when EHOS issued it | not checked |
| `exp` | when it expires | later than now, and 15 minutes from now or sooner |
| `jti` | an identifier of this credential | not checked |
| `cap` | the capabilities, sorted | a list of strings |
| `scp` | for each scoped capability, the values that it grants, by field | a map of capability to `%{field => [value]}`, all strings, or no claim |

Example claims, with `iss`, `iat`, `exp` and `jti` left out:

```json
{"sub": "u-81", "aud": "clinic/production", "cap": ["clinic.open_visits_for_clinic"],
 "scp": {"clinic.open_visits_for_clinic": {"clinic_id": ["7"]}}}
```

`verify/2` does not read `iat` or `jti`. It keeps no list of credentials that it saw, so a
credential works until it expires, each time that it is sent.

The application does not ask EHOS if a grant is still valid. If EHOS removes a role, or a
credential leaks, the credential works until its `exp`: 15 minutes or less.

## What does `verify/2` give?

An accepted credential becomes an `EhOsContract.Actor`:

| Field of the actor | Value |
| --- | --- |
| `kind` | `:credential` |
| `subject` | `sub`, as the credential carries it |
| `capabilities` | the strings of `cap` |
| `scopes` | `scp`, as the credential carries it, or `%{}` |

`verify/2` takes three options. Each one replaces the configuration for one call:

| Option | Default |
| --- | --- |
| `:issuer` | `config :eh_os_contract_auth, :issuer` |
| `:audience` | `config :eh_os_contract_auth, :audience` |
| `:keys` | `EhOsContract.Auth.Keys`, the name of the key process |

## When does `verify/2` refuse a credential?

`verify/2` makes its checks in this order, and returns the first refusal:

| Order | The check fails when | Refusal |
| --- | --- | --- |
| 1 | the token is not a JWT, the header has `crit` or no `kid`, or `alg` is anything but `"Ed25519"`, `"EdDSA"` included | `:bad_signature` |
| 2 | the application holds no key: its table had none or could not be read, and no fetch succeeded, or the key process does not run | `:no_keys` |
| 2 | no key in force has the thumbprint of `kid` | `:unknown_key` |
| 3 | the signature does not match the key | `:bad_signature` |
| 4 | `iss` is not the configured issuer | `:wrong_issuer` |
| 5 | `aud` is not exactly the configured audience, as one string | `:wrong_audience` |
| 6 | `exp` is not later than now, or is missing | `:expired` |
| 7 | `exp` is more than 15 minutes from now | `:bad_signature` |
| 8 | `sub` is not a string, is blank or has a NUL | `:bad_signature` |
| 8 | `cap` is not a list of strings, or `scp` has another form | `:bad_signature` |

- **An unknown `kid` starts an early fetch of the keys**, at most one time in 30 seconds. Then
  `verify/2` looks for the key again. A credential that EHOS signed with a new key thus gets in
  without a restart.
- **Each fetch closes the window for 30 seconds**: the scheduled fetch, an early fetch and a failed
  fetch. In that window, a credential with a key that the application does not hold yet gets
  `:unknown_key`. After the window, the next unknown `kid` starts an early fetch again.
- **A credential that claims a longer life is not one that EHOS issues**, whoever signed it. The
  limit is the 10 minutes of EHOS, and 5 minutes for clocks that do not agree. So a key that
  leaked cannot make a credential that works for a year.
- **`:bad_signature` covers each credential that is not in the form that EHOS signs**, whatever its
  bytes say.
- **`EhOsContract.Clock` gives the time.** A test moves the time with `EhOsContract.Clock.at/2`.

## What does the plug answer over HTTP?

`EhOsContract.Auth.Plug` reads the header `authorization: Bearer <credential>`. The word `Bearer`
can have any case. The plug gives the token to `verify/2`:

| Request | Status | `www-authenticate` | Body |
| --- | --- | --- | --- |
| `verify/2` accepts the credential | the request goes on, with `conn.assigns.eh_os_contract_actor` | — | — |
| no `authorization` header, not a bearer one, or an empty token | 401 | `Bearer` | `{"error": "no_credential"}` |
| `verify/2` refuses the credential | 401 | `Bearer error="invalid_token"` | `{"error": "<refusal>"}`, such as `{"error": "expired"}` |

- **The plug logs each refused credential with its refusal**, at the level `info`. The log has
  nothing of the token.
- **A refused credential gets no decision row.** It names nobody to record, and a flood of them
  would fill the table. The rows are the decisions about actors that verified: [How is each
  decision recorded?](decisions.md)
- **The plug takes the options of `verify/2`**: `:issuer`, `:audience` and `:keys`. It raises
  `ArgumentError` for each other option, because a misspelt option would have no effect.

## Next steps

- [How is each decision recorded?](decisions.md): what the package writes for each verified actor.
- [How is a call authorized?](https://github.com/EmpoweredHouse/eh-os-contract/blob/main/packages/eh_os_contract/docs/authorization.md):
  how the engine checks the capabilities and the scopes of the actor, and the limits of the check.
- [Where the keys come from](../README.md#where-the-keys-come-from-and-what-to-configure-at-integration):
  how the key process fetches, keeps and rotates the keys.

<!-- Decisions behind this page:
EHOS's decisions this package follows: the credential, a ten-minute Ed25519 JWT with the key's
thumbprint as kid; the claims cap and scp, scope values carried in the credential.
-->
