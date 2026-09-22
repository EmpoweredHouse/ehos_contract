defmodule PNS.Web.Router do
  @moduledoc """
  `pns_dashboard/2`, mountable in a host's own router — call-shape identical
  to `oban_dashboard/2`. No separate plug stores a token in the session:
  `live_session`'s `session: {module, function, args}` has Phoenix call
  `__session__/2` itself, with the real `conn`, on every mount and reconnect.
  """

  @doc """
  Mounts the dashboard at `path`: `path <> "/contract"` and
  `path <> "/accounts"` for the two screens, `path` itself redirecting to
  the first — both are named siblings, so neither reads as more canonical
  than the other by virtue of owning the bare mount path. `opts[:resolver]`
  defaults to `PNS.Web.Resolvers.Default`; `opts[:on_mount]` is appended
  after `PNS.Web.Authentication`, which always runs first so access is
  decided before any host-supplied hook sees the socket.

  The compiled JS bundle (`mix assets.build`, shipped under `priv/static/`)
  is **not** served through this macro. It was, briefly — as a `forward`
  nested in whatever pipeline the caller's scope already carries — until
  that turned out to route it through `protect_from_forgery`, and `Plug`'s
  own cross-origin-script guard refuses to serve JavaScript through a
  CSRF-protected route on principle (`Plug.CSRFProtection.InvalidCrossOriginRequestError`).
  Real Phoenix apps serve static files at the **endpoint**, before the
  router runs at all, for exactly this reason. A host adds one line to its
  own endpoint, the same shape as `PNS.Web.Plug.Authenticate` in a router
  pipeline:

      plug Plug.Static,
        at: "/pns_web/assets",
        from: {:pns_web, "priv/static/assets"},
        gzip: false

  (`test/support/test_host/endpoint.ex` carries the same line, so this
  package's own suite proves the instruction rather than assuming it.)
  """
  defmacro pns_dashboard(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      resolver = Keyword.get(opts, :resolver, PNS.Web.Resolvers.Default)

      # Ahead of any access check — a bookmark to the bare mount path should
      # not need to be a decision, just a pointer to whichever screen is
      # first among equals.
      get path, PNS.Web.Router.RedirectToContract, path <> "/contract"

      # The provisional login (PNS.Web.LocalLogin's moduledoc) — one plug,
      # both verbs, because it decides GET-vs-POST for itself. Outside the
      # live_session below on purpose: it has to be reachable by someone
      # `PNS.Web.Authentication` would otherwise turn away.
      match :*, path <> "/login", PNS.Web.LocalLogin,
        action: path <> "/login",
        redirect_to: path <> "/contract"

      get path <> "/logout", PNS.Web.Router.Logout, path <> "/login"

      scope path do
        import Phoenix.LiveView.Router

        live_session :pns_dashboard,
          session: {PNS.Web.Router, :__session__, [resolver, path]},
          root_layout: {PNS.Web.Layouts, :root},
          on_mount: [PNS.Web.Authentication | Keyword.get(opts, :on_mount, [])] do
          live "/contract", PNS.Web.Live.ContractStatus, :index
          live "/accounts", PNS.Web.Live.Accounts, :index
          live "/graph", PNS.Web.Live.Graph, :index
        end
      end
    end
  end

  @doc false
  @spec __session__(Plug.Conn.t(), module(), String.t()) :: %{String.t() => term()}
  def __session__(conn, resolver, path) do
    %{"resolver" => resolver, "user" => resolver.resolve_user(conn), "base_path" => path}
  end

  @doc """
  Mounts the read-only conformance API at `path`: `path <> "/conformance"`.

  Separate from `pns_dashboard/2` and mounted in its own scope on purpose, because
  the two need opposite pipelines. A dashboard route wants a session and CSRF
  protection; a JSON route wants neither, and `plug :accepts, ["html"]` — which any
  ordinary `:browser` pipeline carries — answers 406 to an API client before the
  route is even reached.

      pipeline :pns_api do
        plug :accepts, ["json"]
        plug PNS.Web.Plug.Authenticate
      end

      scope "/" do
        pipe_through :pns_api
        import PNS.Web.Router

        pns_api "/pns/api"
      end

  This macro adds no `Plug.Parsers` of its own, for the reason the dashboard adds no
  `Plug.Static`: a mountable package reaching into the host's pipeline is
  presumptuous, and these are GET routes with no body to parse anyway.
  """
  defmacro pns_api(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      resolver = Keyword.get(opts, :resolver, PNS.Web.Resolvers.Default)

      get path <> "/conformance",
          PNS.Web.Api.Conformance,
          resolver: resolver,
          base_path: path

      # The index first: a bare `/asyncapi` must not be read as a contract named "".
      get path <> "/asyncapi", PNS.Web.Api.AsyncAPI, resolver: resolver, base_path: path

      get path <> "/asyncapi/:contract",
          PNS.Web.Api.AsyncAPI,
          resolver: resolver,
          base_path: path
    end
  end

  defmodule RedirectToContract do
    @moduledoc false
    @behaviour Plug

    @impl true
    def init(to), do: to

    # The query string travels with the redirect — a deep link with
    # `?since=...&until=...` (or, today, a resolver reading a token from a
    # param instead of a header) landing on the index and silently losing
    # it would be a worse bug than the asymmetry this redirect exists to
    # fix.
    @impl true
    def call(%{query_string: ""} = conn, to), do: do_redirect(conn, to)
    def call(conn, to), do: do_redirect(conn, to <> "?" <> conn.query_string)

    defp do_redirect(conn, to) do
      conn
      |> Phoenix.Controller.redirect(to: to)
      |> Plug.Conn.halt()
    end
  end

  defmodule Logout do
    @moduledoc false
    @behaviour Plug

    @impl true
    def init(to), do: to

    @impl true
    def call(conn, to) do
      conn
      |> Plug.Conn.delete_session(:pns_local_token)
      |> Phoenix.Controller.redirect(to: to)
      |> Plug.Conn.halt()
    end
  end
end
