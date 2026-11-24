defmodule BusRig.Warehouse do
  @moduledoc """
  **Invented**, like the rest of `BusRig`: the warehouse's domain, another application
  than the shop's, `bus_rig_warehouse.…`.
  """

  use EhosContract.Domain, name: :bus_rig_warehouse, language: :en

  context :stock, "Stock", subdomain: :core

  actor :keeper, :human, "Keeper"

  subdomain :core, "Core", type: :core
end
