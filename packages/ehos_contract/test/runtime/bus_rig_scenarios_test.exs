defmodule EhosContract.BusRigShopScenariosTest do
  @moduledoc "The invented shop's scenarios, against its decider."

  use EhosContract.ScenarioCase, contract: BusRig.Orders
end

defmodule EhosContract.BusRigWarehouseScenariosTest do
  @moduledoc """
  The invented warehouse's scenarios: its decider, and its policy on an event another
  application publishes, which a scenario hands it as `on` does a local one.
  """

  use EhosContract.ScenarioCase, contract: BusRig.Stock
end
