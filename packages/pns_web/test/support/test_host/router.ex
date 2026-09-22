defmodule PNS.Web.TestHost.Router do
  @moduledoc """
  Mounts `pns_dashboard/2` for real, with `PNS.Web.Plug.Authenticate` in its
  own pipeline — dogfooding the "optional convenience" plug rather than
  leaving it untested because the real work happens in `on_mount`.
  """

  use Phoenix.Router

  import Plug.Conn
  import Phoenix.Controller

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug PNS.Web.Plug.Authenticate
  end

  # No session, no CSRF, and `accepts` says json rather than html. Each of those is
  # the opposite of what the dashboard needs, which is why the API mounts in its own
  # scope rather than beside the screens. `PNS.Web.Plug.Authenticate` appears in
  # both, which is the point: it is meant to work without a session, and mounting it
  # here is what found that it did not.
  pipeline :pns_api do
    plug :accepts, ["json"]
    plug PNS.Web.Plug.Authenticate
  end

  scope "/" do
    pipe_through :browser
    import PNS.Web.Router

    pns_dashboard("/pns")
  end

  scope "/" do
    pipe_through :pns_api
    import PNS.Web.Router

    pns_api("/pns/api")
  end
end
