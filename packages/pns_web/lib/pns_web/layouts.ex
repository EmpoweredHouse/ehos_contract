defmodule PNS.Web.Layouts do
  @moduledoc """
  The dashboard's own root layout, isolated from whatever layout the host
  application already has — `pns_dashboard/2` wires this in explicitly via
  `root_layout:`, the same isolation `oban_web` ships.
  """

  use Phoenix.Component

  embed_templates "layouts/*"
end
