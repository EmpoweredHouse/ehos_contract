defmodule Rehmed.ContractExamplesTest do
  @moduledoc """
  The same generator as `Taxvision.ContractExamplesTest`, pointed at the second
  domain — because *an example is a test* is meant to be a property of the DSL and
  not of one contract's tooling.

  Only `VisitSettlement` has a rule. The other two Rehmed contracts declare none,
  and the reason is in their moduledocs: a rule points at a pure function, and
  Rehmed has no domain code beyond the one decision this file exercises.
  """

  use ExUnit.Case, async: true

  @contract Rehmed.Contracts.VisitSettlement

  for {example, index} <- Enum.with_index(@contract.examples()) do
    @example example
    @rule @contract.rule(example.rule)

    test "#{example.rule}: #{example.description} (##{index})" do
      PNS.ContractExample.run(@example, @rule)
    end
  end

  test "every rule has at least one example — the §18 gate works in this domain too" do
    for rule <- @contract.rules() do
      assert @contract.examples_for(rule.name) != [],
             "rule #{inspect(rule.name)} compiled with no example, and should not have"
    end
  end
end
