defmodule PNS.Web.Layouts do
  @moduledoc """
  The dashboard's own root layout, isolated from whatever layout the host
  application already has — `pns_dashboard/2` wires this in explicitly via
  `root_layout:`, the same isolation `oban_web` ships.
  """

  use Phoenix.Component

  embed_templates "layouts/*"

  @doc """
  The two-screen nav, shared by both LiveViews rather than duplicated —
  `base_path` comes from the session (`PNS.Web.Router.__session__/3`)
  because a mountable router does not get to assume where the host mounted
  it, the same reason nothing here reaches for `~p`.
  """
  attr :base_path, :string, required: true
  attr :current, :atom, required: true

  def nav(assigns) do
    ~H"""
    <nav>
      <.link navigate={"#{@base_path}/contract"} aria-current={@current == :contract_status && "page"}>
        Contract status
      </.link>
      <.link navigate={"#{@base_path}/graph"} aria-current={@current == :graph && "page"}>
        Graph
      </.link>
    </nav>
    """
  end
end
