defmodule PNS.Web.Live.Home do
  @moduledoc """
  The only screen this foundation ships: a placeholder proving the mount,
  the resolver, and the access assign work end to end. Its content is not
  in scope — see PLAN.md for what the two real screens will replace it with.
  """

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <p>PNS dashboard foundation — access: {inspect(@pns_web_access)}</p>
    """
  end
end
