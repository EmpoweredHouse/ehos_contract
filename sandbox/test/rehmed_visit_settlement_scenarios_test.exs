defmodule Rehmed.VisitSettlementScenariosTest do
  @moduledoc """
  One test per scenario of `Rehmed.Contracts.VisitSettlement`, run against
  `Rehmed.Settlement.VisitSettlement` (v2 §4.5). The successor of the examples test
  of the v1 contract: the four examples are the four scenarios, and "every rule has
  an example" is now rule S8, which refuses to compile an invariant no scenario
  rejects on.
  """

  use EhOsContract.ScenarioCase, contract: Rehmed.Contracts.VisitSettlement
end
