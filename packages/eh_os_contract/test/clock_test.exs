defmodule EhOsContract.ClockTest do
  @moduledoc """
  v2 plan, E2: **the time an event is stamped with is chosen before it is written.**

  The log becomes append-only in this stage, so the three test files that used to
  move `occurred_at` with an `UPDATE` now emit in the past through
  `EhOsContract.Clock.at/2`. This file pins what they rely on: the time reaches the
  events a synchronous handler emits and the events a drained job emits, and it
  stops at the end of `at/2`.
  """

  use EhOsContract.DataCase, async: false

  alias EhOsContract.Clock

  @nine ~U[2026-09-01 09:00:00.000000Z]
  @noon ~U[2026-09-01 12:00:00.000000Z]

  test "an event emitted inside at/2 carries that time, and so does its synchronous handler's" do
    Clock.at(@nine, fn ->
      EhOsContract.emit!(ProcessShapes.Timed, :run_started, %{run_id: "r-1"})
    end)

    assert [%{occurred_at: @nine}] = events_of(:run_started)
    assert [%{occurred_at: @nine}] = events_of(:run_acknowledged)
  end

  test "a job drained inside at/2 stamps its events with that time too" do
    Clock.at(@nine, fn ->
      EhOsContract.emit!(ProcessShapes.Promised, :request_received, %{request_id: "r-1"})
      EhOsContract.emit!(ProcessShapes.Promised, :request_refused, %{request_id: "r-1"})
      Oban.drain_queue(queue: :events)
    end)

    emitted_by_jobs = events_of(:refusal_notified)
    assert emitted_by_jobs != [], "the fixture's asynchronous handler emitted nothing"
    assert Enum.all?(emitted_by_jobs, &(&1.occurred_at == @nine))
  end

  test "outside at/2 it is now, and calls nest and restore" do
    before = DateTime.utc_now()
    assert DateTime.compare(Clock.now(), before) != :lt

    Clock.at(@nine, fn ->
      assert Clock.now() == @nine
      Clock.at(@noon, fn -> assert Clock.now() == @noon end)
      assert Clock.now() == @nine
    end)

    assert DateTime.compare(Clock.now(), before) != :lt
  end
end
