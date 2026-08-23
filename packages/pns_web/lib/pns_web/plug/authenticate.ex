defmodule PNS.Web.Plug.Authenticate do
  @moduledoc """
  Optional convenience, not a required link in the chain — exactly like a
  host in Oban decides for itself how `conn.assigns.current_user` gets
  filled. Reads a bearer token — from the `authorization` header, or,
  failing that, from the session key `PNS.Web.LocalLogin` writes — verifies
  it through `PNS.Auth.verify/1`, and assigns the resulting actor.

  The session fallback exists for exactly one caller: the provisional login
  screen has nothing but a browser's cookies to persist a token across
  requests with, unlike an API client that can just keep sending the
  header. It reads the same key regardless of who put it there, so it
  costs nothing once a real login screen writes to that key instead.

  A host with its own session mechanism is free to ignore this plug entirely
  and fill `conn.assigns[:pns_actor]` however it already does.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with token when is_binary(token) <- bearer_token(conn) || session_token(conn),
         {:ok, actor} <- PNS.Auth.verify(token) do
      assign(conn, :pns_actor, actor)
    else
      _ -> conn
    end
  end

  @spec bearer_token(Plug.Conn.t()) :: String.t() | nil
  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _ -> nil
    end
  end

  @spec session_token(Plug.Conn.t()) :: String.t() | nil
  defp session_token(conn), do: get_session(conn, :pns_local_token)
end
