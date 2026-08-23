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

  # Before the router, not through it — see PNS.Web.Router.pns_dashboard/2's
  # moduledoc for why a route (`forward`, nested in a CSRF-protected
  # pipeline) is the wrong place for this. A real host adds this same line
  # to its own endpoint.
  plug Plug.Static,
    at: "/pns_web/assets",
    from: {:pns_web, "priv/static/assets"},
    gzip: false

  # The provisional login (PNS.Web.LocalLogin) posts a plain HTML form —
  # the first thing in this package that needs a parsed request body. Real
  # hosts almost always already have this; a mountable dashboard adding it
  # would be presumptuous, so it stays out of `pns_dashboard/2` and is
  # listed instead in `PNS.Web.LocalLogin`'s moduledoc as an assumption.
  plug Plug.Parsers, parsers: [:urlencoded], pass: ["*/*"]

  plug Plug.Session, @session_options
  plug PNS.Web.TestHost.Router
end
