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

  scope "/" do
    pipe_through :browser
    import PNS.Web.Router

    pns_dashboard("/pns")
  end
end
