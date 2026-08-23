defmodule PNS.Web.TestHost.TestToken do
  @moduledoc """
  Test-only helper, not a plug in the request chain. Mints a signed token
  through `PNS.Auth.LocalToken.sign/1` — the only call site of `sign/1` in
  this package — and attaches it as a bearer token, so
  `PNS.Web.Plug.Authenticate` picks it up exactly as a real host's plug
  would. Stands in for the real login path this foundation does not
  decide (`docs/adr/identity-seam.md`, "Not decided").
  """

  import Plug.Conn

  @spec put_actor(Plug.Conn.t(), String.t(), [String.t()]) :: Plug.Conn.t()
  def put_actor(conn, subject, roles) do
    token = PNS.Auth.LocalToken.sign(%{"sub" => subject, "roles" => roles})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
