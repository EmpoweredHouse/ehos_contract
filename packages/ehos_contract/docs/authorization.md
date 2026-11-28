# How is a call authorized?

This page tells how the engine decides who can issue a command, ask a query or record an event. It
tells which names the engine derives from a contract, which calls it checks, and what each answer
writes. It is for a developer who builds an application on the engine, and for a reviewer who must
know how strong the check is. [The glossary](glossary.md) defines each word in italics.

## Who decides what?

Three places each answer one question:

| Where | Question | Example |
| --- | --- | --- |
| The contract | What can be done, and by which actor? | `command :assign_pick_list, by: :lead` |
| The platform that issues the credentials | Which person has which role? | Mira has the role `authorization_example.lead` |
| The application | Does the credential of this call grant this call? | the credential of Mira grants `authorization_example.assign_pick_list` |

The contract names the *actors* of each declaration. The platform grants *roles* to people. The
application checks each call, in its own process, without a call to the platform.

The model is role-based access control. A *credential* carries the capabilities of all the roles of a
person, not the roles. The application never learns the roles of a person. It knows only what the
credential grants. Kubernetes RBAC and cloud IAM use the same shape.

## An example

A warehouse lead assigns pick lists to pickers. A picker reports a shelf that is empty. A lead reads
the open pick lists of a warehouse:

```elixir
defmodule Concepts.Authorization.Domain do
  use EhosContract.Domain, name: :authorization_example, language: :en

  subdomain :core, "Core", type: :core

  context :warehouse, "Warehouse", subdomain: :core

  actor :lead, :human, "Warehouse lead"
  actor :picker, :human, "Picker"
  actor :nightly_import, :system, "Nightly import"
end

defmodule Concepts.Authorization.Contracts.Warehouse do
  use EhosContract.Contract,
    domain: Concepts.Authorization.Domain,
    context: :warehouse,
    id: "authorization_example.warehouse"

  aggregate :pick_list, "Pick list" do
    identity [:warehouse_id, :order_id]

    command :assign_pick_list, "Assign a pick list to a picker",
      by: [:lead, :nightly_import],
      emits: :assigned do
      field :picker_id, :id
    end

    event :assigned, "Pick list assigned" do
      field :picker_id, :id
    end

    event :shelf_found_empty, "Shelf found empty", recorded_by: :picker
  end

  read_model :open_pick_lists, "Open pick lists", projects: [:assigned] do
    field :warehouse_id, :id
    field :order_id, :id
    field :picker_id, :id
  end

  query :open_pick_lists_for_warehouse, "Open pick lists in a warehouse",
    reads: :open_pick_lists,
    by: [:lead] do
    param :warehouse_id, :id
  end
end
```

The sandbox has a longer example of a warehouse: `Fulfilment.Contracts.Warehouse`. There, pickers
also confirm and pack their pick lists.

## Which names does the engine derive from a contract?

The engine derives each name from the contract. Nobody writes the names by hand. So the list that
the platform grants from always agrees with the code. `EhosContract.Model.capabilities/1` returns
them.

- A *capability* is the name of one thing that a person can do: `<domain>.<name>`. There is one
  capability for each command, query and recorded event that a human actor can use. `<domain>` is the
  `name:` of the domain. The example has `authorization_example.assign_pick_list`,
  `authorization_example.open_pick_lists_for_warehouse` and `authorization_example.shelf_found_empty`.
- A *role* is the name of one human actor: `<domain>.<actor>`. The example has
  `authorization_example.lead` and `authorization_example.picker`. A role grants the capability of
  each declaration whose `by:` or `recorded_by:` names the actor.

**A declaration that no human actor can use has no capability.** A command that only a policy
issues is an example. An event that only an integration records is another. No credential can
grant it, also not by mistake. A `:system` actor of the application reaches it without a credential.

**The application has one more capability for each subscribed event that a policy takes:**
`<published name>.subscribe`. The published name loses its version. `subscribe
{:billing, :invoice_issued, 1}` gives `billing.invoice_issued.subscribe`. This capability has no role,
so no person has it. The engine does not check it.

