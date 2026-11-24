defmodule EhosContract.Web.Resolver do
  @moduledoc """
  How a mounted dashboard turns a connection into an access decision. A host
  implements this to plug its own notion of "who is logged in" and "what may
  they see" into `EhosContract.Web.Router.ehos_contract_dashboard/2` and
  `EhosContract.Web.Router.ehos_contract_api/2`.

  **Required, with no default.** A dashboard that names every event in a client's own
  words is a map of their business, and an access rule that silently lets everyone in
  would be this package deciding that on the host's behalf.

      defmodule MyApp.EhosContractResolver do
        @behaviour EhosContract.Web.Resolver

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

  **Return an identifier from `resolve_user/1`, and look permissions up in
  `resolve_access/2`.** On a page, `resolve_user/1` runs on the full page load only, and
  what it returns is signed (not encrypted) into the page and handed back on every
  reconnect for as long as the page is open. A whole user struct would put its fields
  in the HTML, and a role read from it would outlive a change to that role until the
  next page load; a role looked up in `resolve_access/2` applies on the next reconnect.
  Grant on an explicit role and refuse everything else: anyone the host signs in, a
  customer included, is otherwise let in.

  For a page, `{:forbidden, path}` redirects there; for the JSON API it is a 403 with
  `{"error": "forbidden"}`, and the path is not used. `:all` and `:read_only` see the
  same today, since nothing here changes anything; the screens show which one applies.
  """

  # The package used to ship a default, reading an actor the engine's own token verifier
  # had put on the connection, and a login screen to mint that token. Both went on
  # 23 September 2026 with the rest of the identity layer.

  @doc """
  Reads who the caller is from whatever the host's own auth plug put on the connection.
  For a page it runs on the full page load only, and its answer is kept in the page:
  return an identifier, not a struct.
  """
  @callback resolve_user(conn :: Plug.Conn.t()) :: term()

  @doc """
  Turns a resolved user into an access level, or a redirect.

  `base_path` is the path the asking macro was mounted at, as a browser sees it: the
  dashboard's for a page, the API's for a JSON request, each with the prefix of every
  scope around it and without a trailing slash (`"/admin/dashboard"` for
  `ehos_contract_dashboard "/dashboard"` inside `scope "/admin"`). A host may use it to answer the two differently, or to
  build the `{:forbidden, path}` it sends a person to, typically its own login; match
  it with a clause that accepts any path, or a request to the other mount fails.
  """
  @callback resolve_access(user :: term(), base_path :: String.t()) ::
              :all | :read_only | {:forbidden, String.t()}
end
