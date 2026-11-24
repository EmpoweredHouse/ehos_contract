defmodule EhosContract.Web.Router do
  @moduledoc """
  The two macros a host's router imports: `ehos_contract_dashboard/2` for the screens,
  `ehos_contract_api/2` for the JSON API. Each needs a pipeline of its own.
  """

  # `live_session`'s `session: {module, function, args}` has Phoenix call `__session__/3`
  # itself, with the real `conn`, so no separate plug stores anything in the session. It
  # runs on the HTTP request only: a reconnect or a live navigation gets the session signed
  # into the page back, so `resolve_user/1` is asked once per page load and
  # `resolve_access/2` on every mount. The call shape is `oban_dashboard/2`'s.

  @doc """
  Mounts the dashboard at `path`, in a scope with the host's browser pipeline:

      scope "/" do
        pipe_through :browser
        import EhosContract.Web.Router

        ehos_contract_dashboard "/dashboard", resolver: MyApp.EhosContractResolver
      end

  The screens are `path <> "/contract"` and `path <> "/graph"`; `path` itself redirects
  to the first, keeping its query string. Mounted in a scope with a path of its own,
  `scope "/admin"`, the dashboard is at `/admin/dashboard`, and its redirect, its links
  and the `base_path` the resolver is given all carry the prefix. A scope's alias
  (`scope "/admin", MyAppWeb do`) is not put in front of the package's modules. A
  router may mount it more than once; the mounts share their route helpers' names, so
  link to the second by its path.

  Options:

    * `:resolver` (required): a module implementing `EhosContract.Web.Resolver`. Who
      the caller is (`resolve_user/1`) is asked on a full page load and kept in the page;
      what they may see (`resolve_access/2`) is asked again on every mount, a reconnect
      and a move between the screens included.
    * `:on_mount`: the host's own `on_mount` hooks, run after the access check, so no
      hook sees a socket the resolver refused.

  The dashboard's script and stylesheet are not served through this macro: a route
  behind `protect_from_forgery` refuses to serve JavaScript. The host serves them at
  its endpoint, before the router:

      plug Plug.Static,
        at: "/ehos_contract_web/assets",
        from: {:ehos_contract_web, "priv/static/assets"},
        gzip: false
  """
  defmacro ehos_contract_dashboard(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      resolver = Keyword.fetch!(opts, :resolver)
      # The path a browser sees: `path` under every scope the host mounted it in. The
      # redirect, the screens' links and the resolver's `base_path` all need it, and a
      # route alone does not carry it.
      mounted = EhosContract.Web.Router.__mounted__(__MODULE__, path)

      # `alias: false`: the modules below are named in full, and a host's scope alias
      # (`scope "/admin", MyAppWeb do`) would otherwise be put in front of them.
      scope "/", alias: false do
        # Ahead of any access check — a bookmark to the bare mount path should
        # not need to be a decision, just a pointer to whichever screen is
        # first among equals.
        get path, EhosContract.Web.Router.RedirectToContract, mounted <> "/contract"

        scope path do
          import Phoenix.LiveView.Router

          # Named after where it is mounted, so a router may mount the dashboard twice.
          live_session :"ehos_contract_dashboard:#{mounted}",
            session: {EhosContract.Web.Router, :__session__, [resolver, mounted]},
            root_layout: {EhosContract.Web.Layouts, :root},
            on_mount: [EhosContract.Web.Authentication | Keyword.get(opts, :on_mount, [])] do
            live "/contract", EhosContract.Web.Live.ContractStatus, :index
            live "/graph", EhosContract.Web.Live.Graph, :index
          end
        end
      end
    end
  end

  # The path a browser sees, without a trailing slash: `path` under every scope it is
  # mounted in, so `"/dashboard/"` and `"/dashboard"` give one `base_path`, and a
  # dashboard mounted at `"/"` links to `/contract`, not `//contract`.
  @doc false
  @spec __mounted__(module(), String.t()) :: String.t()
  def __mounted__(router, path) do
    router |> Phoenix.Router.scoped_path(path) |> String.trim_trailing("/")
  end

  @doc false
  @spec __session__(Plug.Conn.t(), module(), String.t()) :: %{String.t() => term()}
  def __session__(conn, resolver, path) do
    %{"resolver" => resolver, "user" => resolver.resolve_user(conn), "base_path" => path}
  end

  @doc """
  Mounts the read-only JSON API at `path`, in a scope of its own whose pipeline accepts
  JSON. A browser pipeline would not do: `plug :accepts, ["html"]` answers 406 to an API
  client before the route is reached.

      pipeline :ehos_contract_api do
        plug :accepts, ["json"]
      end

      scope "/" do
        pipe_through :ehos_contract_api
        import EhosContract.Web.Router

        ehos_contract_api "/api", resolver: MyApp.EhosContractResolver
      end

  `:resolver` (required) is the dashboard's: every route asks it first, and a caller it
  refuses gets 403 with `{"error": "forbidden"}`. The routes, all `GET`:

  | Route | Answers |
  | --- | --- |
  | `<path>/conformance?contract=<id>&since=<ISO 8601>&until=<ISO 8601>` | the contract's conformance report as data (`EhosContract.Conformance.as_data/2`); `contract` may be left out when one contract is registered; `since` and `until` are optional |
  | `<path>/conformance?process=<id>&since=<ISO 8601>&until=<ISO 8601>` | a process module's conformance report, keyed `"process"` where a contract's is keyed `"contract"`; naming both is a bad request |
  | `<path>/model` | every contract, with its version and its model document's digest |
  | `<path>/model/<id>` | the contract's model document (`EhosContract.Model.to_data/1`) |
  | `<path>/openapi` | every contract, with its version and its OpenAPI document's digest |
  | `<path>/openapi/<id>` | the contract's OpenAPI document |
  | `<path>/asyncapi` | every contract, with its version and its AsyncAPI document's digest |
  | `<path>/asyncapi/<id>` | the contract's AsyncAPI document |
  | `<path>/graph` | every contract, process module and domain: its version, its document's digest |
  | `<path>/graph/<id>` | the contract's graph document (`EhosContract.Graph.Document`) |
  | `<path>/graph/<id>/overlay?since=<ISO 8601>&until=<ISO 8601>` | what the log says over the contract's graph document (`EhosContract.Graph.Overlay`) |
  | `<path>/graph/process/<id>` | the process module's graph document |
  | `<path>/graph/process/<id>/overlay?since=<ISO 8601>&until=<ISO 8601>` | what the log says over it |
  | `<path>/graph/domain/<module>` | the domain's graph document |
  | `<path>/graph/domain/<module>/overlay?since=<ISO 8601>&until=<ISO 8601>` | what the log says over the domain's graph document |

  A document carries its digest in `info["x-ehos-contract-digest"]` (the model and a
  graph document in `"digest"`) and as its `ETag`, so a consumer compares what an
  instance serves with what its build recorded with a `HEAD` and no body. An overlay has
  neither: the log moves under it, and one whose `since` is after its `until` is 400. A
  contract or process module id not registered is 404 with `{"error": "not_found",
  "detail": ...}` on the document routes. On `conformance`, an unknown contract or
  process, both named at once, or a parameter that does not parse, is 400 with
  `{"error": "bad_request", "detail": ...}`.

  None of it is business data, but all of it is the client's business in its own
  words, and the conformance report carries event counts per version with timestamps,
  the volume of the business. The resolver decides who sees it; nothing is redacted.

  This macro adds no `Plug.Parsers`, as the dashboard adds no `Plug.Static`: the host's
  pipeline is the host's, and these routes have no body to parse.
  """
  defmacro ehos_contract_api(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      resolver = Keyword.fetch!(opts, :resolver)
      # As the dashboard's: the resolver is given the path a client sees.
      mounted = EhosContract.Web.Router.__mounted__(__MODULE__, path)

      # As the dashboard's: a host's scope alias is not put in front of these modules.
      scope "/", alias: false do
        get path <> "/conformance",
            EhosContract.Web.Api.Conformance,
            resolver: resolver,
            base_path: mounted

        # The index first: a bare `/asyncapi` must not be read as a contract named "".
        get path <> "/asyncapi", EhosContract.Web.Api.AsyncAPI,
          resolver: resolver,
          base_path: mounted

        get path <> "/asyncapi/:contract",
            EhosContract.Web.Api.AsyncAPI,
            resolver: resolver,
            base_path: mounted

        get path <> "/model", EhosContract.Web.Api.Model, resolver: resolver, base_path: mounted

        get path <> "/model/:contract",
            EhosContract.Web.Api.Model,
            resolver: resolver,
            base_path: mounted

        get path <> "/openapi", EhosContract.Web.Api.OpenAPI,
          resolver: resolver,
          base_path: mounted

        # A domain's and a process module's routes before a contract's: `graph/domain/X`
        # is not a contract named "domain" with an overlay. A process module has its own
        # path since its id may be a contract's too.
        get path <> "/graph", EhosContract.Web.Api.Graph, resolver: resolver, base_path: mounted

        get path <> "/graph/process/:process",
            EhosContract.Web.Api.Graph,
            resolver: resolver,
            base_path: mounted,
            of: :process

        get path <> "/graph/process/:process/overlay",
            EhosContract.Web.Api.Graph,
            resolver: resolver,
            base_path: mounted,
            of: :process,
            overlay: true

        get path <> "/graph/domain/:domain",
            EhosContract.Web.Api.Graph,
            resolver: resolver,
            base_path: mounted,
            of: :domain

        get path <> "/graph/domain/:domain/overlay",
            EhosContract.Web.Api.Graph,
            resolver: resolver,
            base_path: mounted,
            of: :domain,
            overlay: true

        get path <> "/graph/:contract",
            EhosContract.Web.Api.Graph,
            resolver: resolver,
            base_path: mounted

        get path <> "/graph/:contract/overlay",
            EhosContract.Web.Api.Graph,
            resolver: resolver,
            base_path: mounted,
            overlay: true

        get path <> "/openapi/:contract",
            EhosContract.Web.Api.OpenAPI,
            resolver: resolver,
            base_path: mounted
      end
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
