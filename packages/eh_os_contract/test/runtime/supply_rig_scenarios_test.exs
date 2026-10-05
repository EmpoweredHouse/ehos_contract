defmodule EhOsContract.SupplyRigScenariosTest do
  @moduledoc """
  Plan T1: `SupplyRig.Desk`'s scenario, run against its implementation. A scenario's
  data is the contract's own, so it gives the supplied field as it gives any other.
  """

  use EhOsContract.ScenarioCase, contract: SupplyRig.Desk
end
