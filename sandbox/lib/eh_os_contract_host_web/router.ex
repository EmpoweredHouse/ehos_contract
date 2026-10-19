defmodule EhOsContractHostWeb.Router do
  @moduledoc """
  Three mounts. Two from `eh_os_contract_web`: the dashboard at `/dashboard` for a person,
  and the read-only conformance API at `/api/eh_os_contract` for anything that is not one.
  And the commands, recordings and queries of the sandbox's domains, each at
  `/api/<domain>` (`/api/fulfilment`, `/api/rehmed`, …), served by `EhOsContract.Plug`
  behind `EhOsContract.Auth.Plug`, which verifies the bearer credential. Nothing else
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
    import EhOsContract.Web.Router

    eh_os_contract_dashboard "/dashboard", resolver: EhOsContractHostWeb.Resolver
  end

  # The same, and the credential verified before anything is routed.
  pipeline :commands do
    plug :accepts, ["json"]
    plug EhOsContract.Auth.Plug
  end

  scope "/api/fulfilment" do
    pipe_through :commands

    forward "/", EhOsContract.Plug,
      contracts: [
        Fulfilment.Contracts.Orders,
        Fulfilment.Contracts.Warehouse,
        Fulfilment.Contracts.Shipping
      ]
  end

  scope "/api/rehmed" do
    pipe_through :commands

    forward "/", EhOsContract.Plug,
      contracts: [
        Rehmed.Contracts.Scheduling,
        Rehmed.Contracts.ClinicalDocumentation,
        Rehmed.Contracts.StatutoryReporting,
        Rehmed.Contracts.Settlement,
        Rehmed.Contracts.ExternalPayers
      ]
  end

  scope "/api/taxvision" do
    pipe_through :commands

    forward "/", EhOsContract.Plug,
      contracts: [Taxvision.Contracts.RegistryWatch, Taxvision.Contracts.AccountingMonth]
  end

  scope "/" do
    pipe_through :api
    import EhOsContract.Web.Router

    eh_os_contract_api "/api/eh_os_contract", resolver: EhOsContractHostWeb.Resolver
  end
end
