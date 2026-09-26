defmodule EhOsContract.PromiseTest do
  @moduledoc """
  A v2 `promise` judged on the new log (v2 §13, plan E7c): **the scenarios of
  `trace_test.exs`, on `ProcessShapes.Promised` and on its v2 port, with the same
  expected verdicts.** Each test below runs once per shape, and its assertions are
  the same for both: that is the acceptance criterion "the same scenarios give the
  same numbers of verdicts".

  On v2 the runs come from `eh_os_contract_event_runs` and the types are
  `"handling.<event>"`; the arithmetic is `EhOsContract.Trace`'s, shared.
  """

  use EhOsContract.DataCase, async: false
  use Oban.Testing, repo: EhOsContract.TestRepo

  alias ProcessShapes.Seed

  @promise :completed_or_refusal_notified
  @start ~U[2026-07-01 09:00:00.000000Z]

  defp evaluate(shape, opts \\ []),
    do: EhOsContract.Trace.evaluate(Seed.promised(shape), @promise, opts)

  for shape <- [:v1, :v2] do
    describe "#{shape}:" do
      @describetag shape: shape

      setup %{shape: shape}, do: Seed.deploy(shape)

      test "a refused request is satisfied through or_else, not violated", %{shape: shape} do
        Seed.request(shape, "r-1", :request_refused)
        Seed.run_queue(shape)

        assert [verdict] = evaluate(shape)
        assert verdict.verdict == :satisfied
        assert verdict.via == :or_else
        assert verdict.instance_id == "handling|r-1"
      end

      test "a completed request is satisfied through eventually", %{shape: shape} do
        Seed.request(shape, "r-1", :request_approved)

        assert [%{verdict: :satisfied, via: :eventually}] = evaluate(shape)
      end

      test "two runs, two ways of being satisfied, and they do not mix", %{shape: shape} do
        Seed.request(shape, "r-1", :request_approved)
        Seed.request(shape, "r-2", :request_refused)
        Seed.run_queue(shape)

        by_instance = Map.new(evaluate(shape), &{&1.instance_id, &1})
        assert by_instance["handling|r-1"].via == :eventually
        assert by_instance["handling|r-2"].via == :or_else

        assert EhOsContract.Trace.summary(evaluate(shape)) == %{
                 satisfied: 2,
                 satisfied_via_eventually: 1,
                 satisfied_via_or_else: 1,
                 violated: 0,
                 pending: 0,
                 suspended: 0,
                 instances: 2
               }
      end

      test "while the or_else waits after the transaction the verdict is pending", %{
        shape: shape
      } do
        Seed.request(shape, "r-1", :request_refused)
        assert [%{verdict: :pending}] = evaluate(shape)

        Seed.run_queue(shape)
        assert [%{verdict: :satisfied, via: :or_else}] = evaluate(shape)
      end

      test "before the window elapses the verdict is pending, after it violated", %{
        shape: shape
      } do
        Seed.fact(shape, :request_received, "r-1", @start)

        assert [pending] = evaluate(shape, now: DateTime.add(@start, 1, :day))
        assert pending.verdict == :pending
        assert pending.deadline_at == DateTime.add(@start, 2, :day)

        assert [%{verdict: :violated, via: nil}] =
                 evaluate(shape, now: DateTime.add(@start, 3, :day))
      end

      test "an ending after the deadline does not rescue the promise", %{shape: shape} do
        Seed.fact(shape, :request_received, "r-1", @start)
        Seed.fact(shape, :request_completed, "r-1", DateTime.add(@start, 5, :day))

        assert [%{verdict: :violated}] = evaluate(shape, now: DateTime.add(@start, 6, :day))
      end

      test "a repeated from does not move the deadline", %{shape: shape} do
        Seed.fact(shape, :request_received, "r-1", @start)
        Seed.fact(shape, :request_received, "r-1", DateTime.add(@start, 10, :day))

        assert [verdict] = evaluate(shape, now: DateTime.add(@start, 11, :day))
        assert verdict.verdict == :violated
        assert verdict.from_at == @start
      end

      test "or_else is bound by the deadline too", %{shape: shape} do
        Seed.fact(shape, :request_received, "r-1", @start)
        Seed.fact(shape, :refusal_notified, "r-1", DateTime.add(@start, 4, :day))

        assert [%{verdict: :violated}] = evaluate(shape, now: DateTime.add(@start, 5, :day))
      end

      test "a run with no from is not judged, and an empty log is no verdict", %{shape: shape} do
        assert evaluate(shape) == []

        Seed.fact(shape, :request_completed, "r-9", @start)
        assert evaluate(shape, now: DateTime.add(@start, 30, :day)) == []
      end

      test "since and until bound the rows, and instance narrows to one run", %{shape: shape} do
        Seed.fact(shape, :request_received, "r-1", @start)
        Seed.fact(shape, :request_received, "r-2", DateTime.add(@start, 10, :day))
        now = DateTime.add(@start, 20, :day)

        assert [%{instance_id: "handling|r-2"}] =
                 evaluate(shape, now: now, since: DateTime.add(@start, 5, :day))

        assert [%{instance_id: "handling|r-1"}] =
                 evaluate(shape, now: now, until: DateTime.add(@start, 5, :day))

        assert [%{instance_id: "handling|r-2"}] =
                 evaluate(shape, now: now, instance: "handling|r-2")
      end
    end
  end

  describe "a v2 contract" do
    test "names its promise, and refuses one it does not declare" do
      assert_raise ArgumentError, ~r/does not declare promise :nothing/, fn ->
        EhOsContract.Trace.evaluate(ProcessShapes.Next.Promised, :nothing)
      end
    end

    test "control: a v1 event of the same process and run is not a v2 run's" do
      # Both shapes name their process `handling`, and a v1 event has its home run in
      # the same table. The v2 promise reads its own types only.
      Seed.fact(:v1, :request_received, "r-1", @start)

      assert evaluate(:v2, now: DateTime.add(@start, 3, :day)) == []
      assert [%{verdict: :violated}] = evaluate(:v1, now: DateTime.add(@start, 3, :day))
    end
  end
end
