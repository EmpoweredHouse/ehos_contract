defmodule EhOsContractHostWeb.Router do
  @moduledoc """
  Three mounts. Two from `eh_os_contract_web`: the dashboard at `/dashboard` for a person,
  and the read-only conformance API at `/api/eh_os_contract` for anything that is not one.
  And, since v2 stage EA, the commands of `Rehmed.Contracts.VisitSettlement` at
  `/api/rehmed`, served by `EhOsContract.Plug` behind `EhOsContract.Auth.Plug`, which
  verifies the bearer credential. Nothing else lives here — this project has no other
  frontend, and `docs/adr/architecture.md` §16-17 puts frontends outside the engine
  regardless.
  """

  use Phoenix.Router

  import Plug.Conn
  import Phoenix.Controller

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
  end

  # No session and no CSRF, and `accepts` says json. Each is the opposite of what the
  # dashboard's pipeline needs, which is why this is a second pipeline rather than a
  # second route in the first one.
  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/" do
    pipe_through :browser
    import EhOsContract.Web.Router

    eh_os_contract_dashboard "/dashboard", resolver: EhOsContractHostWeb.Resolver
  end

  # The same, and the credential verified before anything is routed.
  pipeline :commands do
    plug :accepts, ["json"]
    plug EhOsContract.Auth.Plug
  end

  scope "/api/rehmed" do
    pipe_through :commands
    forward "/", EhOsContract.Plug, contracts: [Rehmed.Contracts.VisitSettlement]
  end

  scope "/" do
    pipe_through :api
    import EhOsContract.Web.Router

    eh_os_contract_api "/api/eh_os_contract", resolver: EhOsContractHostWeb.Resolver
  end
end
