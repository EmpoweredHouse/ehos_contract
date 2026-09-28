defmodule Rehmed.ExternalPayersScenariosTest do
  @moduledoc """
  One test per scenario of `Rehmed.Contracts.ExternalPayers`, run against its
  implementation: the boundary's decision over the events each scenario gives.
  """

  use EhOsContract.ScenarioCase, contract: Rehmed.Contracts.ExternalPayers
end
