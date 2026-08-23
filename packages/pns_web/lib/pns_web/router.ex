defmodule PNS.Web.Router do
  @moduledoc """
  `pns_dashboard/2`, mountable in a host's own router — call-shape identical
  to `oban_dashboard/2`. No separate plug stores a token in the session:
  `live_session`'s `session: {module, function, args}` has Phoenix call
  `__session__/2` itself, with the real `conn`, on every mount and reconnect.
  """

  @doc """
  Mounts the dashboard at `path`. `opts[:resolver]` defaults to
  `PNS.Web.Resolvers.Default`; `opts[:on_mount]` is appended after
  `PNS.Web.Authentication`, which always runs first so access is decided
  before any host-supplied hook sees the socket.
  """
  defmacro pns_dashboard(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      resolver = Keyword.get(opts, :resolver, PNS.Web.Resolvers.Default)

      scope path do
        import Phoenix.LiveView.Router

        live_session :pns_dashboard,
          session: {PNS.Web.Router, :__session__, [resolver, path]},
          root_layout: {PNS.Web.Layouts, :root},
          on_mount: [PNS.Web.Authentication | Keyword.get(opts, :on_mount, [])] do
          live "/", PNS.Web.Live.ContractStatus, :index
          live "/accounts", PNS.Web.Live.Accounts, :index
        end
      end
    end
  end

  @doc false
  @spec __session__(Plug.Conn.t(), module(), String.t()) :: %{String.t() => term()}
  def __session__(conn, resolver, path) do
    %{"resolver" => resolver, "user" => resolver.resolve_user(conn), "base_path" => path}
  end
end
