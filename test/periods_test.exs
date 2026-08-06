defmodule Taxvision.PeriodsTest do
  @moduledoc """
  Stage 1.3b: **two modules needing the same data.**

  The last of the five shapes and the only one that could not be exercised on the
  rig: on a fixture I would have duplicated data with a "named source of truth"
  and declared success without learning anything. Real pressure was needed — a
  `period` lives in the events of five TaxVision modules, and cross-module joins
  are forbidden.

  This is also where the product plan's doubt gets settled: **whether the no-join
  rule is bearable.**
  """

  use Taxvision.DataCase, async: false

  alias Taxvision.AccountingMonth.Month
  alias Taxvision.Tasks.Task

  @period "2026-07"

  defp open_month(company) do
    {:ok, _} = Taxvision.Api.open_month(accountant(company), %{company_id: company, period: @period})
  end

  describe "canonicalisation" do
    test "a period is a row, so nothing can be booked into a period that does not exist" do
      # This is the whole gain from turning a string into a row. `"2026-7"` beside
      # `"2026-07"` stops being possible rather than merely discouraged.
      assert_raise ArgumentError, ~r/no period named "2026-13"/, fn ->
        Taxvision.Api.open_month(accountant("c-1"), %{company_id: "c-1", period: "2026-13"})
      end
    end

    test "the date range is derived from the name once, in one place" do
      period = Taxvision.Periods.fetch!(@period)

      assert period.starts_on == ~D[2026-07-01]
      assert period.ends_on == ~D[2026-07-31]
    end

    test "creating the same period twice gives one row" do
      before = Taxvision.Periods.fetch!(@period)
      assert Taxvision.Periods.ensure!(@period) == before
    end
  end

  describe "two modules, the same answer, one source" do
    test "the tasks and the month get the same date, each into its own table" do
      open_month("c-1")

      period = Taxvision.Periods.fetch!(@period)
      [month] = Repo.all(Month)
      tasks = Repo.all(Task)

      assert month.closes_on == period.ends_on
      assert length(tasks) == 4
      assert Enum.all?(tasks, &(&1.due_on == period.ends_on))

      # Two copies of the same truth, in two private tables. This is **strategic
      # duplication**, not a shared table: there is one source of truth and it is
      # named.
      assert month.closes_on == List.first(tasks).due_on
    end
  end

  describe "the price of the no-join rule, measured" do
    test "every module pays with its own query — and that is what N+1 amounts to here" do
      # Notes §14 call N+1 a risk rather than a surprise. Here it is measured
      # rather than described: two modules need the same answer and neither can use
      # the other's query, because they are not allowed to see each other.
      me = self()

      :telemetry.attach(
        "periods-counter",
        [:taxvision, :repo, :query],
        fn _event, _measure, meta, _config ->
          if meta[:source] == "taxvision_periods", do: send(me, :period_query)
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach("periods-counter") end)

      open_month("c-1")

      assert count_queries() == 3,
             "one at the request edge, resolving the period's name to its identifier, " <>
               "and one per module that needs the dates: Taxvision.Tasks and " <>
               "Taxvision.AccountingMonth. Fewer means somebody is passing data around " <>
               "the side; more means N+1 grows faster than notes §14 predict"
    end

    test "the third query is what canonicalisation costs, and it is at the edge" do
      # It was two until 6 August, when a fact started carrying `period_id` instead of the
      # name. The new one is the translation, and it happens **once, at the request edge**
      # — which is the point: past that line nothing in the domain sees the string, so
      # `"2026-7"` beside `"2026-07"` stops being possible rather than being discouraged.
      #
      # Pinned separately from the count above so that if somebody moves the resolution
      # into a handler, the number stays 3 while the reason changes — and this fails.
      me = self()

      :telemetry.attach(
        "periods-by-name",
        [:taxvision, :repo, :query],
        fn _event, _measure, meta, _config ->
          # The **condition**, not the projection. Matching `"name"` anywhere caught all
          # three queries, because every one of them selects the name — the lookups differ
          # in what they filter on, not in what they return.
          if meta[:source] == "taxvision_periods" and meta.query =~ ~s(."name" = ) do
            send(me, :by_name)
          end
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach("periods-by-name") end)

      open_month("c-1")

      # Exactly one lookup by name. Every other read of this table is by identifier.
      assert_received :by_name
      refute_received :by_name
    end

    defp count_queries(counter \\ 0) do
      receive do
        :period_query -> count_queries(counter + 1)
      after
        50 -> counter
      end
    end
  end
end
