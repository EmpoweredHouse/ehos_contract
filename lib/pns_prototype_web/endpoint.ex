defmodule PnsPrototypeWeb.Endpoint do
  @moduledoc """
  The real Phoenix endpoint `packages/pns_web`'s own test host stood in
  for until now (`packages/pns_web/test/support/test_host/endpoint.ex`,
  which this mirrors — same plugs, same order, for the same reasons
  documented there and in `PNS.Web.Router.pns_dashboard/2`'s moduledoc).
  """

  use Phoenix.Endpoint, otp_app: :pns_prototype

  @session_options [
    store: :cookie,
    key: "_pns_prototype_key",
    signing_salt: "pns-prototype-salt",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  # Before the router, not through it — PNS.Web.Router.pns_dashboard/2's
  # moduledoc explains why: a route nested in a CSRF-protected pipeline
  # gets refused by Plug's own cross-origin-script guard.
  plug Plug.Static,
    at: "/pns_web/assets",
    from: {:pns_web, "priv/static/assets"},
    gzip: false

  plug Plug.Session, @session_options
  plug PnsPrototypeWeb.Router
end
