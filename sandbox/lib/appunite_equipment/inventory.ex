defmodule AppuniteEquipment.Inventory do
  @moduledoc """
  The implementation of `AppuniteEquipment.Contracts.Computers`: the computer's
  decision, pure, the check of the serial number, and the Inventory tab's
  projection with its query, the one table of this tree. It exists so that the
  contract's scenarios run.
  """

  use Boundary,
    deps: [EhOsContract, AppuniteEquipment.Contracts, AppuniteEquipment.Domain],
    exports: [Computer, SerialNumber, InventoryRows, InventoryList]
end
