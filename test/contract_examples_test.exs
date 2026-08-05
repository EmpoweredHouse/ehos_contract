defmodule Taxvision.ContractExamplesTest do
  @moduledoc """
  **An example from the contract IS a test** (ADR §18, notes §6).

  There is not a single hand-written case here. The tests below are generated from
  the `example` declarations while this file compiles — so when the process owner
  corrects an example in the contract, the test changes rather than a description
  of it.

  This is also where §18 turns out to be weaker than it sounds, and that is worth
  recording: the contract holds an **MFA, not a capture**, so as not to depend on
  the domain at compile time. The consequence is that the function is resolved at
  test run time rather than while the contract compiles. The gate "a rule with no
  example does not compile" is true; "an example is a test" is only true with this
  generator. The record claims one thing and delivers one and a half.
  """

  use ExUnit.Case, async: true

  @contract Taxvision.Contracts.AccountingMonth

  for {example, index} <- Enum.with_index(@contract.examples()) do
    @example example
    @rule @contract.rule(example.rule)

    test "#{example.rule}: #{example.description} (##{index})" do
      # Passed as an argument rather than expanded in the test body: a literal in
      # the `case` would let the typechecker treat the other branches as
      # unreachable and bury the output in warnings.
      ContractExamples.run(@example, @rule)
    end
  end

  test "every rule has at least one example — the §18 gate works" do
    for rule <- @contract.rules() do
      assert @contract.examples_for(rule.name) != [],
             "rule #{inspect(rule.name)} compiled with no example, and should not have"
    end
  end
end
