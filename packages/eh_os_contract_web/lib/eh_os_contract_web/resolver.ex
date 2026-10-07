defmodule EhOsContract.Web.Resolver do
  @moduledoc """
  How a mounted dashboard turns a connection into an access decision. A host
  implements this to plug its own notion of "who is logged in" and "what may
  they see" into `EhOsContract.Web.Router.eh_os_contract_dashboard/2` and
  `EhOsContract.Web.Router.eh_os_contract_api/2`.

  **Required, with no default.** A dashboard that names every event in a client's own
  words is a map of their business, and an access rule that silently lets everyone in
  would be this package deciding that on the host's behalf.

      defmodule MyApp.EhOsContractResolver do
        @behaviour EhOsContract.Web.Resolver

        @impl true
        def resolve_user(conn), do: conn.assigns[:current_user]

        @impl true
        def resolve_access(%{admin: true}, _base_path), do: :all
        def resolve_access(%{}, _base_path), do: :read_only
        def resolve_access(nil, _base_path), do: {:forbidden, "/login"}
      end

  For a page, `{:forbidden, path}` redirects there; for the JSON API it is a 403 with
  `{"error": "forbidden"}`, and the path is not used. `:all` and `:read_only` see the
  same today, since nothing here changes anything; the screens show which one applies.
  """

  # The package used to ship a default, reading an actor the engine's own token verifier
  # had put on the connection, and a login screen to mint that token. Both went on
  # 23 September 2026 with the rest of the identity layer.

  @doc "Reads whatever the host's own auth plug put on the connection."
  @callback resolve_user(conn :: Plug.Conn.t()) :: term()

  @doc """
  Turns a resolved user into an access level, or a redirect.

  `base_path` is the prefix `eh_os_contract_dashboard/2` was mounted at — passed
  through so a `{:forbidden, path}` can point somewhere real — the host's
  own login, typically — instead of a path this behaviour has no way to
  construct on its own.
  """
  @callback resolve_access(user :: term(), base_path :: String.t()) ::
              :all | :read_only | {:forbidden, String.t()}
end
