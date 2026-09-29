defmodule EhOsContract.ImplementationDependencyTest do
  @moduledoc """
  v2 plan, E5, acceptance: **`mix xref graph --label compile-connected` shows no edge
  from a contract to its implementation** (v2 §8). The implementation compiles
  against the contract, and the contract names nothing, not even its domain.

  Read from the package's own fixture, `UniversalityGate`, through the real
  `mix xref` over this build's manifest, so it is the compiler's record and not a
  claim about it.
  """

  use ExUnit.Case, async: true

  @contract "test/support/universality_gate/treatment_episode.ex"
  @implementation "test/support/universality_gate/episode.ex"
  @domain "test/support/universality_gate/domain.ex"

  test "the contract has no compile-time edge to its implementation or its domain" do
    from_contract = xref(["--label", "compile-connected", "--source", @contract])

    refute from_contract =~ @implementation
    refute from_contract =~ @domain

    # Control: the graph is not empty; the contract compiles against the library.
    assert from_contract =~ "lib/eh_os_contract/contract/dsl.ex"
  end

  test "the implementation depends on the contract at compile time" do
    assert xref(["--label", "compile", "--sink", @contract]) =~ @implementation
  end

  defp xref(args) do
    {output, 0} =
      System.cmd("mix", ["xref", "graph", "--no-compile", "--format", "plain" | args],
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    output
  end
end
