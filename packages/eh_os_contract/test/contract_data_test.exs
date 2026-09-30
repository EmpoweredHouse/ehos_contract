defmodule EhOsContract.Contract.DataTest do
  @moduledoc """
  Scenario data of a built-in type (`EhOsContract.Contract.Data`): what a decimal
  written as a string may be.
  """

  use ExUnit.Case, async: true

  alias EhOsContract.Contract.Data

  test "a decimal is digits, a sign and a fraction, and nothing after them" do
    for value <- ["12", "-12", "12.50", 12], do: assert(Data.problems(:decimal, value) == [])

    for value <- ["12\n", "12.", ".5", "1e3", "١٢"] do
      assert [problem] = Data.problems(:decimal, value)
      assert problem =~ "is not a decimal"
    end
  end
end
