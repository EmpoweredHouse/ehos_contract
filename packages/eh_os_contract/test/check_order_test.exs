defmodule EhOsContract.CheckOrderTest do
  @moduledoc """
  `mix eh_os_contract.check` prints its findings in a fixed order: errors, warnings,
  notices, each sorted by text. The order the checks happen to produce them in is
  not stable. Grouping into an atom-keyed map follows atom creation order on OTP 26
  and later, and in E1 that swapped two lines between runs of unchanged code.
  """

  use ExUnit.Case, async: true

  alias EhOsContract.Check.Finding
  alias Mix.Tasks.EhOsContract.Check

  @findings [
    Finding.new("owner-not-a-module", "owner B.Module does not exist"),
    Finding.new("process-without-accountable", "process :b names no `accountable` role"),
    Finding.new("rule-function-missing", "rule :x names X.y/1, which does not exist"),
    Finding.new("owner-not-a-module", "owner A.Module does not exist"),
    Finding.new("process-without-accountable", "process :a names no `accountable` role")
  ]

  test "errors, then warnings, then notices, each by text" do
    assert Enum.map(Check.ordered(@findings), &{&1.level, &1.message}) == [
             {:error, "rule :x names X.y/1, which does not exist"},
             {:warn, "process :a names no `accountable` role"},
             {:warn, "process :b names no `accountable` role"},
             {:info, "owner A.Module does not exist"},
             {:info, "owner B.Module does not exist"}
           ]
  end

  test "the order does not depend on the order the findings arrived in" do
    for _ <- 1..20 do
      assert Check.ordered(Enum.shuffle(@findings)) == Check.ordered(@findings)
    end
  end
end
