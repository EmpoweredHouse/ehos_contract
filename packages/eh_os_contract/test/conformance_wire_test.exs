defmodule EhOsContract.Conformance.WireTest do
  @moduledoc """
  Stage 5.8: **the report as values that survive a wire** — the part of
  `EhOsContract.Conformance.Wire` that is not about any report.

  A value the encoder has no decided shape for raises rather than being guessed at.
  The structural walk over a whole report, which does not assert on any particular
  key and so covers the ones a later stage adds, is in `conformance/wire_v2_test.exs`.
  """

  use ExUnit.Case, async: true

  describe "a shape nobody decided about" do
    test "an undecided tuple raises rather than being guessed at" do
      assert_raise ArgumentError, ~r/has no decided shape on the wire/, fn ->
        EhOsContract.Conformance.Wire.encode(%{a: {1, 2, 3}})
      end
    end

    test "an undecided struct raises too" do
      assert_raise ArgumentError, ~r/has no decided shape on the wire/, fn ->
        EhOsContract.Conformance.Wire.encode(%{a: %Date{year: 2026, month: 9, day: 22}})
      end
    end
  end
end
