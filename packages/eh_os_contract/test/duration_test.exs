defmodule EhOsContract.DurationTest do
  @moduledoc """
  The units, and the prose made out of them.

  `humanize/1` moved here from `EhOsContract.Report`, where the plurals were listed by hand
  for `:month` and `:day` and every other unit fell through to a branch that
  produced **"within 24 hour"**. It survived four contracts because none of them
  used hours until the fourth — the same shape of miss as `within: {1, :month}`,
  which also compiled until somebody wrote it.
  """

  use ExUnit.Case, async: true

  describe "units" do
    test "only what converts to seconds without a calendar" do
      assert Enum.sort(EhOsContract.Duration.units()) == [:day, :hour, :minute, :second]
    end

    test "shifting a moment is plain seconds, because the log is UTC" do
      at = ~U[2026-07-01 09:00:00Z]

      assert EhOsContract.Duration.shift(at, {24, :hour}) == ~U[2026-07-02 09:00:00Z]
      assert EhOsContract.Duration.shift(at, {2, :day}) == ~U[2026-07-03 09:00:00Z]
    end

    test "a calendar unit raises, with the reason rather than a type error" do
      assert_raise ArgumentError, ~r/unsupported time unit :month/, fn ->
        EhOsContract.Duration.shift(~U[2026-07-01 09:00:00Z], {1, :month})
      end
    end
  end

  describe "humanize" do
    test "hours are pluralised — the defect this function was extracted to fix" do
      assert EhOsContract.Duration.humanize({24, :hour}) == "24 hours"
    end

    test "every unit pluralises, none of them listed by hand" do
      assert EhOsContract.Duration.humanize({2, :day}) == "2 days"
      assert EhOsContract.Duration.humanize({30, :second}) == "30 seconds"
      assert EhOsContract.Duration.humanize({15, :minute}) == "15 minutes"
    end

    test "a count of one drops the numeral, because both callers put a word in front" do
      # "Due: every month", not "Due: every 1 month".
      assert EhOsContract.Duration.humanize({1, :month}) == "month"
      assert EhOsContract.Duration.humanize({1, :day}) == "day"
    end

    test "months are readable although `within` refuses them, because `cadence` takes them" do
      assert EhOsContract.Duration.humanize({3, :month}) == "3 months"
    end
  end
end
