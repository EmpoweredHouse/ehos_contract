defmodule PNS.Web.Plug.Authenticate do
  @moduledoc """
  Optional convenience, not a required link in the chain — exactly like a
  host in Oban decides for itself how `conn.assigns.current_user` gets
  filled. Reads a bearer token from the `authorization` header, verifies it
  through `PNS.Auth.verify/1`, and assigns the resulting actor.

  A host with its own session mechanism is free to ignore this plug entirely
  and fill `conn.assigns[:pns_actor]` however it already does.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with [header] <- get_req_header(conn, "authorization"),
         "Bearer " <> token <- header,
         {:ok, actor} <- PNS.Auth.verify(token) do
      assign(conn, :pns_actor, actor)
    else
      _ -> conn
    end
  end
end
