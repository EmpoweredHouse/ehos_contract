defmodule PnsPrototypeWeb.Router do
  @moduledoc """
  The one route this host has: the dashboard, mounted at `/dashboard`.
  Nothing else lives here — this project has no other frontend yet, and
  `docs/adr/architecture.md` §16-17 puts frontends outside the engine
  regardless.
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

    pns_dashboard "/dashboard"
  end
end
