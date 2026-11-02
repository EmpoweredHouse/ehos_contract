# Accept calls with a credential

This page tells how to bring a call with a credential to the contract: over HTTP, through another door
of the application, or from code. It also tells how the code of the application calls as a `:system`
actor. It is for a developer who builds an application on the engine. [The glossary](glossary.md)
defines each word in italics.

## Before you start

- You know how the engine checks a call: [How is a call authorized?](authorization.md)
- A plug in front of the routes verifies the credential and builds the actor. The plug of
  `eh_os_contract_auth` does this. Its README tells how to configure it.
- The examples use the contract of [How is a call authorized?](authorization.md#an-example)

> **`EhOsContract.Actor.credential/3` verifies nothing.**
> Build an actor from a credential only after a plug verifies its signature. An actor that you build
> from an unverified token grants each capability that the token claims.

## Serve the contract over HTTP

`EhOsContract.Plug` serves the commands, the recorded events and the queries of the contracts that you
give it. Each route is the name of a capability.

1. Forward a path to the plug, after the plug that verifies the credential:

   <!-- not compiled: a line of the host's router -->
   ```elixir
   forward "/api", EhOsContract.Plug, contracts: [Concepts.Authorization.Contracts.Warehouse]
   ```

2. Send a call:

   ```text
   POST /api/commands/authorization_example.assign_pick_list
        {"warehouse_id": "7", "order_id": "order-1", "picker_id": "u-82"}
   POST /api/records/authorization_example.shelf_found_empty
        {"warehouse_id": "7", "order_id": "order-1"}
   GET  /api/queries/authorization_example.open_pick_lists_for_warehouse?warehouse_id=7
   ```

   A command and a recorded event take their fields as the body. A query takes its parameters in the
   URL.

The plug reads two headers. `idempotency-key` gives the idempotency key of a command.
`x-correlation-id` gives its correlation, a UUID.

The plug does not authenticate. It reads the actor from `conn.assigns.eh_os_contract_actor`, which
the plug in front of it builds from a verified credential. Without that actor, the answer is 401. A
`:system` actor never comes over HTTP: the plug refuses it with 401 too. A path that the plug does
not serve gets 404 before the plug looks at the actor.

These are the main answers. `EhOsContract.Plug` lists each answer, with its body:

| Answer | Status |
| --- | --- |
| accepted, or a query answered | 200 |
| rejected on an invariant, or fields that do not fit | 422 |
| refused: `missing_capability`, `outside_scope` and others | 403 |
| no actor of a credential | 401 |
| conflict, or an idempotency key that the same actor used for another command | 409 |
| no such capability | 404 |
| a body that is not a JSON object, or a correlation id that is not a UUID | 400 |
| personal data of an erased subject | 410 |
| the host could not supply a field | 503 |

**The plug asks the Authorizer first.** It asks also when the body or the fields do not fit. So a
caller without the capability gets 403, and learns nothing about the fields of the declaration. Each
request is one decision, and `eh_os_contract_auth` records it.

**A problem or a refusal carries no value that the caller did not send.** A problem names the field.
A refusal names its reason.

## Call the contract from another door

The plug is one door to `EhOsContract.call/3`. Each other door that carries raw data calls it in the
same way. Examples: a job that holds the credential of a person, or another API. Give it the name of
the capability, the data as it was sent, and the actor of the credential:

<!-- not compiled: a call in the host's code -->
```elixir
EhOsContract.call(
  {:command, "authorization_example.assign_pick_list"},
  %{"warehouse_id" => "7", "order_id" => "order-1", "picker_id" => "u-82"},
  actor: actor, idempotency_key: "req-81"
)
#=> {:ok, %EhOsContract.Receipt{...}}
```

`call/3` asks the Authorizer before it tells what is wrong with the data, as the plug does. Then it
answers as `dispatch/3`, `record/3` or `query/3` does. It has these answers of its own:

| Answer | When |
| --- | --- |
| `{:error, :not_found}` | the contracts that it serves do not declare the capability as that kind. `contracts:` gives them; the default is each registered contract. |
| `{:error, :no_actor}` | the call has no actor of a credential |
| `{:error, :not_an_object}` | the caller can make the call, and the data is not a map |
| `{:error, :correlation_id_is_not_a_uuid}` | the caller can make the call, and the correlation id is not a UUID |

A door that builds the structs itself loses this order. For this reason, the plug does not build
them.

`call/3` takes data with the types that JSON gives: a boolean as `true`, an integer as a number. A
form sends text: `"false"` for a checkbox, `"42"` for an amount. A page reads a form through
[`EhOsContract.Form`](forms.md). The form takes the module of the declaration, or the same name of the
capability: `Form.changeset({:command, "authorization_example.assign_pick_list"}, params)`. It checks
the fields while the person types. The page then dispatches the struct with the actor of the
person, and `dispatch/3` asks the Authorizer. Until the person sends the form, nothing asks the
Authorizer. The form checks only the shape that the contract declares. So a page shows a form only to
the people that it is for.

## Dispatch from code

From code, build the actor and dispatch the struct of the command:

<!-- not compiled: calls in the host's code -->
```elixir
actor =
  EhOsContract.Actor.credential("u-81", ["authorization_example.assign_pick_list"])

EhOsContract.dispatch(Concepts.Authorization.Contracts.Warehouse,
  %AssignPickList{warehouse_id: "7", order_id: "order-1", picker_id: "u-82"},
  actor: actor, idempotency_key: "req-81")
#=> {:ok, %EhOsContract.Receipt{...}}
```

The code of the application acts as a `:system` actor of its domain:

<!-- not compiled: calls in the host's code -->
```elixir
EhOsContract.dispatch(MyApp.Contracts.Ledger, %Deposit{account_id: "a-1", amount: 100},
  actor: EhOsContract.Actor.system(:nightly_import))
#=> {:ok, ...} when the command's by: names :nightly_import, else {:error, :not_declared}
```

## Give each actor its own idempotency keys

An idempotency key belongs to the actor that sends it: to the subject of the credential, or to the
name of the `:system` actor. Two actors with one key send two commands. Neither actor sees the
receipt of the other.

- Send a retry from the same subject. If the platform gives a person another `sub` between the first
  try and the retry, the retry is a new command, and it runs.
- Give the keys of each job a prefix of its own. All the code that shares one credential, or runs as
  one `:system` actor, shares one set of keys. Two jobs import as `:nightly_import`, and both send
  `"row-1"`:
  - for the same command, the second job gets the receipt of the first, and nothing runs again;
  - for another command, the second job gets `{:error, :idempotency_key_reused}`.

## Test a call with a credential

In a test, `EhOsContract.Auth.Testing.credential/3` of `eh_os_contract_auth` signs a credential with a
test key. Send it through the plug, as a client does.

## Next steps

- [How is a call authorized?](authorization.md): what the Authorizer answers, and what each answer
  writes.
- [Narrow a call to the values of a grant](scope.md): the scope that `outside_scope` refers to.
- [Issue a command from a form](forms.md): read the text of a form before a dispatch.
- `EhOsContract.Plug` and `EhOsContract.call/3`: the reference, on hexdocs.
