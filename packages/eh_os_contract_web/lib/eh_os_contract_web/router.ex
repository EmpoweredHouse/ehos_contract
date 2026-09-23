defmodule EhOsContract.Web.Router do
  @moduledoc """
  `eh_os_contract_dashboard/2`, mountable in a host's own router — call-shape identical
  to `oban_dashboard/2`. No separate plug stores a token in the session:
  `live_session`'s `session: {module, function, args}` has Phoenix call
  `__session__/2` itself, with the real `conn`, on every mount and reconnect.
  """

  @doc """
  Mounts the dashboard at `path`: `path <> "/contract"` and
  `path <> "/graph"` for the two screens, `path` itself redirecting to
  the first — both are named siblings, so neither reads as more canonical
  than the other by virtue of owning the bare mount path. `opts[:resolver]`
  is required — see `EhOsContract.Web.Resolver`; `opts[:on_mount]` is appended
  after `EhOsContract.Web.Authentication`, which always runs first so access is
  decided before any host-supplied hook sees the socket.

  The compiled JS bundle (`mix assets.build`, shipped under `priv/static/`)
  is **not** served through this macro. It was, briefly — as a `forward`
  nested in whatever pipeline the caller's scope already carries — until
  that turned out to route it through `protect_from_forgery`, and `Plug`'s
  own cross-origin-script guard refuses to serve JavaScript through a
  CSRF-protected route on principle (`Plug.CSRFProtection.InvalidCrossOriginRequestError`).
  Real Phoenix apps serve static files at the **endpoint**, before the
  router runs at all, for exactly this reason. A host adds one line to its
  own endpoint:

      plug Plug.Static,
        at: "/eh_os_contract_web/assets",
        from: {:eh_os_contract_web, "priv/static/assets"},
        gzip: false

  (`test/support/test_host/endpoint.ex` carries the same line, so this
  package's own suite proves the instruction rather than assuming it.)
  """
  defmacro eh_os_contract_dashboard(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      resolver = Keyword.fetch!(opts, :resolver)

      # Ahead of any access check — a bookmark to the bare mount path should
      # not need to be a decision, just a pointer to whichever screen is
      # first among equals.
      get path, EhOsContract.Web.Router.RedirectToContract, path <> "/contract"

      scope path do
        import Phoenix.LiveView.Router

        live_session :eh_os_contract_dashboard,
          session: {EhOsContract.Web.Router, :__session__, [resolver, path]},
          root_layout: {EhOsContract.Web.Layouts, :root},
          on_mount: [EhOsContract.Web.Authentication | Keyword.get(opts, :on_mount, [])] do
          live "/contract", EhOsContract.Web.Live.ContractStatus, :index
          live "/graph", EhOsContract.Web.Live.Graph, :index
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

  Separate from `eh_os_contract_dashboard/2` and mounted in its own scope on purpose, because
  the two need opposite pipelines. A dashboard route wants a session and CSRF
  protection; a JSON route wants neither, and `plug :accepts, ["html"]` — which any
  ordinary `:browser` pipeline carries — answers 406 to an API client before the
  route is even reached.

      pipeline :eh_os_contract_api do
        plug :accepts, ["json"]
      end

      scope "/" do
        pipe_through :eh_os_contract_api
        import EhOsContract.Web.Router

        eh_os_contract_api "/api", resolver: MyApp.EhOsContractResolver
      end

  This macro adds no `Plug.Parsers` of its own, for the reason the dashboard adds no
  `Plug.Static`: a mountable package reaching into the host's pipeline is
  presumptuous, and these are GET routes with no body to parse anyway.
  """
  defmacro eh_os_contract_api(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      resolver = Keyword.fetch!(opts, :resolver)

      get path <> "/conformance",
          EhOsContract.Web.Api.Conformance,
          resolver: resolver,
          base_path: path

      # The index first: a bare `/asyncapi` must not be read as a contract named "".
      get path <> "/asyncapi", EhOsContract.Web.Api.AsyncAPI, resolver: resolver, base_path: path

      get path <> "/asyncapi/:contract",
          EhOsContract.Web.Api.AsyncAPI,
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
end
