defmodule EhOsContract.ScenarioQueryTest do
  @moduledoc """
  A query's scenario held to its declaration, as dispatch holds the query: a query
  returning one answers a row or nil, never a list of one.
  """

  use EhOsContract.DataCase, async: false

  alias DispatchRig.Ledger

  test "a scenario of a query returning one fails on a list" do
    scenario =
      Enum.find(EhOsContract.Model.fetch(Ledger).scenarios, &(&1.target.name == :balance_of))

    assert EhOsContract.ScenarioCase.run(Ledger, scenario)

    Process.put(:dispatch_rig_as_list, true)

    assert_raise ExUnit.AssertionError, ~r/answered \[/, fn ->
      EhOsContract.ScenarioCase.run(Ledger, scenario)
    end
  end
end
