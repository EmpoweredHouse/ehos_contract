defmodule EhosContract.Web.TestHost.Router do
  @moduledoc """
  Mounts `ehos_contract_dashboard/2` and `ehos_contract_api/2` for real, with
  `EhosContract.Web.TestHost.Resolver` as the access rule every host now supplies.
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
  pipeline :ehos_contract_api do
    plug :accepts, ["json"]
  end

  scope "/" do
    pipe_through :browser
    import EhosContract.Web.Router

    ehos_contract_dashboard("/dashboard", resolver: EhosContract.Web.TestHost.Resolver)
  end

  scope "/" do
    pipe_through :ehos_contract_api
    import EhosContract.Web.Router

    ehos_contract_api("/api", resolver: EhosContract.Web.TestHost.Resolver)
  end

  # Both again under a scope with a path of its own, as a host with an admin area
  # mounts them: what a browser follows has to carry the prefix.
  scope "/admin" do
    pipe_through :browser
    import EhosContract.Web.Router

    ehos_contract_dashboard("/dashboard", resolver: EhosContract.Web.TestHost.Resolver)
  end

  scope "/admin" do
    pipe_through :ehos_contract_api
    import EhosContract.Web.Router

    ehos_contract_api("/api", resolver: EhosContract.Web.TestHost.Resolver)
  end

  # A scope with an alias, the usual Phoenix shape (`scope "/", MyAppWeb do`): the
  # package's modules are named in full and must not get the alias in front.
  scope "/aliased", EhosContract.Web.TestHost do
    pipe_through :browser
    import EhosContract.Web.Router

    ehos_contract_dashboard("/dashboard", resolver: EhosContract.Web.TestHost.Resolver)
  end

  scope "/aliased", EhosContract.Web.TestHost do
    pipe_through :ehos_contract_api
    import EhosContract.Web.Router

    ehos_contract_api("/api", resolver: EhosContract.Web.TestHost.Resolver)
  end

  # A mount path written with a trailing slash.
  scope "/" do
    pipe_through :browser
    import EhosContract.Web.Router

    ehos_contract_dashboard("/slashed/", resolver: EhosContract.Web.TestHost.Resolver)
  end
end
