# Write an Authorizer

This page tells how to add a rule of your own to the check of each call. Example: refuse the calls
of a suspended account. It is for a developer who builds an application on the engine. [The
glossary](glossary.md) defines each word in italics.

The *Authorizer* is a module of the application. Dispatch asks it if an actor with a credential can
make a call. The engine has a default Authorizer. You need one of your own only for a rule that the
credential does not carry.

## Before you start

- You know how the engine checks a call: [How is a call authorized?](authorization.md)
- If the application uses `eh_os_contract_auth`, `EhOsContract.Auth` is the Authorizer already. It
  writes a row for each decision. A module of your own replaces it, with its rows.

## 1. Write the module

Implement `EhOsContract.Authorizer`. It has one callback:

<!-- not compiled: the callback of a behaviour of the library -->
```elixir
@callback authorize(EhOsContract.Actor.t(), EhOsContract.Authorizer.Request.t()) ::
            :ok | {:error, reason :: atom()}
```

The request names:

- the kind of call: `:command`, `:query` or `:record`;
- the capability;
- the contract module, its `id:` and its version;
- for a scoped command or query, the scope field and the value that the call asks for:
  `{"warehouse_id", "7"}`.

A refusal gives an atom as the reason. The engine raises on any other reason.

Give your rule first. Then call `EhOsContract.Authorizer.check/2`, which compares the request with
the credential:

```elixir
defmodule MyApp.Authorizer do
  @behaviour EhOsContract.Authorizer

  @impl true
  def authorize(actor, request) do
    if MyApp.Accounts.suspended?(actor.subject),
      do: {:error, :suspended},
      else: EhOsContract.Authorizer.check(actor, request)
  end
end
```

## 2. Configure it

Name the module in the configuration of the application:

<!-- not compiled: the host's configuration -->
```elixir
config :eh_os_contract, authorizer: MyApp.Authorizer
```

## The result

Dispatch asks `MyApp.Authorizer` about each call with a credential: a command, a query and a recorded
event. A suspended account gets `{:error, :suspended}`, and nothing is decided or written. The engine
does not ask the Authorizer about a `:system` actor or a policy.

## What can go wrong

**The engine raises `EhOsContract.Authorizer.WidenedError`.** The module answered `:ok` for a call
that the credential does not grant. After each `:ok`, the engine runs `check/2` again on the actor,
and raises if it refuses. An Authorizer can narrow what a credential grants. It cannot widen it.
Give each grant in the credential, as the platform issues it.

**A decision row goes away.** The engine asks the Authorizer before its own transaction. If the
caller wraps `dispatch/3` in a transaction and rolls it back, a row that the Authorizer writes in the
same database goes too.

## Next steps

- [How is a call authorized?](authorization.md): what `check/2` answers, and what each answer writes.
- [Accept calls with a credential](calls.md): the doors that bring a call to dispatch.
- `EhOsContract.Authorizer`: the behaviour, on hexdocs.
