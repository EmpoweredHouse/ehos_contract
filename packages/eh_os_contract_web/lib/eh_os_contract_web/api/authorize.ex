defmodule EhOsContract.Web.Api.Authorize do
  @moduledoc """
  The dashboard's access decision, applied to a request that is not a page.

  Not `EhOsContract.Web.Authentication`: that is an `on_mount/4` hook keyed on a LiveView
  session map, and there is no socket here. What is shared is the thing that
  matters — the same `EhOsContract.Web.Resolver` callbacks, so a host writes its access rule
  once and both transports obey it.

  ## `{:forbidden, path}` becomes 403, and the path is dropped

  `resolve_access/2` answers with a redirect target because the transport it was
  written for is HTML. A redirect is a datum only a browser can use; an API client
  following it would fetch a login page and try to parse it as JSON, which is the
  most confusing failure available here. So the meaning is kept — *this actor may
  not see this* — and the representation is the transport's to choose.

  A second callback was the alternative and is worse: every host would implement
  two, `@optional_callbacks` would make it one that may silently not exist, and the
  two would drift the first time somebody changed one.

  `:read_only` and `:all` both pass, identically. Redacting for `:read_only` would
  reinterpret a level that today means "may look, may not act", and would be this
  package forming an opinion about how sensitive a client's own data is.
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    resolver = Keyword.fetch!(opts, :resolver)
    base_path = Keyword.fetch!(opts, :base_path)

    case resolver.resolve_access(resolver.resolve_user(conn), base_path) do
      {:forbidden, _redirect_target} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(403, Jason.encode_to_iodata!(%{"error" => "forbidden"}))
        |> halt()

      access when access in [:all, :read_only] ->
        assign(conn, :eh_os_contract_web_access, access)
    end
  end
end
