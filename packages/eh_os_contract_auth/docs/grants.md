# Let a person grant a role

This page tells a developer how a signed-in person grants a role to another person from a page of
the application. For example, an accountant names the representative of a client, and EHOS invites
the representative with the client role and no other role.

The application does not decide if the person can give the role. It sends the request of the
person to EHOS. EHOS
checks the rule against a role that the person holds there, and invites the other person by mail.
EHOS records who granted the role, and through which application.

## Prerequisites

- People sign in to the application: [Sign people in through EHOS](sign-in.md). A grant uses the
  client of the sign-in, and needs no other configuration.
- The installation sends mail. Otherwise, someone who manages people invites the person in the
  console of EHOS.

## 1. Write the rule in the domain

Give the actor of the person who grants `may_grant:`, with the roles that they can give:

```elixir
actor :office_employee, :human, "Office employee", may_grant: [:client]
```

The [domain of the engine](https://github.com/EmpoweredHouse/eh-os-contract/blob/main/packages/eh_os_contract/docs/domain-data.md)
tells the other options of an actor. The compiler refuses `may_grant:` in each of these cases:

- on a system actor;
- when it names the actor itself, a system actor, or an actor that the domain does not declare;
- when it names one actor two times;
- when the rules lead back to an actor.

**Result:** `mix eh_os_contract.manifest` writes the rule into the manifest, at `ehos.manifest/v5`
or later, and EHOS reads it at deployment. In the manifest, a role is `<application>.<actor>`, such
as `clinic.client`. The task refuses an actor with `may_grant:` that holds no capability.

## 2. Grant the role from a page

Record the command of the application first, through `EhOsContract.dispatch/3` or
`EhOsContract.Plug`. The engine then checks that the actor of the person has its capability. Call
EHOS only after that. Each call uses one token request of the application, also when EHOS refuses
it. Put the route behind `protect_from_forgery`, as [Sign people in through EHOS](sign-in.md) tells.

After the application records its own command, ask `EhOsContract.Auth.Grants.granter/0` for the
module that grants, and give it the request of the person:

```elixir
alias EhOsContract.Auth.Grants.Grant

case EhOsContract.Auth.Grants.granter().grant(conn, email: email, name: name, role: "clinic.client") do
  {:ok, %Grant{bound: :before}} -> # "they had this role already"
  {:ok, %Grant{delivery: :mailed}} -> # "we sent them an invitation"
  {:ok, %Grant{delivery: :held}} -> # "they have a recent invitation; it still works"
  {:ok, %Grant{delivery: :none}} -> # "they can use the role at their next sign-in"
  {:error, :beyond_rule} -> # "your role cannot give that role"
  {:error, :unavailable} -> # "we did not invite them; try again"
  {:error, _reason} -> # the table below gives each reason
end
```

`granter/0` gives `EhOsContract.Auth.Grants` where `sign_in:` is configured. Elsewhere, it gives a
module that does not call EHOS: [Use people, grants and mail where EHOS does
not answer](without-ehos.md).

| Option | Value |
| --- | --- |
| `email:` | required: the email of the person |
| `role:` | required: the role, `<application>.<actor>` |
| `name:` | optional: the name of the person, which EHOS keeps only for a person that this grant registers |

The first argument is a `Plug.Conn` with its session fetched, or the session map that the `mount/3`
of a LiveView gets.

**Result:** an `EhOsContract.Auth.Grants.Grant`:

| Field | Value |
| --- | --- |
| `person_id` | the id of the person at EHOS, which never changes; keep it to revoke the role |
| `email` | the email, as EHOS keeps it |
| `state` | `:invited` until the person signs in the first time, then `:joined` |
| `role`, `role_binding_id` | the role, and the id of its role binding |
| `bound` | `:now`, or `:before` when the person had the role already |
| `delivery` | `:mailed`: EHOS sent a sign-in link. `:held`: EHOS sent too many links to this person from this application in the last hour, and the last link still works. `:none`: the person has joined, and signs in as before. |

## 3. Revoke the role

Give the id from the grant and the role:

```elixir
{:ok, %{role_binding_id: _id, role: "clinic.client"}} =
  EhOsContract.Auth.Grants.granter().revoke(conn, person_id, "clinic.client")
```

**Result:** EHOS removes the role binding, and the call gives it.

## How does a call work?

Each call takes the credential of the person for this application from their session. If the
credential is about to expire, the call renews it first. Then the call exchanges it at the token
endpoint of EHOS for another credential. EHOS accepts that credential only on its grant routes, for
1 minute or less.
The call signs the exchange as the client of the sign-in (RFC 8693, `private_key_jwt`). It sends the
grant or the revocation with that credential, and gives the answer of EHOS.

The call does not keep, log or give either credential. Each call exchanges again.

The call is made in the request of the person, and tries nothing again. If it fails, the page tells
the person, and they ask again. A second request is safe:

- a role that the person has already gives `bound: :before`;
- a person who is invited and has not joined gets a new link, which ends the earlier links.

Each request to EHOS uses https, follows no redirect, reads 64 KiB or less, and stops after 10
seconds. A call answers in about 20 seconds or less when EHOS does not answer. If the credential of
the person must be renewed first, the wait for the renewal comes on top.

The grants API of EHOS, `docs/grants-api.md` in eh-os, tells the routes that a call uses.

## What can go wrong

A call never raises for what EHOS does. It raises `ArgumentError` for an argument that is not
correct. Examples are an empty `email:` or `role:`, a string that is not UTF-8, or another option.

| Error | When |
| --- | --- |
| `:beyond_rule` | No role of the person here can give that role |
| `:not_permitted` | EHOS refused to exchange the credential, and tells no more: no role of the person here has a rule, the person is disabled, or the credential is not for this client. Also a person disabled since the exchange. |
| `:unknown_role` | The application has no such role in this environment. A revocation of a role that is not `<application>.<name>` gets this answer without a request to EHOS. |
| `:mail_required` | The installation sends no mail. Someone who manages people invites the person in the console. |
| `:person_disabled` | EHOS disabled the person that the email names |
| `:invalid_email`, `:invalid_name` | EHOS does not keep the email or the name |
| `:already_bound` | Another decision gave the role to the person at the same time. Ask again. |
| `:too_many_invitations` | The application registered its 100 new people of the day |
| `:not_mailed` | EHOS granted the role, but the mail failed. A second grant sends a new link. |
| `:not_found` | A revocation of a role binding that does not exist, or of an environment that EHOS removed. An id that is not a UUID gets this answer without a request to EHOS. |
| `:rate_limited` | The limit of EHOS on its token endpoint or its grant routes |
| `:signed_out` | The session names nobody |
| `:renewal_busy` | Another request of the session is renewing the credential, the credential has too few seconds left for the exchange, or EHOS could not renew it in the last 5 seconds. Ask again. |
| `:unavailable` | EHOS cannot be reached, fails, or gives an answer that it never gives. The log tells which. |

EHOS takes 60 token requests a minute or fewer from the client of the application, and the
credential of the [workload](people.md) counts too. Each grant exchanges one time. So show the grant
only to people whose role can give a role, and limit how often one person can grant.

## Next steps

- [Sign people in through EHOS](sign-in.md): the session that a grant uses.
- [Read the people of the company](people.md): the same `id` for a person.
- [Use people, grants and mail where EHOS does not answer](without-ehos.md): the stand-ins for
  development and tests.
