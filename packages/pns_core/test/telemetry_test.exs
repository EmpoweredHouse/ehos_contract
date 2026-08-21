defmodule PNS.TelemetryTest do
  @moduledoc """
  Stage 2.5: **the engine emits, and nothing here collects.**

  Two families, and the reason there are only two is the interesting part: each one is
  something no other tool in the stack can see. Nothing else observes a synchronous
  handler, and nothing else knows what the client agreed to. Query timings are Ecto's,
  job lifecycle is Oban's, and anything a report answers stays in the log where it is
  exact.
  """

  use PNS.DataCase, async: false
  use Oban.Testing, repo: PNS.TestRepo

  alias ProcessShapes.Rig

  defp listen(events) do
    id = {__MODULE__, System.unique_integer()}
    test = self()

    :telemetry.attach_many(
      id,
      events,
      fn event, measurements, metadata, _ -> send(test, {event, measurements, metadata}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)
  end

  describe "the catalogue is an interface" do
    test "it is pinned as a literal, because renaming an event is a breaking change" do
      # A telemetry name is as public as a function name: whoever attached to it stops
      # receiving anything, silently, and finds out when a dashboard goes flat. Pinned
      # so a rename has to be deliberate.
      assert PNS.Telemetry.events() == [
               [:pns, :handler, :start],
               [:pns, :handler, :stop],
               [:pns, :handler, :exception],
               [:pns, :contract, :violation]
             ]
    end

    test "the three handler events are the span convention, not names of our own" do
      # `:telemetry.span/3` produces exactly `start`, `stop`, `exception` under one
      # prefix. Asserting the shape rather than trusting it, because the first seam
      # invented `duration_us` and that is precisely the kind of near-miss that costs an
      # integrator a special case.
      [start, stop, exception, _] = PNS.Telemetry.events()

      assert start == [:pns, :handler, :start]
      assert stop == [:pns, :handler, :stop]
      assert exception == [:pns, :handler, :exception]
    end
  end

  describe "a handler is observable wherever it runs" do
    test "synchronously: start then stop, with a duration in native units" do
      listen([[:pns, :handler, :start], [:pns, :handler, :stop]])

      PNS.emit!(Rig, :item_measured, %{case_id: "c-1", item_no: 1})

      assert_received {[:pns, :handler, :start], started, meta}
      assert is_integer(started.system_time)
      assert meta.async == false
      assert meta.event_type == :item_measured
      assert meta.instance_id == "pairing|c-1"

      assert_received {[:pns, :handler, :stop], stopped, _meta}
      assert stopped.duration >= 0
    end

    test "through the queue: the same three events, marked async" do
      # Oban emits its own span around the job. This one is around the handler, which
      # Oban knows nothing about — two spans, two subjects.
      listen([[:pns, :handler, :start], [:pns, :handler, :stop]])

      PNS.emit!(Rig, :item_appealed, %{case_id: "c-1", item_no: 1})
      Oban.drain_queue(queue: :events)

      # The synchronous handler on `item_appealed` reports first; the queued one follows.
      assert_received {[:pns, :handler, :start], _, %{async: false}}
      assert_received {[:pns, :handler, :start], _, %{async: true} = queued}

      assert queued.handler == ProcessShapes.Intake.OnItemReopened
      assert queued.attempt == 1
    end

    test "a raise reports exception rather than stop" do
      listen([[:pns, :handler, :stop], [:pns, :handler, :exception]])

      assert_raise RuntimeError, fn ->
        PNS.emit!(Rig, :item_flagged, %{case_id: "c-1", item_no: 1})
      end

      assert_received {[:pns, :handler, :exception], measurements, metadata}
      assert %RuntimeError{} = metadata.reason
      assert measurements.duration >= 0

      # A failed handler must not also look like a successful one.
      refute_received {[:pns, :handler, :stop], _, _}
    end
  end

  describe "a contract violation, which nothing else in the stack can report" do
    setup do
      listen([[:pns, :contract, :violation]])
    end

    test "a payload that contradicts its declaration" do
      assert_raise ArgumentError, fn ->
        PNS.emit!(ProcessShapes.Bare, :batch_closed, %{batch_id: "b-1"})
      end

      assert_received {[:pns, :contract, :violation], _, metadata}
      assert metadata.kind == :payload
      assert metadata.event_type == :batch_closed
    end

    test "a cycle, and the path is in the metadata because that is what makes it actionable" do
      assert_raise ArgumentError, fn ->
        PNS.emit!(Rig, :item_disputed, %{case_id: "c-1", item_no: 1})
      end

      assert_received {[:pns, :contract, :violation], _, metadata}
      assert metadata.kind == :cycle
      assert metadata.chain == ["item_disputed", "item_rechecked", "item_disputed"]
    end

    test "a handler emitting what it never declared" do
      assert_raise ArgumentError, fn ->
        PNS.emit!(Rig, :item_reviewed, %{case_id: "c-1", item_no: 1})
      end

      assert_received {[:pns, :contract, :violation], _, metadata}
      assert metadata.kind == :undeclared_publication
      assert metadata.handler == ProcessShapes.Resolution.OnItemReviewed
      assert metadata.undeclared == [:item_paired]
    end

    test "nothing is reported when the contract is honoured" do
      # The control. Without it every test above would pass against a mechanism that
      # reported a violation on every emission.
      PNS.emit!(Rig, :item_measured, %{case_id: "c-1", item_no: 1})

      refute_received {[:pns, :contract, :violation], _, _}
    end
  end

  describe "the retention rule reaches telemetry too" do
    test "no payload value appears in any metadata" do
      # Telemetry is a third way out of the system, after the log and the job arguments.
      # `retain` covers those two; a metric carrying a payload value would reopen the
      # hole that closing them shut. `note` is on `retain: :drop`, so its value must not
      # turn up anywhere.
      listen([[:pns, :handler, :start], [:pns, :handler, :stop]])

      PNS.emit!(Rig, :item_noted, %{case_id: "c-1", item_no: 1, note: "secret"})

      # A span **did** happen — the first version of this test asserted the absence
      # without checking that, so it passed by receiving nothing at all. `item_noted`
      # had no handler, which made the whole assertion vacuous.
      assert_received {[:pns, :handler, :start], _, metadata}
      assert metadata.event_type == :item_noted

      refute Map.has_key?(metadata, :note)
      refute Map.has_key?(metadata, :payload)
      refute metadata |> Map.values() |> Enum.member?("secret")
    end
  end
end
