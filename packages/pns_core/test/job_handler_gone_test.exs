defmodule PNS.JobHandlerGoneTest do
  @moduledoc """
  Stage 2.4: **a job whose handler no longer exists is cancelled and recorded.**

  It used to raise `String.to_existing_atom`, fail, and be retried twice more, three
  seconds apart, ending as `discarded` with an error that said nothing about why. A
  deterministic failure retried is noise, and noise in a queue is where real failures
  go to hide.

  Recording it is not bookkeeping. A queued job for a handler that is gone is a **path
  declared by a wiring that is no longer deployed** — the exact fact stage 1.6 built the
  wiring version to tell apart from drift. Dropped silently, the log would imply the
  work was never scheduled.
  """

  use PNS.DataCase, async: false
  use Oban.Testing, repo: PNS.TestRepo

  alias ProcessShapes.Rig

  defp handlings(event_id) do
    Repo.all(from(h in PNS.EventHandling, where: h.event_id == ^event_id))
  end

  defp queue_job(event, handler) do
    %{
      "handler" => handler,
      "event_id" => event.id,
      "event_type" => event.type,
      "payload" => event.payload,
      "correlation_id" => event.correlation_id,
      "causation_id" => event.causation_id,
      "chain" => [event.type],
      "actor" => nil
    }
    |> PNS.Job.new()
    |> Oban.insert!()
  end

  # A real event to hang the job off, so the recorded row references something that
  # exists — the point being that the *event* is a fact and only its handler is gone.
  defp an_event(item_no \\ 1) do
    PNS.emit!(Rig, :item_measured, %{case_id: "c-1", item_no: item_no})
  end

  describe "a handler that was renamed away" do
    test "the job is cancelled rather than retried" do
      event = an_event()
      job = queue_job(event, "ProcessShapes.Intake.OnSomethingRenamedAway")

      assert {:cancel, reason} = perform_job(PNS.Job, job.args)
      assert reason =~ "no longer exists"

      # The sentence that matters for whoever reads it: this is not a transient
      # failure, so the queue must not keep trying.
      assert reason =~ "Cancelled rather than retried"
    end

    test "the attempt is recorded against the event, with the deployment reason" do
      event = an_event()
      job = queue_job(event, "ProcessShapes.Intake.OnSomethingRenamedAway")

      perform_job(PNS.Job, job.args)

      [cancelled] =
        handlings(event.id) |> Enum.filter(&(&1.status == "cancelled"))

      assert cancelled.handler == "ProcessShapes.Intake.OnSomethingRenamedAway"

      # Connected to stage 1.6 on purpose. Without this the log says the work was
      # never scheduled, which is a different and false statement.
      assert cancelled.error =~ "wiring that is no longer deployed"
    end
  end

  describe "a module that exists but stopped being a handler" do
    test "is treated the same, because the work has no owner either way" do
      # `ProcessShapes.Matching` is a real, loadable module that has no
      # `__pns_handler__/0` — the shape somebody produces by deleting `use PNS.Handler`
      # and keeping the file. Resolving by name alone would have called a function that
      # does not exist and crashed one line later.
      event = an_event()
      job = queue_job(event, "ProcessShapes.Matching")

      assert {:cancel, reason} = perform_job(PNS.Job, job.args)
      assert reason =~ "no longer exists"

      assert [_] = handlings(event.id) |> Enum.filter(&(&1.status == "cancelled"))
    end
  end

  describe "the control" do
    test "a handler that does exist still runs and is recorded as ok" do
      # Without this the tests above would pass against a job that cancels everything.
      #
      # `item_no: 0` because `OnItemEscalated` is the stage 2.1 fixture that emits
      # something it never declared, and it does so only for a positive item number.
      # Driving it with 1 would make this control fail for a reason that has nothing to
      # do with resolving a handler — which is what it did on the first run.
      event = an_event(0)
      job = queue_job(event, "ProcessShapes.Resolution.OnItemEscalated")

      assert :ok = perform_job(PNS.Job, job.args)

      assert [handling] =
               handlings(event.id) |> Enum.filter(&(&1.handler =~ "OnItemEscalated"))

      assert handling.status == "ok"
    end
  end
end
