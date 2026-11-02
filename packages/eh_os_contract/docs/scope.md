# Narrow a call to the values of a grant

This page tells how to narrow a command or a query to the values that a credential grants. Example:
a lead of warehouse 7 can assign the pick lists of warehouse 7, and of no other warehouse. It is for
a developer who writes a contract. [The glossary](glossary.md) defines each word in italics.

A *scope* is one field of a command, or one field of a read model, that the engine compares with the
values of the credential. The engine compares the value of the call before the code runs. For a query,
it also compares each row that the code answers.

## Before you start

- You know how the engine checks a call: [How is a call authorized?](authorization.md)
- The command or the query has `by:` with a human actor.

## 1. Give the actor a scope in the domain

Name the field in `scope:` of the actor:

```elixir
defmodule Concepts.Scope.Domain do
  use EhOsContract.Domain, name: :scope_example, language: :en

  subdomain :core, "Core", type: :core

  context :warehouse, "Warehouse", subdomain: :core

  actor :lead, :human, "Warehouse lead", scope: [:warehouse_id]
  actor :picker, :human, "Picker"
end
```

## 2. Scope the command or the query

Give the command or the query `scope:` with the same field:

```elixir
defmodule Concepts.Scope.Contracts.Warehouse do
  use EhOsContract.Contract,
    domain: Concepts.Scope.Domain,
    context: :warehouse,
    id: "scope_example.warehouse"

  aggregate :pick_list, "Pick list" do
    identity [:warehouse_id, :order_id]

    command :assign_pick_list, "Assign a pick list to a picker",
      by: :lead,
      scope: :warehouse_id,
      emits: :assigned do
      field :picker_id, :id
    end

    event :assigned, "Pick list assigned" do
      field :picker_id, :id
    end
  end

  read_model :open_pick_lists, "Open pick lists", projects: [:assigned] do
    field :warehouse_id, :id
    field :order_id, :id
    field :picker_id, :id
  end

  query :open_pick_lists_for_warehouse, "Open pick lists in a warehouse",
    reads: :open_pick_lists,
    by: [:lead],
    scope: :warehouse_id do
    param :warehouse_id, :id
  end
end
```

- The scope of a command is one of its fields, or a field of the identity of its unit. It is
  required.
- The scope of a query is a field of its read model. The query has a parameter with the same name
  and type.
- Each actor in `by:` carries the scope in the domain.

The compiler refuses a scope that does not fit ([`D10`](refusals.md#refusals-d)).

## 3. Grant the values in the credential

The platform gives the role with values. The credential carries them in `scp`, for each scoped
capability:

```json
{
  "cap": ["scope_example.assign_pick_list", "scope_example.open_pick_lists_for_warehouse"],
  "scp": {
    "scope_example.assign_pick_list": {"warehouse_id": ["7"]},
    "scope_example.open_pick_lists_for_warehouse": {"warehouse_id": ["7"]}
  }
}
```

The credential needs the values for each scoped capability. Values for the query do not grant the
command.

> **Check that the platform can grant values.**
> The manifest of `eh_os_contract_auth` has no field for a scope. If the platform cannot give a role
> with values, each call to a scoped capability gets `{:error, :unscoped_grant}`.

## The result

A lead with a grant for warehouse 7:

- can assign a pick list of warehouse 7;
- gets `{:error, :outside_scope}` for a pick list of warehouse 12;
- reads only the open pick lists of warehouse 7.

The engine does these checks:

1. **Before the code runs**, the engine compares the value of the scope field with the granted values.
   If the value is outside the grant, the answer is `{:error, :outside_scope}`. The code of the
   command or the query does not run.
2. **After a query answers**, the engine compares the scope field of each row with the grant. If one
   row is outside it, the engine raises `EhOsContract.Authorizer.OutsideScopeError`. The caller gets
   no row. So a wrong `where` cannot give one warehouse the rows of another warehouse.

## What can go wrong

**The answer is `{:error, :unscoped_grant}`.** The credential has the capability, but no values for
it in `scp`. No values does not mean all values: the check refuses the call. Ask the platform to
give the role with values.

**A granted value never matches.** The engine compares the values as the strings that the
credential carries. A value that is not of the type of the field matches nothing. The engine does
not fail on a cast.

**A `:system` actor sees all the rows.** The engine does not narrow a `:system` actor that `by:`
names, for a command or a query. This is correct: the code of the application has no grant.

**A person records an event for another warehouse.** A recorded event has no scope. A credential
with its capability can record it for each unit. If the event must stay in one warehouse, make it a
command with a scope.

**The rule needs more than one field.** Keep the rule in the code of the application. A scope is
one field, compared for equality. "Only the pick lists that are assigned to me" is such a rule.

## Next steps

- [How is a call authorized?](authorization.md): the check that a scope narrows.
- [Write a read model and its query](read-models.md): the read model that a query reads.
- [The compile refusals](refusals.md#refusals-d): each refusal of a scope, in the family D.
