defmodule EhOsContract.TraceTest do
  @moduledoc """
  Stage 1.5: **evaluating `trace` assertions per run.**

  There is one acceptance criterion and it is the first test below: with a refused
  request the assertion is **satisfied through `or_else`**, not violated. A refusal
  is a correct ending, just not the one we wanted — and a tool that shouts about
  every correctly refused run gets switched off within a week.

  The rest of the tests pin the semantic decisions, each of which can be reversed
  without breaking anything else.
  """

  use EhOsContract.DataCase, async: false
  use Oban.Testing, repo: EhOsContract.TestRepo

  alias ProcessShapes.Promised, as: Contract

  @assertion :completed_or_refusal_notified

  # The request edge: one command, two facts. Approving reaches the ordinary
  # ending inside the transaction; refusing leaves the ending in the queue.
  defp request(id, decision) do
    EhOsContract.emit_all(Contract, [
      EhOsContract.event(:request_received, %{request_id: id}),
      EhOsContract.event(decision, %{request_id: id})
    ])
  end

  # The refusal notice goes out through an **asynchronous** handler, so `or_else`
  # does not exist in the log until the job runs. In tests jobs stay put
  # (`testing: :manual`), which is an advantage here: it separates "the agreement
  # was kept" from "the agreement is about to be kept".
  defp run_jobs, do: Oban.drain_queue(queue: :events)

  defp evaluate(opts \\ []), do: EhOsContract.Trace.evaluate(Contract, @assertion, opts)

  describe "acceptance criterion" do
    test "a refused request is SATISFIED through or_else, not violated" do
      request("r-1", :request_refused)
      run_jobs()

      assert [verdict] = evaluate()

      assert verdict.verdict == :satisfied,
             "refusing is a correct ending of the process, not a broken agreement"

      assert verdict.via == :or_else
      assert verdict.instance_id == "handling|r-1"
    end

    test "a completed request is satisfied through eventually" do
      request("r-1", :request_approved)

      assert [verdict] = evaluate()
      assert verdict.verdict == :satisfied
      assert verdict.via == :eventually
    end

    test "two runs, two different ways of being satisfied — and they do not mix" do
      # This is 1.1 and 1.5 tied together: without run identity this assertion
      # would be counted once, globally, and would credit both runs the same way.
      request("r-1", :request_approved)
      request("r-2", :request_refused)
      run_jobs()

      by_instance = Map.new(evaluate(), &{&1.instance_id, &1})

      assert by_instance["handling|r-1"].via == :eventually
      assert by_instance["handling|r-2"].via == :or_else

      assert EhOsContract.Trace.summary(evaluate()) == %{
               satisfied: 2,
               satisfied_via_eventually: 1,
               satisfied_via_or_else: 1,
               violated: 0,
               pending: 0,
               # Since stage 1.5b. Reported separately and never folded into `violated`,
               # because a suspended run is the one the client is not answerable for.
               suspended: 0,
               instances: 2
             }
    end
  end

  describe "leaving the BEAM process boundary" do
    test "while the `or_else` job sits in the queue the verdict is `pending`" do
      # This is the same lesson as the overlay's fourth state: "not yet" looks
      # identical in the log to "never". The decision to refuse has been taken, but
      # the notice has not gone out, so the agreement is not **yet** kept — and the
      # verdict has no business claiming that it is.
      request("r-1", :request_refused)

      assert [verdict] = evaluate()
      assert verdict.verdict == :pending

      # And once the job has run, the same assertion is satisfied. The cost of
      # asynchrony is named: a job wedged past the window counts as a violation —
      # correctly, because the notice really did not go out.
      run_jobs()
      assert [%{verdict: :satisfied, via: :or_else}] = evaluate()
    end
  end

  describe "the window" do
    # Events inserted directly, because that is the only way to set `occurred_at`.
    defp fact(type, request_id, at) do
      record_event!(%{
        type: to_string(type),
        contract: inspect(Contract),
        contract_version: Contract.version(),
        process: "handling",
        instance_id: "handling|#{request_id}",
        correlation_id: Ecto.UUID.generate(),
        payload: %{"request_id" => request_id},
        occurred_at: at
      })
    end

    @start ~U[2026-07-01 09:00:00.000000Z]

    test "before the window elapses the verdict is `pending`, not `violated`" do
      fact(:request_received, "r-1", @start)

      assert [verdict] = evaluate(now: DateTime.add(@start, 1, :day))
      assert verdict.verdict == :pending
      assert verdict.deadline_at == DateTime.add(@start, 2, :day)
    end

    test "after the window elapses with neither ending, the verdict is `violated`" do
      fact(:request_received, "r-1", @start)

      assert [verdict] = evaluate(now: DateTime.add(@start, 3, :day))
      assert verdict.verdict == :violated
      assert verdict.via == nil
    end

    test "an ending after the deadline does not rescue the assertion" do
      fact(:request_received, "r-1", @start)
      fact(:request_completed, "r-1", DateTime.add(@start, 5, :day))

      assert [verdict] = evaluate(now: DateTime.add(@start, 6, :day))
      assert verdict.verdict == :violated
    end

    test "a repeated `from` does NOT move the deadline" do
      # If the window ran from the last occurrence, a process could outrun its own
      # deadline forever by simply emitting `from` again — and this assertion
      # could never be violated.
      fact(:request_received, "r-1", @start)
      fact(:request_received, "r-1", DateTime.add(@start, 10, :day))

      assert [verdict] = evaluate(now: DateTime.add(@start, 11, :day))
      assert verdict.verdict == :violated
      assert verdict.from_at == @start
    end

    test "`or_else` is bound by the deadline too" do
      # A decision for the process owner to confirm: "within two days, X or Y"
      # means both are meant to fit. Otherwise the deadline is useless.
      fact(:request_received, "r-1", @start)
      fact(:refusal_notified, "r-1", DateTime.add(@start, 4, :day))

      assert [verdict] = evaluate(now: DateTime.add(@start, 5, :day))
      assert verdict.verdict == :violated
    end
  end

  describe "the assertion is conditional" do
    test "a run with no `from` is not evaluated at all" do
      # It is neither satisfied nor violated — there is nothing to judge. Counting
      # it as a violation would raise an alarm for every case not yet started.
      fact(:request_completed, "r-9", @start)

      assert evaluate(now: DateTime.add(@start, 30, :day)) == []
    end

    test "an empty log is zero verdicts, not zero violations" do
      assert evaluate() == []
      assert EhOsContract.Trace.summary(evaluate()).instances == 0
    end
  end

  describe "every contract" do
    test "the second domain's assertions are evaluated by the same code" do
      request("r-1", :request_approved)

      all = EhOsContract.Trace.evaluate_all()
      names = Enum.map(all, & &1.trace) |> Enum.sort()

      # Three contracts declare assertions here. `submission_reaches_inspection`
      # is the shapes rig, and it is where the `:suspended` verdict is exercised;
      # the two medical ones belong to the invented universality gate, which has no
      # implementation at all.
      assert names == [
               :completed_or_refusal_notified,
               :episode_reaches_an_end,
               :referral_reaches_a_decision,
               :submission_reaches_inspection
             ]

      # A contract with no implementation has no runs to judge — and that is zero
      # verdicts, not zero violations. `UniversalityGate.TreatmentEpisode` is the
      # invented medical domain that proved the vocabulary needs no new words, and
      # it deliberately has no handlers.
      unimplemented = Enum.filter(all, &(&1.contract == UniversalityGate.TreatmentEpisode))

      assert unimplemented != []
      assert Enum.all?(unimplemented, &(&1.verdicts == []))
    end
  end
end
