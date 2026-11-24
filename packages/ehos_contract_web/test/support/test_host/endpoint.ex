defmodule EhosContract.Web.TestHost.Endpoint do
  @moduledoc """
  The whole host this package proves itself against — never the real
  `ehos_contract_host`, which has no Phoenix yet.
  """

  use Phoenix.Endpoint, otp_app: :ehos_contract_web

  @session_options [
    store: :cookie,
    key: "_ehos_contract_web_test_host_key",
    signing_salt: "ehos-contract-web-test-salt",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  # Before the router, not through it — see EhosContract.Web.Router.ehos_contract_dashboard/2's
  # moduledoc for why a route (`forward`, nested in a CSRF-protected
  # pipeline) is the wrong place for this. A real host adds this same line
  # to its own endpoint.
  plug Plug.Static,
    at: "/ehos_contract_web/assets",
    from: {:ehos_contract_web, "priv/static/assets"},
    gzip: false

  plug Plug.Session, @session_options
  plug EhosContract.Web.TestHost.Router
end
