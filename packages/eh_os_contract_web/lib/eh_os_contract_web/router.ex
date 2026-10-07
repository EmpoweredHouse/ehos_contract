defmodule EhOsContract.Web.Router do
  @moduledoc """
  The two macros a host's router imports: `eh_os_contract_dashboard/2` for the screens,
  `eh_os_contract_api/2` for the JSON API. Each needs a pipeline of its own.
  """

  # `live_session`'s `session: {module, function, args}` has Phoenix call `__session__/3`
  # itself, with the real `conn`, on every mount and reconnect, so no separate plug stores
  # anything in the session. The call shape is `oban_dashboard/2`'s.

  @doc """
  Mounts the dashboard at `path`, in a scope with the host's browser pipeline:

      scope "/" do
        pipe_through :browser
        import EhOsContract.Web.Router

        eh_os_contract_dashboard "/dashboard", resolver: MyApp.EhOsContractResolver
      end

  The screens are `path <> "/contract"` and `path <> "/graph"`; `path` itself redirects
  to the first, keeping its query string.

  Options:

    * `:resolver` (required): a module implementing `EhOsContract.Web.Resolver`, asked
      on every mount and reconnect who the caller is and what they may see. A permission
      changed between the first render and a reconnect applies at once.
    * `:on_mount`: the host's own `on_mount` hooks, run after the access check, so no
      hook sees a socket the resolver refused.

  The dashboard's script and stylesheet are not served through this macro: a route
  behind `protect_from_forgery` refuses to serve JavaScript. The host serves them at
  its endpoint, before the router:

      plug Plug.Static,
        at: "/eh_os_contract_web/assets",
        from: {:eh_os_contract_web, "priv/static/assets"},
        gzip: false
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
  Mounts the read-only JSON API at `path`, in a scope of its own whose pipeline accepts
  JSON. A browser pipeline would not do: `plug :accepts, ["html"]` answers 406 to an API
  client before the route is reached.

      pipeline :eh_os_contract_api do
        plug :accepts, ["json"]
      end

      scope "/" do
        pipe_through :eh_os_contract_api
        import EhOsContract.Web.Router

        eh_os_contract_api "/api", resolver: MyApp.EhOsContractResolver
      end

  `:resolver` (required) is the dashboard's: every route asks it first, and a caller it
  refuses gets 403 with `{"error": "forbidden"}`. The routes, all `GET`:

  | Route | Answers |
  | --- | --- |
  | `<path>/conformance?contract=<id>&since=<ISO 8601>&until=<ISO 8601>` | the contract's conformance report as data (`EhOsContract.Conformance.as_data/2`); `contract` may be left out when one contract is registered; `since` and `until` are optional |
  | `<path>/model` | every contract, with its version and its model document's digest |
  | `<path>/model/<id>` | the contract's model document (`EhOsContract.Model.to_data/1`) |
  | `<path>/openapi` | every contract, with its version and its OpenAPI document's digest |
  | `<path>/openapi/<id>` | the contract's OpenAPI document |
  | `<path>/asyncapi` | every contract, with its version and its AsyncAPI document's digest |
  | `<path>/asyncapi/<id>` | the contract's AsyncAPI document |

  A document carries its digest in `info["x-eh-os-contract-digest"]` (the model in
  `"digest"`) and as its `ETag`, so a consumer compares what an instance serves with
  what its build recorded with a `HEAD` and no body. A contract id not registered is
  404 with `{"error": "not_found", "detail": ...}`; a conformance parameter that does
  not parse is 400 with `{"error": "bad_request", "detail": ...}`.

  None of it is business data, but all of it is the client's business in its own
  words, and the conformance report carries event counts per version with timestamps,
  the volume of the business. The resolver decides who sees it; nothing is redacted.

  This macro adds no `Plug.Parsers`, as the dashboard adds no `Plug.Static`: the host's
  pipeline is the host's, and these routes have no body to parse.
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

      get path <> "/model", EhOsContract.Web.Api.Model, resolver: resolver, base_path: path

      get path <> "/model/:contract",
          EhOsContract.Web.Api.Model,
          resolver: resolver,
          base_path: path

      get path <> "/openapi", EhOsContract.Web.Api.OpenAPI, resolver: resolver, base_path: path

      get path <> "/openapi/:contract",
          EhOsContract.Web.Api.OpenAPI,
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
