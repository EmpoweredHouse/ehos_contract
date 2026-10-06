defmodule EhOsContract.ScaleTest do
  @moduledoc """
  **Volume, and the two instants a report's period is bounded by** — on a v2 promise,
  whose runs come from `eh_os_contract_event_runs` rather than from the event row.

  Everything else is exercised at the scale of a handful of runs, which is the scale at
  which an accidental `Enum.map` over a query result is invisible. These are the shapes
  that stop being free: one run holding ten thousand facts, and an evaluation over
  fifty thousand runs. On v2 the run is a join, so a join that multiplied rows or a
  grouping that collapsed them would show here first.

  The period boundaries are here because they are the same kind of question asked of a
  different axis: what happens at the exact edge. Both bounds are inclusive, which has a
  consequence for anybody generating consecutive periods and is pinned below rather
  than left to be discovered by a number that is off by one event.
  """

  use EhOsContract.DataCase, async: false

  alias ProcessShapes.Promised

  @promise :completed_or_refusal_notified
  @received ~U[2026-07-01 09:00:00.000000Z]
  @long_after ~U[2026-07-10 09:00:00.000000Z]

  # Written directly rather than dispatched: dispatching ten thousand commands would
  # exercise authorization, the deciders and the policies ten thousand times, and none
  # of those is under test here. What is under test is the evaluator on a log of that
  # size. `record_events!/1` appends through `EhOsContract.Store`, so every row comes
  # with its home run, as a dispatched one does.
  #
  # Then `ANALYZE`, because the rows are the test transaction's and the planner's
  # statistics are not: they describe whatever the tables held when autovacuum last
  # looked, usually nothing. On a v2 promise the run is a join, and with statistics
  # that say "almost empty" the planner may pick a nested loop that compares every run
  # with every event — seen 29 September 2026 as seventeen seconds and a cancelled
  # query, then gone once autovacuum had run, so not reproducible on demand. `ANALYZE`
  # inside the transaction counts its own rows, which is what a real log's statistics
  # would say. It writes planner statistics, not data, and they outlive the rollback.
  defp bulk_insert(rows) do
    record_events!(rows)
    EhOsContract.TestRepo.query!("ANALYZE eh_os_contract_events, eh_os_contract_event_runs")
  end

  defp row(name, request_id, at) do
    %{
      type: "process_shapes.promised.#{name}",
      contract: inspect(Promised),
      contract_version: EhOsContract.Model.fetch(Promised).version,
      process: "handling",
      instance_id: "handling|#{request_id}",
      payload: %{"request_id" => request_id},
      occurred_at: at
    }
  end

  defp evaluate(opts), do: EhOsContract.Trace.evaluate(Promised, @promise, opts)

  describe "one run holding ten thousand facts" do
    test "still produces exactly one verdict, anchored on the earliest occurrence" do
      # Ten thousand repetitions of one event in one run is not exotic — it is what a
      # monthly settlement run looks like at a client with real traffic. The run gets
      # one verdict rather than ten thousand, and the window opens on the **first**
      # occurrence rather than on whichever row the database returned first.
      #
      # The second is the one with teeth. Anchoring on the last occurrence would let a
      # process outrun its own deadline for ever by recording `from` again.
      later =
        for n <- 1..9_999, do: row(:request_received, "r-1", DateTime.add(@received, n, :second))

      bulk_insert([row(:request_received, "r-1", @received) | later])
      bulk_insert([row(:request_completed, "r-1", ~U[2026-07-01 12:00:00.000000Z])])

      assert [verdict] = evaluate(now: @long_after)
      assert verdict.from_at == @received
      assert verdict.verdict == :satisfied
    end
  end

  describe "fifty thousand runs" do
    test "every one of them is judged, and the summary counts them all" do
      # The denominator is the number this product reports on, so a summary that
      # silently lost runs — a query limit, a grouping that collapsed keys, a map that
      # overwrote — would understate the problem while looking healthy.
      bulk_insert(for n <- 1..50_000, do: row(:request_received, "r-#{n}", @received))

      summary = [now: @long_after] |> evaluate() |> EhOsContract.Trace.summary()

      assert summary.instances == 50_000
      assert summary.violated == 50_000
    end
  end

  describe "the two instants that bound a report period" do
    setup do
      bulk_insert([
        row(:request_received, "at-since", ~U[2026-07-01 00:00:00.000000Z]),
        row(:request_received, "at-until", ~U[2026-07-31 23:59:59.999999Z]),
        row(:request_received, "before", ~U[2026-06-30 23:59:59.999999Z]),
        row(:request_received, "after", ~U[2026-08-01 00:00:00.000000Z])
      ])

      :ok
    end

    test "both bounds are inclusive, and one microsecond outside either is excluded" do
      # A period is a closed interval on both sides: an event on the first instant of
      # the month belongs to that month, and a report that dropped it would be off by
      # one in the direction of good news.
      judged =
        [
          since: ~U[2026-07-01 00:00:00.000000Z],
          until: ~U[2026-07-31 23:59:59.999999Z],
          now: @long_after
        ]
        |> evaluate()
        |> Enum.map(& &1.instance_id)

      assert "handling|at-since" in judged
      assert "handling|at-until" in judged
      refute "handling|before" in judged
      refute "handling|after" in judged
    end

    test "two periods sharing a boundary instant both count the event on it" do
      # Today's behaviour, and the reason the inclusivity above is worth stating out
      # loud. Anybody writing `until: end_of_july, since: end_of_july` for consecutive
      # reports counts the event on that instant twice. Not a defect in the engine —
      # the caller gives the bounds, and a closed interval is a defensible reading of
      # "the period from X to Y" — but one waiting for whoever generates them.
      boundary = ~U[2026-07-31 23:59:59.999999Z]

      first = evaluate(since: @received, until: boundary, now: @long_after)

      second =
        evaluate(since: boundary, until: ~U[2026-08-31 23:59:59.999999Z], now: @long_after)

      assert "handling|at-until" in Enum.map(first, & &1.instance_id)
      assert "handling|at-until" in Enum.map(second, & &1.instance_id)
    end
  end
end
