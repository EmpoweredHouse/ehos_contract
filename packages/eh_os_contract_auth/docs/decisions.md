# How is each decision recorded?

This page tells how `EhOsContract.Auth` decides about the actor of a credential, and which row it
writes for each decision. It also tells what the row costs, and how long the application keeps it. It is for a developer
who configures the package, and for a person who must answer who tried to do what. The *Authorizer*
is the module that the engine asks if the actor of a credential can make a call. The
[glossary of the engine](https://github.com/EmpoweredHouse/eh-os-contract/blob/main/packages/eh_os_contract/docs/glossary.md)
defines it, and the words *capability* and *scope*.

## What does the package decide?

`EhOsContract.Auth` is an Authorizer, after you configure
`config :eh_os_contract, authorizer: EhOsContract.Auth`. The engine asks it about each command, query
and recorded event that comes with a credential.

The package has no rule of its own. It decides with `EhOsContract.Authorizer.check/2` alone:

- the credential must grant the capability, in `cap`;
- for a scoped call, the value that the call asks for must be among the values in `scp`.

So the package narrows nothing that the credential grants. [How is a call
authorized?](https://github.com/EmpoweredHouse/eh-os-contract/blob/main/packages/eh_os_contract/docs/authorization.md)
tells how the engine asks, and each refusal of `check/2`.

## What does a row hold?

The package writes 1 row to `eh_os_contract_auth_decisions` for each decision. It records a
refusal as carefully as an acceptance. A refusal writes nothing to the tables of the engine, so
this row is the only record of it.

| Column | Value |
| --- | --- |
| `decided_at` | the time of the database when it wrote the row |
| `subject` | the `sub` of the credential |
| `kind` | `command`, `query` or `record` |
| `capability` | the capability that the call needs |
| `contract`, `contract_version` | the `id:` of the contract, and its version |
| `scope_dimension`, `scope_value` | for a scoped call, the field and the value that the call asks for; the value is empty if the call does not give it |
| `outcome` | `allowed` or `refused` |
| `reason` | for a refusal, its reason, such as `missing_capability`; otherwise empty |

The package records some scope values as `sha256:` and the hex digest of the value:

- a value that a text column cannot hold: invalid UTF-8, or a NUL;
- a value longer than 256 bytes;
- a value that starts with `sha256:`.

So a value that an attacker made is refused like each other value, and does not make the request
fail. The decision is the same: only the record changes.

## What does the row not record?

- **The row records the authorization, not the command.** An allowed command can still be rejected
  on an invariant, or fail in the code. The row of the engine in `eh_os_contract_commands` records
  what became of the command. An accepted command thus has two rows, one in each table.
- **A credential that does not verify gets no row.** It names nobody. `EhOsContract.Auth.Plug` logs
  it instead: [The credential](credential.md#what-does-the-plug-answer-over-http).
- **A declaration that no person can use gets no row.** It has no capability. The engine refuses
  the call with `:missing_capability`, and does not ask the Authorizer.
- **A refusal of an Authorizer of your own gets no row.** Your module refuses first, and does not
  call `EhOsContract.Auth.authorize/2`. So the package does not see the call. The package has no public
  function that writes the row of another refusal.

## When is the row written?

The engine asks the Authorizer before its own transaction starts. A refused call starts no
transaction, and the package must record the refusal too. The row goes through the connection that
the call is on:

- **If the call is not in a transaction**, the row is one `INSERT` that commits on its own.
  `EhOsContract.Plug` calls this way.
- **If the caller wraps `EhOsContract.dispatch/3` in its own transaction and rolls it back**, the
  row goes too.
- **If the package cannot write the row, the call fails.** The package makes no decision that it
  did not record.

## What does it cost?

Each call that gets to the package writes 1 row: 1 `INSERT`. For a query, it is the only write of
the call.
Plan for 1 more write for each call.

The table has 2 indexes: on `decided_at`, and on `subject` and `decided_at`. It has no other.

## How long are the rows kept?

The application decides. The package deletes no row. A common choice is to keep the rows as long as
the application keeps its own log.

The index on `decided_at` makes a periodic delete cheap. Run it from a job, for example:

```elixir
MyApp.Repo.query!("DELETE FROM eh_os_contract_auth_decisions WHERE decided_at < now() - interval '400 days'")
```

## Next steps

- [The credential](credential.md): what the package verifies before it decides.
- [What does each answer write?](https://github.com/EmpoweredHouse/eh-os-contract/blob/main/packages/eh_os_contract/docs/authorization.md#what-does-each-answer-write):
  each answer of a call, and the rows that it writes in each table.
- [Write an Authorizer](https://github.com/EmpoweredHouse/eh-os-contract/blob/main/packages/eh_os_contract/docs/authorizer.md):
  add a rule of your own, and keep the rows of this package.

<!-- Decisions behind this page:
EHOS's decisions this package follows: every decision recorded, a refusal as carefully as an
acceptance, in the application's own table.
#66: a scope value a text column cannot hold, or past 256 bytes, recorded as its digest.
-->
