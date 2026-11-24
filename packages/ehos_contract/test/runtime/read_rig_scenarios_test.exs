defmodule EhosContract.ReadRigScenariosTest do
  @moduledoc """
  Plan DD, T2a (#240): `ReadRig.Orders`' scenarios, run against its implementation. A
  command that reads a product is decided with the row its scenario gives by
  `given_entity`, as dispatch decides it with the host's.
  """

  use EhosContract.ScenarioCase, contract: ReadRig.Orders
end
