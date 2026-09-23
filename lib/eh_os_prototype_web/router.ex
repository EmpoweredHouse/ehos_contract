defmodule EhOsPrototypeWeb.Router do
  @moduledoc """
  Two mounts, both from `eh_os_contract_web`: the dashboard at `/dashboard` for a person, and
  the read-only conformance API at `/api/eh_os_contract` for anything that is not one.
  Nothing else lives here — this project has no other frontend, and
  `docs/adr/architecture.md` §16-17 puts frontends outside the engine regardless.
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

    eh_os_contract_dashboard "/dashboard", resolver: EhOsPrototypeWeb.Resolver
  end

  scope "/" do
    pipe_through :api
    import EhOsContract.Web.Router

    eh_os_contract_api "/api/eh_os_contract", resolver: EhOsPrototypeWeb.Resolver
  end
end
