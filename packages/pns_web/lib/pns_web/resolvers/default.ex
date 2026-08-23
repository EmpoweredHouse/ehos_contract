defmodule PNS.Web.Resolvers.Default do
  @moduledoc """
  Reads `PNS.Auth.Actor` off `conn.assigns[:pns_actor]` and maps two
  placeholder roles to access levels.

  The role names are stand-ins — the real vocabulary belongs to the accounts
  screen, not to this foundation.
  """

  @behaviour PNS.Web.Resolver

  @impl true
  @spec resolve_user(Plug.Conn.t()) :: PNS.Auth.Actor.t() | nil
  def resolve_user(conn), do: conn.assigns[:pns_actor]

  @impl true
  @spec resolve_access(PNS.Auth.Actor.t() | term(), String.t()) ::
          :all | :read_only | {:forbidden, String.t()}
  def resolve_access(%PNS.Auth.Actor{} = actor, base_path) do
    cond do
      PNS.Auth.entitled?(actor, :pns_admin) -> :all
      PNS.Auth.entitled?(actor, :pns_read) -> :read_only
      true -> {:forbidden, "#{base_path}/login"}
    end
  end

  def resolve_access(_, base_path), do: {:forbidden, "#{base_path}/login"}
end
