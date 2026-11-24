defmodule EhosContract.CheckOrderTest do
  @moduledoc """
  `mix ehos_contract.check` prints its findings in a fixed order: errors, warnings,
  notices, each sorted by text. The order the checks happen to produce them in is
  not stable. Grouping into an atom-keyed map follows atom creation order on OTP 26
  and later, and in E1 that swapped two lines between runs of unchanged code.
  """

  use ExUnit.Case, async: true

  alias EhosContract.Check.Finding
  alias Mix.Tasks.EhosContract.Check

  @findings [
    Finding.new("promise-without-within", "promise :b has no `within`"),
    Finding.new("process-without-accountable", "process :b names no `accountable` role"),
    Finding.compiler({"X2: rule :x names X.y/1, which does not exist", nil}),
    Finding.new("promise-without-within", "promise :a has no `within`"),
    Finding.new("process-without-accountable", "process :a names no `accountable` role")
  ]

  test "errors, then warnings, then notices, each by text" do
    assert Enum.map(Check.ordered(@findings), &{&1.level, &1.message}) == [
             {:error, "rule :x names X.y/1, which does not exist"},
             {:warn, "process :a names no `accountable` role"},
             {:warn, "process :b names no `accountable` role"},
             {:info, "promise :a has no `within`"},
             {:info, "promise :b has no `within`"}
           ]
  end

  test "the order does not depend on the order the findings arrived in" do
    for _ <- 1..20 do
      assert Check.ordered(Enum.shuffle(@findings)) == Check.ordered(@findings)
    end
  end
end
