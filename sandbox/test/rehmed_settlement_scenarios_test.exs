defmodule Rehmed.SettlementScenariosTest do
  @moduledoc """
  One test per scenario of `Rehmed.Contracts.Settlement`, run against its
  implementations. "Every rule has an example" is rule S8, which refuses to compile
  an invariant no scenario rejects on; the query's scenario projects into the
  sandbox's own table and is rolled back.
  """

  use EhOsContract.ScenarioCase, contract: Rehmed.Contracts.Settlement
end
