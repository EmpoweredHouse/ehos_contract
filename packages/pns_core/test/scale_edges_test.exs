defmodule PNS.ScaleEdgesTest do
  @moduledoc """
  **Volume, and the two instants a report's period is bounded by.**

  Everything else in this repository is exercised at the scale of a handful of runs,
  which is the scale at which an accidental `Enum.map` over a query result is
  invisible. These are the shapes that stop being free: one run holding ten thousand
  facts, and an evaluation over fifty thousand runs.

  The period boundaries are here rather than in a report test because they are the
  same kind of question asked of a different axis: what happens at the exact edge.
  Both bounds are inclusive, which has a consequence for anybody generating
  consecutive periods and is pinned below rather than left to be discovered by a
  number that is off by one event.

  The fixture is invented and stays out of the registry — it exists to be filled with
  rows, and it makes no claim about anybody's process.
  """

  use PNS.DataCase, async: false

  defmodule Bulk do
    @moduledoc "# INVENTED. Two events and a window, so that rows have somewhere to go."

    use PNS.Contract

    event :opened, label: "Opened", payload: %{case_id: :id}, process: :bulk
    event :closed, label: "Closed", payload: %{case_id: :id}, process: :bulk, terminal: true

    trace :closes_within_a_day do
      from :opened
      eventually :closed, within: {1, :day}
    end

    process :bulk, label: "Bulk", instance: [:case_id]
  end

  @opened ~U[2026-07-01 09:00:00.000000Z]
  @long_after ~U[2026-07-10 09:00:00.000000Z]

  # `insert_all` rather than `PNS.emit!`: emitting ten thousand facts would exercise
  # dispatch, the cycle guard and telemetry ten thousand times, and none of those is
  # what is under test here. What is under test is the evaluator's behaviour on a log
  # of that size, so the log is written directly.
  defp bulk_insert(rows) do
    rows
    |> Enum.chunk_every(2_000)
    |> Enum.each(&Repo.insert_all(PNS.Event, &1))
  end

  defp row(type, case_id, at) do
    %{
      id: Ecto.UUID.generate(),
      type: to_string(type),
      contract: inspect(Bulk),
      contract_version: Bulk.version(),
      process: "bulk",
      instance_id: "bulk|#{case_id}",
      correlation_id: Ecto.UUID.generate(),
      payload: %{"case_id" => case_id},
      occurred_at: at
    }
  end

  describe "one run holding ten thousand facts" do
    test "still produces exactly one verdict, anchored on the earliest occurrence" do
      # Ten thousand repetitions of one event in one run is not exotic — it is what a
      # monthly settlement run looks like at a client with real traffic. Two things have
      # to hold and neither is obvious from reading the evaluator: the run gets one
      # verdict rather than ten thousand, and the window opens on the **first**
      # occurrence rather than on whichever row the database returned first.
      #
      # The second is the one with teeth. Anchoring on the last occurrence would let a
      # process outrun its own deadline for ever by emitting `from` again, which is
      # exactly what a repeated check does.
      later = for n <- 1..9_999, do: row(:opened, "c-1", DateTime.add(@opened, n, :second))
      bulk_insert([row(:opened, "c-1", @opened) | later])
      bulk_insert([row(:closed, "c-1", ~U[2026-07-01 12:00:00.000000Z])])

      assert [verdict] = PNS.Trace.evaluate(Bulk, :closes_within_a_day, now: @long_after)
      assert verdict.from_at == @opened
      assert verdict.verdict == :satisfied
    end
  end

  describe "fifty thousand runs" do
    test "every one of them is judged, and the summary counts them all" do
      # The denominator is the number this product reports on, so a summary that silently
      # lost runs — a query limit, a grouping that collapsed keys, a map that overwrote —
      # would understate the problem while looking healthy. Fifty thousand is enough for
      # a default page size or an integer assumption to show itself and small enough to
      # keep the suite honest about its own cost.
      bulk_insert(for n <- 1..50_000, do: row(:opened, "c-#{n}", @opened))

      summary =
        Bulk
        |> PNS.Trace.evaluate(:closes_within_a_day, now: @long_after)
        |> PNS.Trace.summary()

      assert summary.instances == 50_000
      assert summary.violated == 50_000
    end
  end

  describe "the two instants that bound a report period" do
    setup do
      bulk_insert([
        row(:opened, "at-since", ~U[2026-07-01 00:00:00.000000Z]),
        row(:opened, "at-until", ~U[2026-07-31 23:59:59.999999Z]),
        row(:opened, "before", ~U[2026-06-30 23:59:59.999999Z]),
        row(:opened, "after", ~U[2026-08-01 00:00:00.000000Z])
      ])

      :ok
    end

    test "both bounds are inclusive, and one microsecond outside either is excluded" do
      # A period is a closed interval on both sides. The consequence for whoever
      # generates consecutive periods is in the next test; the consequence here is
      # simpler — an event on the first instant of the month belongs to that month, and
      # a report that dropped it would be off by one in the direction of good news
      # exactly when a month starts with its own opening.
      judged =
        Bulk
        |> PNS.Trace.evaluate(:closes_within_a_day,
          since: ~U[2026-07-01 00:00:00.000000Z],
          until: ~U[2026-07-31 23:59:59.999999Z],
          now: @long_after
        )
        |> Enum.map(& &1.instance_id)

      assert "bulk|at-since" in judged
      assert "bulk|at-until" in judged
      refute "bulk|before" in judged
      refute "bulk|after" in judged
    end

    test "two periods sharing a boundary instant both count the event on it" do
      # Today's behaviour, and the reason the inclusivity above is worth stating out
      # loud. Anybody writing `until: end_of_july, since: end_of_july` for consecutive
      # reports counts the event on that instant twice, and the two reports then disagree
      # with the sum of the log by exactly one run.
      #
      # Not a defect in the engine: the bounds are given by the caller and a closed
      # interval is a defensible reading of "the period from X to Y". It is a defect
      # waiting for whoever generates the bounds, which is why it is pinned here rather
      # than argued about later.
      boundary = ~U[2026-07-31 23:59:59.999999Z]

      first =
        PNS.Trace.evaluate(Bulk, :closes_within_a_day,
          since: @opened,
          until: boundary,
          now: @long_after
        )

      second =
        PNS.Trace.evaluate(Bulk, :closes_within_a_day,
          since: boundary,
          until: ~U[2026-08-31 23:59:59.999999Z],
          now: @long_after
        )

      assert "bulk|at-until" in Enum.map(first, & &1.instance_id)
      assert "bulk|at-until" in Enum.map(second, & &1.instance_id)
    end
  end
end
