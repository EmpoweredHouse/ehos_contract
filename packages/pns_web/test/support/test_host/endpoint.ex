defmodule PNS.Web.TestHost.Endpoint do
  @moduledoc """
  The whole host this package proves itself against — never the real
  `pns_prototype`, which has no Phoenix yet.
  """

  use Phoenix.Endpoint, otp_app: :pns_web

  @session_options [
    store: :cookie,
    key: "_pns_web_test_host_key",
    signing_salt: "pns-web-test-salt",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  plug Plug.Session, @session_options
  plug PNS.Web.TestHost.Router
end
