defmodule PNS.HandlerFailureTest do
  @moduledoc """
  Stage 2.3: **a synchronous handler failure leaves a trace.**

  A synchronous handler runs inside the emitting transaction, so raising takes the
  handling row and the event down with it. That is correct — nothing happened, so the
  log must not claim it did — and it is the one gap ADR §13 found by building the
  third verification layer: the most interesting failure was invisible in the artifact
  that exists to make failures visible.

  The acceptance criterion has two halves that pull against each other, and both are
  pinned below: the failure is recorded **and** the rollback still happens. Recording
  by weakening the rollback would trade a diagnosis gap for a log that lies.
  """

  use Taxvision.DataCase, async: false

  alias ProcessShapes.Rig

  defp flag(case_id, item_no) do
    PNS.emit!(Rig, :item_flagged, %{case_id: case_id, item_no: item_no})
  end

  defp receive_item(case_id) do
    PNS.emit!(Rig, :item_received, %{case_id: case_id, item_no: 1, amount: 100})
  end

  defp failures, do: Repo.all(PNS.HandlerFailure)
  defp logged(type), do: Repo.aggregate(from(e in PNS.Event, where: e.type == ^type), :count)

  defp pairing do
    PNS.Conformance.untraversed_paths() |> Enum.find(&(&1.process == :pairing))
  end

  describe "acceptance criterion: the failure is recorded and the rollback stands" do
    test "the failure leaves a row naming the handler, the event and the run" do
      assert_raise RuntimeError, fn -> flag("c-1", 1) end

      assert [failure] = failures()
      assert failure.handler == "ProcessShapes.Intake.OnItemFlagged"
      assert failure.event_type == "item_flagged"
      assert failure.instance_id == "pairing|c-1"
      assert failure.error =~ "review desk is unreachable"
      assert failure.correlation_id
    end

    test "the event is still rolled back, so the log claims nothing happened" do
      assert_raise RuntimeError, fn -> flag("c-1", 1) end

      # The other half. Recording the failure must not have been bought by letting
      # the event commit — that would replace a missing diagnosis with a log that
      # says a fact occurred when the work did not.
      assert logged("item_flagged") == 0
      assert logged("pairing_unresolved") == 0
    end

    test "a handler that does not fail leaves no row" do
      # The control. Without it, a mechanism recording a failure for every handler
      # call would pass the test above.
      flag("c-1", 0)

      assert failures() == []
      assert logged("item_flagged") == 1
    end
  end

  describe "what the caller sees" do
    test "the handler's own exception, not the engine's wrapper" do
      # The wrapper exists to carry context to the recorder. If it reached callers,
      # a diagnostic mechanism would have become a breaking change in everyone's
      # error handling — so this is pinned rather than left to a comment.
      error = assert_raise RuntimeError, fn -> flag("c-1", 1) end

      assert error.message == "the review desk is unreachable"
    end

    test "a stacktrace that points at the handler, not at the emitter" do
      # Reraising the original with the *current* stacktrace would point at the
      # library, which is worse than not unwrapping at all.
      trace =
        try do
          flag("c-1", 1)
          nil
        rescue
          _ -> __STACKTRACE__
        end

      modules = Enum.map(trace, fn {module, _fun, _arity, _loc} -> module end)
      assert ProcessShapes.Intake.OnItemFlagged in modules
    end
  end

  describe "telemetry" do
    test "the failure is emitted on the seam error tooling attaches to" do
      # The durable row is not a replacement for this. Error collection belongs to
      # the client's tooling; the row exists because the *report* has to be able to
      # answer whether a path was ever attempted.
      handler_id = {__MODULE__, :exception, System.unique_integer()}
      test_pid = self()

      :telemetry.attach(
        handler_id,
        [:pns, :handler, :exception],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert_raise RuntimeError, fn -> flag("c-1", 1) end

      assert_received {:telemetry, measurements, metadata}
      assert metadata.handler == ProcessShapes.Intake.OnItemFlagged
      assert metadata.event_type == :item_flagged
      assert metadata.instance_id == "pairing|c-1"
      assert %RuntimeError{} = metadata.reason
      assert is_list(metadata.stacktrace)
      assert measurements.duration_us >= 0
    end
  end

  describe "the path report tells failing from dead" do
    setup do
      # A successful run, so the process has a denominator. With zero runs the report
      # correctly refuses to judge any path, and this question would not arise.
      receive_item("c-1")
      :ok
    end

    test "a failing path is reported as failing and not as untraversed" do
      assert_raise RuntimeError, fn -> flag("c-1", 1) end

      p = pairing()
      failing = Enum.map(p.failing, &{&1.from, &1.to})
      untraversed = Enum.map(p.untraversed, &{&1.from, &1.to})

      assert {:item_flagged, :pairing_unresolved} in failing

      refute {:item_flagged, :pairing_unresolved} in untraversed,
             "a bug reported as an untraversed path sends a developer's problem to " <>
               "the process owner as a question about their process"
    end

    test "the same path with no failures is untraversed, not failing" do
      p = pairing()

      assert {:item_flagged, :pairing_unresolved} in Enum.map(p.untraversed, &{&1.from, &1.to})
      assert p.failing == []
    end

    test "the count is failing runs, not failures" do
      # A handler retried forty times for one client is one failing run. The number
      # that means something when a path is not being taken is how many runs are
      # affected — the same reason the overlay counts runs rather than occurrences.
      assert_raise RuntimeError, fn -> flag("c-1", 1) end
      assert_raise RuntimeError, fn -> flag("c-1", 1) end

      assert [edge] = pairing().failing
      assert edge.failing == 1

      receive_item("c-2")
      assert_raise RuntimeError, fn -> flag("c-2", 1) end

      assert [edge] = pairing().failing
      assert edge.failing == 2
    end
  end

  describe "the limit, stated rather than hidden" do
    test "inside a caller's own transaction nothing is recorded, and the error still surfaces" do
      # A durable write from inside somebody else's doomed transaction is not
      # possible on one connection. So the engine does not pretend: the exception
      # goes into the caller's transaction and the trace is theirs to write.
      assert_raise RuntimeError, fn ->
        Repo.transaction(fn -> flag("c-1", 1) end)
      end

      assert failures() == []
    end
  end
end
