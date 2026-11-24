defmodule EhosContract.PromiseTest do
  @moduledoc """
  A v2 `promise` judged on the new log (v2 §13, plan E7c): **the scenarios v1's
  `trace` was judged on, with the verdicts v1 gave them.** Until v1 went (plan E11a)
  each ran on v1's shape too, with the same assertions: that was the acceptance
  criterion "the same scenarios give the same numbers of verdicts".

  The runs come from `ehos_contract_event_runs`, filed under the id of
  `ProcessShapes.Handling`, the process module that keeps the promise since plan DD,
  P2g (#228); the arithmetic is `EhosContract.Trace`'s.
  """

  use EhosContract.DataCase, async: false
  use Oban.Testing, repo: EhosContract.TestRepo

  alias ProcessShapes.Seed

  @promise :completed_or_refusal_notified
  @start ~U[2026-07-01 09:00:00.000000Z]

  defp evaluate(opts \\ []),
    do: EhosContract.Trace.evaluate(ProcessShapes.Handling, @promise, opts)

  describe "the promise" do
    setup do: Seed.deploy()

    test "a refused request is satisfied through or_else, not violated" do
      Seed.request("r-1", :request_refused)
      Seed.run_queue()

      assert [verdict] = evaluate()
      assert verdict.verdict == :satisfied
      assert verdict.via == :or_else
      assert verdict.instance_id == "process_shapes.handling|r-1"
    end

    test "a completed request is satisfied through eventually" do
      Seed.request("r-1", :request_approved)

      assert [%{verdict: :satisfied, via: :eventually}] = evaluate()
    end

    test "two runs, two ways of being satisfied, and they do not mix" do
      Seed.request("r-1", :request_approved)
      Seed.request("r-2", :request_refused)
      Seed.run_queue()

      by_instance = Map.new(evaluate(), &{&1.instance_id, &1})
      assert by_instance["process_shapes.handling|r-1"].via == :eventually
      assert by_instance["process_shapes.handling|r-2"].via == :or_else

      assert EhosContract.Trace.summary(evaluate()) == %{
               satisfied: 2,
               satisfied_via_eventually: 1,
               satisfied_via_or_else: 1,
               violated: 0,
               pending: 0,
               suspended: 0,
               instances: 2
             }
    end

    test "while the or_else waits after the transaction the verdict is pending" do
      Seed.request("r-1", :request_refused)
      assert [%{verdict: :pending}] = evaluate()

      Seed.run_queue()
      assert [%{verdict: :satisfied, via: :or_else}] = evaluate()
    end

    test "before the window elapses the verdict is pending, after it violated" do
      Seed.fact(:request_received, "r-1", @start)

      assert [pending] = evaluate(now: DateTime.add(@start, 1, :day))
      assert pending.verdict == :pending
      assert pending.deadline_at == DateTime.add(@start, 2, :day)

      assert [%{verdict: :violated, via: nil}] =
               evaluate(now: DateTime.add(@start, 3, :day))
    end

    test "an ending after the deadline does not rescue the promise" do
      Seed.fact(:request_received, "r-1", @start)
      Seed.fact(:request_completed, "r-1", DateTime.add(@start, 5, :day))

      assert [%{verdict: :violated}] = evaluate(now: DateTime.add(@start, 6, :day))
    end

    test "a repeated from does not move the deadline" do
      Seed.fact(:request_received, "r-1", @start)
      Seed.fact(:request_received, "r-1", DateTime.add(@start, 10, :day))

      assert [verdict] = evaluate(now: DateTime.add(@start, 11, :day))
      assert verdict.verdict == :violated
      assert verdict.from_at == @start
    end

    test "or_else is bound by the deadline too" do
      Seed.fact(:request_received, "r-1", @start)
      Seed.fact(:refusal_notified, "r-1", DateTime.add(@start, 4, :day))

      assert [%{verdict: :violated}] = evaluate(now: DateTime.add(@start, 5, :day))
    end

    test "a run with no from is not judged, and an empty log is no verdict" do
      assert evaluate() == []

      Seed.fact(:request_completed, "r-9", @start)
      assert evaluate(now: DateTime.add(@start, 30, :day)) == []
    end

    test "since and until bound the rows, and instance narrows to one run" do
      Seed.fact(:request_received, "r-1", @start)
      Seed.fact(:request_received, "r-2", DateTime.add(@start, 10, :day))
      now = DateTime.add(@start, 20, :day)

      assert [%{instance_id: "process_shapes.handling|r-2"}] =
               evaluate(now: now, since: DateTime.add(@start, 5, :day))

      assert [%{instance_id: "process_shapes.handling|r-1"}] =
               evaluate(now: now, until: DateTime.add(@start, 5, :day))

      assert [%{instance_id: "process_shapes.handling|r-2"}] =
               evaluate(now: now, instance: "process_shapes.handling|r-2")
    end
  end

  describe "a process module" do
    test "names its promise, and refuses one it does not declare" do
      assert_raise ArgumentError, ~r/does not declare promise :nothing/, fn ->
        EhosContract.Trace.evaluate(ProcessShapes.Handling, :nothing)
      end
    end
  end
end
