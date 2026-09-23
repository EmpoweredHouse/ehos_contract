defmodule PNS.Web.TestHost.Router do
  @moduledoc """
  Mounts `pns_dashboard/2` and `pns_api/2` for real, with
  `PNS.Web.TestHost.Resolver` as the access rule every host now supplies.
  """

  use Phoenix.Router

  import Plug.Conn
  import Phoenix.Controller

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
  end

  # No session, no CSRF, and `accepts` says json rather than html. Each of those is
  # the opposite of what the dashboard needs, which is why the API mounts in its own
  # scope rather than beside the screens.
  pipeline :pns_api do
    plug :accepts, ["json"]
  end

  scope "/" do
    pipe_through :browser
    import PNS.Web.Router

    pns_dashboard("/pns", resolver: PNS.Web.TestHost.Resolver)
  end

  scope "/" do
    pipe_through :pns_api
    import PNS.Web.Router

    pns_api("/pns/api", resolver: PNS.Web.TestHost.Resolver)
  end
end
