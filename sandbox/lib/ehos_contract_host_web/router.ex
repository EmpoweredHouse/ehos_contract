defmodule EhosContractHostWeb.Router do
  @moduledoc """
  Three mounts. Two from `ehos_contract_web`: the dashboard at `/dashboard` for a person,
  and the read-only conformance API at `/api/ehos_contract` for anything that is not one.
  And the commands, recordings and queries of the sandbox's domains, each at
  `/api/<domain>` (`/api/fulfilment`, `/api/lending`, …), served by `EhosContract.Plug`
  behind `EhosContract.Auth.Plug`, which verifies the bearer credential. Nothing else
  lives here — this project has no other frontend, and `docs/adr/architecture.md` §16-17
  puts frontends outside the engine regardless.
  """

  use Phoenix.Router

  import Plug.Conn
  import Phoenix.Controller

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :content_security_policy
  end

  # EHOS's policy (plan EG3), so the dashboard is looked at here as it runs there: nothing
  # inline, nothing from elsewhere. A diagram that needs an inline style shows up as
  # black boxes on this host first.
  defp content_security_policy(conn, _opts),
    do: put_resp_header(conn, "content-security-policy", "default-src 'self'")

  # No session and no CSRF, and `accepts` says json. Each is the opposite of what the
  # dashboard's pipeline needs, which is why this is a second pipeline rather than a
  # second route in the first one.
  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/" do
    pipe_through :browser
    import EhosContract.Web.Router

    ehos_contract_dashboard "/dashboard", resolver: EhosContractHostWeb.Resolver
  end

  # The same, and the credential verified before anything is routed.
  pipeline :commands do
    plug :accepts, ["json"]
    plug EhosContract.Auth.Plug
  end

  scope "/api/fulfilment" do
    pipe_through :commands

    forward "/", EhosContract.Plug,
      contracts: [
        Fulfilment.Contracts.Orders,
        Fulfilment.Contracts.Warehouse,
        Fulfilment.Contracts.Shipping
      ]
  end

  scope "/api/lending" do
    pipe_through :commands

    forward "/", EhosContract.Plug,
      contracts: [Lending.Contracts.Membership, Lending.Contracts.Circulation]
  end

  scope "/" do
    pipe_through :api
    import EhosContract.Web.Router

    ehos_contract_api "/api/ehos_contract", resolver: EhosContractHostWeb.Resolver
  end
end
