defmodule EhOsContract.Web.TestHost.Endpoint do
  @moduledoc """
  The whole host this package proves itself against — never the real
  `pns_prototype`, which has no Phoenix yet.
  """

  use Phoenix.Endpoint, otp_app: :eh_os_contract_web

  @session_options [
    store: :cookie,
    key: "_pns_web_test_host_key",
    signing_salt: "pns-web-test-salt",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  # Before the router, not through it — see EhOsContract.Web.Router.eh_os_contract_dashboard/2's
  # moduledoc for why a route (`forward`, nested in a CSRF-protected
  # pipeline) is the wrong place for this. A real host adds this same line
  # to its own endpoint.
  plug Plug.Static,
    at: "/eh_os_contract_web/assets",
    from: {:eh_os_contract_web, "priv/static/assets"},
    gzip: false

  plug Plug.Session, @session_options
  plug EhOsContract.Web.TestHost.Router
end
