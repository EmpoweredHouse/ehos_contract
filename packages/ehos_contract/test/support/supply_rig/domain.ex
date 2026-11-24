defmodule SupplyRig.Domain do
  @moduledoc "**Invented**, like the rest of `SupplyRig`."

  use EhosContract.Domain, name: :supply_rig, language: :en

  context :desk, "Desk", subdomain: :core

  actor :clerk, :human, "Clerk"

  subdomain :core, "Core", type: :core
end