A capability is `<domain>.<name>`. So the name of a command, a query or a recorded event is unique
in the whole domain. The compiler checks this ([`D14`](refusals.md#refusals-d)).

## How does a call get to the application?

![The application sends its capabilities and roles to the platform that issues the credentials, a person signs in and gets a credential, and the application checks that credential against keys in its own database before it writes anything.](img/call-authorization.svg)

1. At deployment, the application sends its capabilities and roles to the platform, in its manifest.
   The engine derives them from the contracts. The task `mix ehos_contract.manifest` of the package
   `ehos_contract_auth` writes the manifest. `EhosContract.Auth.Manifest` tells which version of
   the manifest it writes.
2. A person with a role signs in to the platform. An administrator of the platform gives the role to
   the person first.
3. The platform issues a credential. The credential is a JWT, signed with Ed25519, and valid for 10
   minutes. It carries these claims:
   - `sub`: the subject, an opaque name of the person;
   - `aud`: the audience, the one application, in one place where it runs, that the credential is
     for;
   - `cap`: each capability of each role of the person;
   - `scp`: the values of the scoped capabilities, if the role has values. [Narrow a call to the
     values of a grant](scope.md) tells how a scope uses them.
4. Every 5 minutes, the application fetches the public keys of the platform.
5. The application keeps the keys in its own database. So it verifies a credential without a call to
   the platform, and it keeps working when the platform is down.
6. The person sends a call with the credential. A plug of `ehos_contract_auth` verifies the
   signature, the issuer, the audience and the expiry. Then it builds an `EhosContract.Actor` from the
   claims. If one check fails, the plug answers 401, and nothing asks the Authorizer.
7. Dispatch asks the *Authorizer* if the actor can make the call. If the Authorizer allows it, the
   application decides and writes the events. If not, the engine decides nothing and writes nothing.
8. The application answers with a receipt or a refusal.

For the pages of the application, `ehos_contract_auth` also signs a person in. It keeps the
credential encrypted in its own table, on the server. The browser holds only a random token.
`EhosContract.Auth.Session` then builds the actor of the person.

## Which calls does the Authorizer check?

The Authorizer checks each call that comes into the application from outside, with a credential.
This page calls the place where such a call enters the door. The door is `EhosContract.call/3`,
or `dispatch/3`, `record/3` and `query/3` with the actor of a credential. `EhosContract.Plug` calls
`call/3` for a request to `/api`. A page calls it with `form: true` for a person who signed in:
[Issue a command from a form](forms.md). The kind of actor decides. The engine asks the Authorizer about an actor of a credential. It never asks about
a `:system` actor or a reaction.

![A call from a person or an external system passes the credential check and the Authorizer before dispatch, while a reaction and the code of the application issue to dispatch directly, held to what the contract names.](img/authorization-door.svg)

1. A person sends a call with a credential.
2. An external system sends a call with its own credential.
3. The credential check passes the actor of a verified credential on.
4. The Authorizer allows the call, or dispatch refuses it.
5. Dispatch delivers an event to a reaction: a policy or a process manager.
6. The reaction issues a command that its declaration names.
7. As a `:system` actor, the code of the application issues or records what `by:` or `recorded_by:`
   names.
8. As the domain's seed, the code of the application loads sample data: what a person may issue,
   except what the domain's `not_seeded:` names.

| Origin of the call | Actor | What checks it |
| --- | --- | --- |
| A person, with a credential | `Actor.credential(sub, cap, scp)`, which `ehos_contract_auth` builds from a verified credential | the Authorizer: the credential grants the capability |
| An external system, with its own credential | `Actor.credential/3` | the same, when the platform issues credentials to systems |
| A policy or a process manager that takes an event | the engine builds it | the contract: the reaction names the command that it issues |
| The code of the application: a job, an import | `Actor.system(:name)` | the contract: the domain declares the actor `:system`, and `by:` or `recorded_by:` names it |
| The code of the application that loads sample data | `Actor.seed(:name)` | the contract: the domain declares the actor `:seed`, a `:human` actor may use the declaration, `not_seeded:` does not name it, and it is not a query or a command with `actor_is` |

The engine does not ask the Authorizer about the code of the application, for 3 reasons:

- The application would ask itself.
- A job that runs as the application has no credential of its own.
- A policy can run in the transaction of the command that set it off. A refusal there would fail
  the command of a person, for a reason that is not the person's.

The contract gives the code of the application its permission: an `issues:` or a `by:` that a
reviewer approved. The compiler and dispatch hold the code to it. A `:system` actor can do only what
the contract names it for. `Actor.system(:nightly_import)` can assign a pick list only because `by:`
names `:nightly_import`. An actor of a person cannot pass as a `:system` actor, because the domain must
declare the actor `:system`.

A person is never the code of the application. So a call of a person comes through the door.

> **Pass the actor of the person.**
> If you send the request of a person as a `:system` actor, nothing asks the
> Authorizer. The person then gets each permission of the `:system` actor.

## What can the Authorizer answer?

The Authorizer is a module of the application. It gets the actor and the request, and answers
`:ok` or `{:error, reason}`. The request names the kind of call, the capability, the contract and its
version. For a scoped command or query, it also names the scope field and the value that the call
asks for.

The decision is `EhosContract.Authorizer.check/2`. It reads only the actor and the request:

| Answer | When |
| --- | --- |
| `:ok` | the credential grants the capability, and the scope value is one of its values |
| `{:error, :missing_capability}` | `cap` does not have the capability |
| `{:error, :unscoped_grant}` | the capability is scoped, and `scp` has no values for it. No values does not mean all values. |
| `{:error, :outside_scope}` | the value that the call asks for is not one of the granted values |

If the host configures no Authorizer, the engine uses `EhosContract.Authorizer.Default`. It is
`check/2` alone, and records nothing. `EhosContract.Auth`, in the package `ehos_contract_auth`,
calls `check/2` and writes a row for each decision. The host must configure it:
`config :ehos_contract, authorizer: EhosContract.Auth`.

**An Authorizer can narrow what a credential grants. It cannot widen it.** After an `:ok`, the
engine runs `check/2` again on the actor. If `check/2` refuses, the engine raises
`EhosContract.Authorizer.WidenedError`. So a defect in an Authorizer fails, and does not let a call
through. Each grant must come in the credential, as the platform issues it.

[Write an Authorizer](authorizer.md) tells how to add a rule of your own.

## What does a recorded event need?

`EhosContract.record/3` appends an event that the contract declares `recorded_by:`, without a
command. Example: an observation, or the answer of an external system. Its capability is
`<domain>.<event>`. Its roles are those of the human actors in `recorded_by:`. The engine asks the
Authorizer about a credential, as for a command. A picker who reports an empty shelf needs
`authorization_example.shelf_found_empty`. A `:system` actor that the event names records it without
a credential.

**A recorded event has no scope.** A credential with the capability can record the event for each
unit. A picker of warehouse 7 can record an empty shelf in warehouse 12.

## What does each answer write?

| Answer | Log | `ehos_contract_commands` | `ehos_contract_auth_decisions`, for a call with a credential |
| --- | --- | --- | --- |
| Refused by the Authorizer | nothing | nothing | a `refused` row, with the reason |
| Refused after the Authorizer: fields that do not fit, a conflict, a reused idempotency key, an erased subject | nothing | nothing | an `allowed` row |
| Accepted | the events | an `accepted` row | an `allowed` row |
| Accepted before, with the same idempotency key | nothing more | nothing more | an `allowed` row |
| Rejected on an invariant | nothing | a `rejected` row | an `allowed` row |
| Failed in the code | nothing: the engine rolls back | a `failed` row, if dispatch owns the transaction | an `allowed` row |

- A refusal leaves nothing in the tables of the engine. The row that records it belongs to the
  Authorizer.
- A credential that the plug does not verify gets no row. The Authorizer never sees it.
- A declaration that no human actor can use has no capability. A call with a credential gets
  `{:error, :missing_capability}`, and the engine does not ask the Authorizer. No row is written.
- Each row of `ehos_contract_auth` is one `INSERT` in the call, also for a query. Nothing deletes
  the rows: the application decides how long it keeps them.
- If `ehos_contract_auth` cannot write its row, the call fails.
- If the code fails inside the transaction of the caller, the engine writes no `failed` row. It
  raises the exception again.
- A query writes nothing to the log, because a read is not an event. A query with a credential gets a
  decision row, as a command does.
- An accepted command has two rows. The row of `ehos_contract_auth` records that the credential
  allowed the call. The row of `ehos_contract_commands` records what became of the command.
- The engine asks the Authorizer before its own transaction. If a caller wraps `dispatch/3` in its own
  transaction and rolls it back, the decision row goes too. `EhosContract.Plug` never does this.

## How strong is this check?

The check is the standard level. It is the same as an application that verifies the tokens of
Auth0, Keycloak or Entra ID:

- the credentials are signed and short: Ed25519, 10 minutes;
- the application verifies them with published keys, in its own process;
- the keys rotate by `kid`;
- each credential has one audience;
- the roles become capabilities;
- a missing value refuses the call;
- with `ehos_contract_auth`, each decision of the Authorizer gets a row.

Two things are stronger than in a usual application:

- The check is in one place, dispatch, not in each controller. A command without the capability
  does not get to its decision, from any origin with a credential. This closes the most frequent weakness of web
  applications, broken access control (OWASP A01).
- The engine checks each row of a scoped query again, against the grant.

The check has these limits. They are known and accepted:

- A role that the platform removes works until the credential expires: 15 minutes or less. This is
  true of each JWT without a revocation list.
- A stolen credential works until it expires. A credential bound to a client (DPoP, mutual TLS) is a
  higher level. The platform must decide it.
- The plug accepts a credential that expires in 15 minutes or less. That is the 10 minutes of the
  platform, and 5 minutes for clocks that do not agree.
- A key that the platform removes from its set works until the next fetch that succeeds. If the
  fetches succeed, that is 5 minutes or less. While the fetches fail, the application keeps the last
  set of keys that it fetched, with no limit of time.
- A scope is one field, compared for equality. A recorded event has no scope. Richer rules for rows
  stay in the code of the application. For a command, `actor_is` lets only the person whom a field
  of the state names issue it. [Write a domain, a contract and a process module](contract.md) tells
  how.
- The decision rows are not tamper-evident.
- The whole chain is as strong as the flow that gives a frontend its credential. `ehos_contract_auth`
  signs a person in with the authorization code flow of OpenID Connect, with PKCE.

## Next steps

- [Narrow a call to the values of a grant](scope.md): give a command or a query a scope.
- [Write an Authorizer](authorizer.md): add a rule of your own to the check.
- [Accept calls with a credential](calls.md): serve the contract over HTTP, through `call/3`, or
  from code.
- [The compile refusals](refusals.md#refusals-d): each refusal of names and scopes, in the family D.
