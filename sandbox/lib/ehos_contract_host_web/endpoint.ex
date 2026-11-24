defmodule EhosContractHostWeb.Endpoint do
  @moduledoc """
  The real Phoenix endpoint `packages/ehos_contract_web`'s own test host stood in
  for until now (`packages/ehos_contract_web/test/support/test_host/endpoint.ex`,
  which this mirrors — same plugs, same order, for the same reasons
  documented there and in `EhosContract.Web.Router.ehos_contract_dashboard/2`'s moduledoc).
  """

  use Phoenix.Endpoint, otp_app: :ehos_contract_host

  @session_options [
    store: :cookie,
    key: "_ehos_contract_host_key",
    signing_salt: "eh-os-contract-host-salt",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  # Before the router, not through it — EhosContract.Web.Router.ehos_contract_dashboard/2's
  # moduledoc explains why: a route nested in a CSRF-protected pipeline
  # gets refused by Plug's own cross-origin-script guard.
  plug Plug.Static,
    at: "/ehos_contract_web/assets",
    from: {:ehos_contract_web, "priv/static/assets"},
    gzip: false

  plug Plug.Session, @session_options
  plug EhosContractHostWeb.Router
end
