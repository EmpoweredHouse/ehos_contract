defmodule AppuniteEquipment.ComputersScenariosTest do
  @moduledoc """
  One test per scenario of `AppuniteEquipment.Contracts.Computers`, run against
  `AppuniteEquipment.Inventory.Computer`.
  """

  use EhOsContract.ScenarioCase, contract: AppuniteEquipment.Contracts.Computers
end

defmodule AppuniteEquipment.DomainValuesTest do
  @moduledoc """
  One test per example of `AppuniteEquipment.Domain`'s value invariants: an old
  twelve-character and a new ten-character serial number pass, a lowercase or a
  spaced one does not.
  """

  use EhOsContract.ScenarioCase, domain: AppuniteEquipment.Domain
end

defmodule AppuniteEquipment.DemandsScenariosTest do
  @moduledoc """
  One test per scenario of `AppuniteEquipment.Contracts.Demands`, run against its
  implementations in `AppuniteEquipment.Demanding`.
  """

  use EhOsContract.ScenarioCase, contract: AppuniteEquipment.Contracts.Demands
end
