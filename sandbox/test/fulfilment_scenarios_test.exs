# The invented fulfilment (`Fulfilment`): one test per scenario of each of its contracts
# and its process module, run against its implementations.

defmodule Fulfilment.OrdersScenariosTest do
  @moduledoc false
  use EhosContract.ScenarioCase, contract: Fulfilment.Contracts.Orders
end

defmodule Fulfilment.WarehouseScenariosTest do
  @moduledoc false
  use EhosContract.ScenarioCase, contract: Fulfilment.Contracts.Warehouse
end

defmodule Fulfilment.ShippingScenariosTest do
  @moduledoc false
  use EhosContract.ScenarioCase, contract: Fulfilment.Contracts.Shipping
end

defmodule Fulfilment.OrderProcessScenariosTest do
  @moduledoc false
  use EhosContract.ScenarioCase, process: Fulfilment.Processes.Order
end
