# Decide who can see the dashboard

This page tells you how to write the *resolver*: the module that decides who can see the dashboard
and the JSON API. It is for a developer who mounts the dashboard. The dashboard and the API both
need a resolver, and the package has no default.

The dashboard names each event of the client in the words of the client, so it is a map of the
business. The API also gives the number of events for each version, with their times: the volume
of the business. The package does not redact anything. The resolver decides who sees it.

## Before you start

- Your application signs people in, and a plug puts the signed-in person on the connection.
  The package has no sign-in screen.

## Steps

1. Write a module that implements `EhOsContract.Web.Resolver`:

   ```elixir
   defmodule MyApp.EhOsContractResolver do
     @behaviour EhOsContract.Web.Resolver

     @impl true
     def resolve_user(conn) do
       case conn.assigns[:current_user] do
         %{id: id} -> id
         nil -> nil
       end
     end

     @impl true
     def resolve_access(nil, _base_path), do: {:forbidden, "/login"}

     def resolve_access(user_id, _base_path) do
       case MyApp.Accounts.role(user_id) do
         :operator -> :all
         :auditor -> :read_only
         _other -> {:forbidden, "/"}
       end
     end
   end
   ```

2. In `resolve_user/1`, return an identifier of the person, not a struct. On a page, the dashboard
   calls `resolve_user/1` only on a full page load. It signs the answer into the page, but does not
   encrypt it, and gets it back on each reconnect while the page is open. A struct would put its
   fields in the HTML.
3. In `resolve_access/2`, look up the permissions of the person. The dashboard calls it on each
   mount, a reconnect and a move between the screens included. A role that you look up here
   applies on the next reconnect. A role that you read from a struct would apply only on the next
   page load.
4. Grant access for an explicit role, and refuse each other caller. If you do not, each person
   that your application signs in can see the dashboard, a customer included.
5. Give the resolver to each macro, with `resolver: MyApp.EhOsContractResolver`.

**Result:** a person with a granted role sees the dashboard. Each other caller goes to the path of
`{:forbidden, path}`.

## What can `resolve_access/2` return?

| Return | On a page of the dashboard | On the JSON API |
| --- | --- | --- |
| `:all` | shows the page | answers the request |
| `:read_only` | shows the page | answers the request |
| `{:forbidden, path}` | sends the browser to `path` | answers 403 with `{"error": "forbidden"}`, and does not use `path` |

Return only one of these. Any other return is not a refusal: the page or the request fails with
an error.
`:all` and `:read_only` show the same thing, because the dashboard changes nothing. The screens
show which one applies.

`base_path` is the path where the dashboard or the API is mounted, as a browser sees it. It
includes the prefix of each scope around the macro, and has no slash at the end. Example:
`"/admin/dashboard"` for `eh_os_contract_dashboard "/dashboard"` inside `scope "/admin"`. You can
use it to answer the dashboard and the API differently, or to build the path of
`{:forbidden, path}`, such as your sign-in page.

## What can go wrong

- **A request to the other mount fails.** `resolve_access/2` has no clause for its `base_path`.
  Match `base_path` with a clause that accepts any path.
- **A change of role applies only on the next page load.** `resolve_access/2` reads the role from
  what `resolve_user/1` returned. Look the role up in `resolve_access/2`.

## Next steps

- [Mount the dashboard](mount-the-dashboard.md): the routes and the assets.
- [The JSON API](api.md): what the API gives to a caller that the resolver lets in.
- `EhOsContract.Web.Resolver`: the reference of the callbacks.
