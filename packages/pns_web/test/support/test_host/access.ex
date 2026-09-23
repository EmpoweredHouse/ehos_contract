defmodule PNS.Web.TestHost.Access do
  @moduledoc """
  Test-only helper. Puts a caller's roles on a request as a header, which
  `PNS.Web.TestHost.Resolver` reads back — the same job a real host's own
  authentication does before `pns_dashboard/2` ever sees the connection.

  A header rather than an assign because it survives the whole request,
  including the `live/2` round trip, the way a real host's credentials would.
  """

  import Plug.Conn

  @spec put_actor(Plug.Conn.t(), String.t(), [String.t()]) :: Plug.Conn.t()
  def put_actor(conn, subject, roles) do
    conn
    |> put_req_header("x-test-subject", subject)
    |> put_req_header("x-test-roles", Enum.join(roles, ","))
  end
end
