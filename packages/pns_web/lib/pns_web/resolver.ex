defmodule PNS.Web.Resolver do
  @moduledoc """
  How a mounted dashboard turns a connection into an access decision. A host
  implements this to plug its own notion of "who is logged in" and "what may
  they see" into `PNS.Web.Router.pns_dashboard/2`.

  **Required, with no default.** The package used to ship one, reading an actor
  the engine's own token verifier had put on the connection, and a login screen
  to mint that token. Both went on 23 September 2026 with the rest of the identity
  layer: a dashboard that names every event in a client's own words is a map of
  their business, and an access rule that is silently "let everyone in" would be
  this package deciding that on the host's behalf.
  """

  @doc "Reads whatever the host's own auth plug put on the connection."
  @callback resolve_user(conn :: Plug.Conn.t()) :: term()

  @doc """
  Turns a resolved user into an access level, or a redirect.

  `base_path` is the prefix `pns_dashboard/2` was mounted at — passed
  through so a `{:forbidden, path}` can point somewhere real — the host's
  own login, typically — instead of a path this behaviour has no way to
  construct on its own.
  """
  @callback resolve_access(user :: term(), base_path :: String.t()) ::
              :all | :read_only | {:forbidden, String.t()}
end
