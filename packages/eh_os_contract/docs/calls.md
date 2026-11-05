# Accept calls with a credential

This page tells how to bring a call with a *credential* to the contract. A call comes over HTTP,
through other code that carries raw data, or from code that builds the struct. It also tells how the code of the
application calls as a `:system` actor. It is for a developer who builds an application on the
engine. [The glossary](glossary.md) defines each word in italics.

## Before you start

- You know how the engine checks a call: [How is a call authorized?](authorization.md)
- A plug in front of the routes verifies the credential and builds the actor. The plug of
  `eh_os_contract_auth` does this. Its README tells how to configure it.

This page uses this contract. A lead assigns pick lists. A picker reports an empty shelf. A nightly
import also assigns pick lists, as a `:system` actor:

```elixir
defmodule Concepts.Calls.Domain do
  use EhOsContract.Domain, name: :calls_example, language: :en

  subdomain :core, "Core", type: :core

  context :warehouse, "Warehouse", subdomain: :core

  actor :lead, :human, "Warehouse lead"
  actor :picker, :human, "Picker"
  actor :nightly_import, :system, "Nightly import"
end

defmodule Concepts.Calls.Contracts.Warehouse do
  use EhOsContract.Contract,
    domain: Concepts.Calls.Domain,
    context: :warehouse,
    id: "calls_example.warehouse"

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

> **`EhOsContract.Actor.credential/3` verifies nothing.**
> Build an actor from a credential only after a plug verifies its signature. An actor that you build
> from an unverified token grants each capability that the token claims.

## Serve the contract over HTTP

`EhOsContract.Plug` serves the commands, the recorded events and the queries of the contracts that you
give it. Each route is the name of a capability.

1. Forward a path to the plug, after the plug that verifies the credential:

   <!-- not compiled: a line of the host's router -->
   ```elixir
   forward "/api", EhOsContract.Plug, contracts: [Concepts.Calls.Contracts.Warehouse]
   ```

2. Send a call:

   ```text
   POST /api/commands/calls_example.assign_pick_list
        {"warehouse_id": "7", "order_id": "order-1", "picker_id": "u-82"}
   POST /api/records/calls_example.shelf_found_empty
        {"warehouse_id": "7", "order_id": "order-1"}
   GET  /api/queries/calls_example.open_pick_lists_for_warehouse?warehouse_id=7
   ```

   A command and a recorded event take their fields as the body. A query takes its parameters in the
   URL. Browsers, proxies and servers can log the URL: [Write a read model and its
   query](read-models.md) tells what that means for personal data.

A command and a recorded event must have the header `content-type: application/json`, also with an
empty body. If the caller may make the call and the header is missing or different, the plug answers
415. It dispatches nothing. A command with a scope gets 403 `outside_scope` instead, because the
plug does not read the scope from that body.

This header protects a person who is signed in with a cookie. A web page of another origin can send
a form with the cookie of the person. But the browser asks your application before that page can
send `content-type: application/json`. Do not let your CORS configuration allow credentials for an
origin that you do not trust. Otherwise, a page of that origin can send a command to the plug as the
person.

The plug reads two headers, for a command and for a recorded event. `idempotency-key` gives the
idempotency key. `x-correlation-id` gives the correlation, a UUID.

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
| a command or a recorded event without `content-type: application/json` | 415 |
| personal data of an erased subject | 410 |
| the host could not supply a field | 503 |

**The plug asks the Authorizer first.** It asks also when the body or the fields do not fit. So a
caller without the capability gets 403, and learns nothing about the fields of the declaration. Each
request that gets to the Authorizer is one decision, and `eh_os_contract_auth` records it. A 404
and a 401 get no decision.

**A problem or a refusal carries no value that the caller did not send.** A problem names the field.
A refusal names its reason.

## Call the contract from other code

The plug calls `EhOsContract.call/3`. Other code that carries raw data calls it in the same way. Examples: a job that holds the credential of a person, or another API. Give it the name of
the capability, the data as it was sent, and the actor of the credential:

<!-- not compiled: a call in the host's code -->
```elixir
EhOsContract.call(
  {:command, "calls_example.assign_pick_list"},
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

Code that builds the structs itself loses this order. For this reason, the plug does not build
them.

`call/3` takes data with the types that JSON gives: a boolean as `true`, an integer as a number.
The values of a query can also come as text, as a URL carries them. A
form sends text: `"false"` for a checkbox, `"42"` for an amount. With `form: true`, `call/3` reads
the params of a form as text, a blank field as absent, and rows as `inputs_for` sends them. A page
checks the form through [`EhOsContract.Form`](forms.md) while the person types, with the module of
the declaration or the same name of the capability:
`Form.changeset({:command, "calls_example.assign_pick_list"}, params)`. On submit, the page sends
the params to `call/3` with `form: true` and the actor of the person, and `call/3` asks the
Authorizer. Until the person sends the form, nothing asks the Authorizer. The form checks only the shape that the contract declares. That is the fields, their
types, the members of an enum and the names of the invariants of its values. So a page shows a form
only to the people that it is for.

## Dispatch from code

From code, dispatch the struct of the command with the actor of the person. On a page,
`EhOsContract.Auth.Session.actor/2` gives the actor of the person who signed in.

This example builds the actor by hand, which is correct only in a test or to try the engine. See
the warning in "Before you start".

<!-- not compiled: calls in the host's code -->
```elixir
actor =
  EhOsContract.Actor.credential("u-81", ["calls_example.assign_pick_list"])

EhOsContract.dispatch(Concepts.Calls.Contracts.Warehouse,
  %AssignPickList{warehouse_id: "7", order_id: "order-1", picker_id: "u-82"},
  actor: actor, idempotency_key: "req-81")
#=> {:ok, %EhOsContract.Receipt{...}}
```

The code of the application acts as a `:system` actor of its domain:

<!-- not compiled: calls in the host's code -->
```elixir
EhOsContract.dispatch(Concepts.Calls.Contracts.Warehouse,
  %AssignPickList{warehouse_id: "7", order_id: "order-2", picker_id: "u-83"},
  actor: EhOsContract.Actor.system(:nightly_import), idempotency_key: "import-row-2")
#=> {:ok, ...}, because by: names :nightly_import; else {:error, :not_declared}
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
  - for a command of the same type, the second job gets the receipt of the first, whatever its
    fields. Its command does not run;
  - for another command, the second job gets `{:error, :idempotency_key_reused}`.

## Test a call with a credential

In a test, `EhOsContract.Auth.Testing.credential/3` of `eh_os_contract_auth` signs a credential with a
test key. Send it through the plug, as a client does. The test key needs this line in
`config/test.exs`, and nowhere else:

<!-- not compiled: the host's configuration -->
```elixir
config :eh_os_contract_auth, pin_keys: true
```

The package raises if a test pins a key without the line, or where the environment of Mix is not
`:test`. If another environment sets the line, the children of the package do not start.

## Next steps

- [How is a call authorized?](authorization.md): what the Authorizer answers, and what each answer
  writes.
- [Narrow a call to the values of a grant](scope.md): the scope that `outside_scope` refers to.
- [Issue a command from a form](forms.md): check the text of a form, and send it through `call/3`.
- `EhOsContract.Plug` and `EhOsContract.call/3`: the reference, on hexdocs.
