defmodule PNS.Web.Resolver do
  @moduledoc """
  How a mounted dashboard turns a connection into an access decision. A host
  implements this to plug its own notion of "who is logged in" and "what may
  they see" into `PNS.Web.Router.pns_dashboard/2`.
  """

  @doc "Reads whatever the host's own auth plug put on the connection."
  @callback resolve_user(conn :: Plug.Conn.t()) :: term()

  @doc """
  Turns a resolved user into an access level, or a redirect.

  `base_path` is the prefix `pns_dashboard/2` was mounted at — passed
  through so a `{:forbidden, path}` can point somewhere real (the
  provisional login, today) instead of a path this behaviour has no way to
  construct on its own.
  """
  @callback resolve_access(user :: term(), base_path :: String.t()) ::
              :all | :read_only | {:forbidden, String.t()}
end
