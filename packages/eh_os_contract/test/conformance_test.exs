defmodule EhOsContract.ConformanceTest do
  @moduledoc """
  Stage 1.4: **behavioural path verification, per run.**

  The acceptance criterion is sharp and is the first block below: with 50 runs,
  none of which entered the refusal branch, the report shows **one** untraversed
  path. With one run in that branch — **none**.

  This is also the test of whether the declared-versus-observed difference is
  signal or noise — the ADR's falsification condition. Fifty runs, one line of
  report. If the report showed fifty or three, the answer would be "noise".

  The volume is simulated, but **the process is not**: the runs go through a
  contract with handlers, three declared paths and an asynchronous ending, of
  which an ordinary run traverses two. Until 2026-08-21 that contract was
  TaxVision's; it is now `ProcessShapes.Promised`, which has the same ratio and
  belongs to the engine. A contract designed against its own acceptance criterion
  would always meet it, which is why the ratio comes from the shape rather than
  from the criterion.
  """

  use EhOsContract.DataCase, async: false
  use Oban.Testing, repo: EhOsContract.TestRepo

  alias ProcessShapes.Promised

  @refusal_path {:request_refused, :refusal_notified}

  # The request edge: one command, two facts, no cause between them. Approving
  # reaches the ordinary ending inside the transaction; refusing leaves the
  # ending in the queue.
  defp request(id, decision) do
    EhOsContract.emit_all(Promised, [
      EhOsContract.event(:request_received, %{request_id: id}),
      EhOsContract.event(decision, %{request_id: id})
    ])
  end

  defp report do
    [r] = EhOsContract.Conformance.untraversed_paths() |> Enum.filter(&(&1.process == :handling))
    r
  end

  defp paths(report), do: Enum.map(report.untraversed, &{&1.from, &1.to})

  describe "acceptance criterion" do
    test "50 runs, none in the refusal branch — exactly one untraversed path" do
      for n <- 1..50, do: request("r-#{n}", :request_approved)

      r = report()

      assert r.instances == 50
      assert r.basis == :runs
      assert paths(r) == [@refusal_path]

      # The point: the report has **one** line, not fifty and not three. If it
      # counted per event type, this one path would still come out — but with 49
      # ordinary runs and one refusal (the test below) it would not.
      assert length(r.untraversed) == 1
    end

    test "one run through the refusal branch — no untraversed paths" do
      for n <- 1..49, do: request("r-#{n}", :request_approved)
      request("r-50", :request_refused)
      # The notification goes through an asynchronous handler, so the path only
      # closes once the job has run.
      Oban.drain_queue(queue: :events)

      r = report()

      assert r.instances == 50
      assert r.untraversed == []
      assert r.in_flight == []
    end
  end

  describe "two situations where the report easily lies" do
    test "zero runs is no basis, not three findings" do
      r = report()

      assert r.instances == 0
      assert r.basis == :no_runs

      assert r.untraversed == [],
             "a process that never started has every path untraversed — listing them " <>
               "turns \"no data\" into \"we have three problems\""

      assert r.paths == 3
    end

    test "a job waiting in the queue is not an untraversed path" do
      request("r-1", :request_refused)

      r = report()

      refute @refusal_path in paths(r),
             "a queued job is \"not yet\", not \"never\" — without that the report lies " <>
               "on every ordinary delay"

      assert Enum.map(r.in_flight, &{&1.from, &1.to}) == [@refusal_path]
    end
  end

  describe "the shape of the report" do
    test "undeclared paths do not enter this list" do
      # Drift is a different question on the screen. Mixed into one list it turns
      # the report into a bag where "we did not do it" cannot be told apart from
      # "we did something we never agreed".
      request("r-1", :request_approved)

      record_event!(%{
        type: "event_outside_the_contract",
        contract: inspect(Promised),
        contract_version: Promised.version(),
        correlation_id: Ecto.UUID.generate(),
        causation_id: List.first(events_of(:request_completed)).id,
        payload: %{},
        occurred_at: DateTime.utc_now()
      })

      assert Enum.all?(report().untraversed, & &1.handler)
    end

    test "one report per process rather than one global list" do
      # Notes §9: "navigation is per-process, never global".
      request("r-1", :request_approved)

      processes = EhOsContract.Conformance.untraversed_paths() |> Enum.map(& &1.process)
      assert :handling in processes
    end
  end
end
