defmodule BusRig.Shop do
  @moduledoc """
  **Invented**, like the rest of `BusRig`: the shop's domain. Its name is the
  namespace of what it publishes (D11), `bus_rig_shop.…`.
  """

  use EhosContract.Domain, name: :bus_rig_shop, language: :en

  context :sales, "Sales", subdomain: :core

  actor :clerk, :human, "Clerk"

  subdomain :core, "Core", type: :core
end
