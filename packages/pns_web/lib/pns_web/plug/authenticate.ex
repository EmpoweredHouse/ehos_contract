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

  # **Only when a session has been fetched.** `Plug.Conn.get_session/2` raises when
  # `fetch_session` has not run, and this plug is meant to be mountable in a
  # pipeline that has no session at all — an API pipeline is exactly that. Without
  # this guard the plug crashes on every request arriving without a bearer header,
  # which is precisely the unauthenticated request an endpoint most needs to refuse
  # cleanly. Found by mounting it that way in stage 5.8, not by reading it.
  @spec session_token(Plug.Conn.t()) :: String.t() | nil
  # `:plug_session`, not `:plug_session_fetch`. The endpoint's `Plug.Session` sets
  # the latter on every request whether or not anybody fetched a session, so keying
  # on it looks right and guards nothing — which is what the first version of this
  # did, until the API test failed with the exact crash it was meant to prevent.
  defp session_token(%Plug.Conn{private: %{plug_session: _}} = conn),
    do: get_session(conn, :pns_local_token)

  defp session_token(_conn), do: nil
end
