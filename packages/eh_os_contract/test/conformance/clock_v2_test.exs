defmodule EhOsContract.ClockV2Test do
  @moduledoc """
  `EhOsContract.Clock.at/2` on a v2 contract: **the time an event is stamped with is
  chosen before it is written, whichever way the event got into the log.**

  The log is append-only, so every test that needs a run in the past dispatches in the
  past through `at/2` — `ProcessShapes.Seed` does, and so do the deployment and
  deadline tests on it. They rely on the time reaching more than the command's own
  event: the event of a policy inside the transaction, and the event of a command a
  subscription issues when the queue is drained. A policy stamped with the wall clock
  would leave a run spread across two dates, one of them today, and every duration and
  promise measured on it would be wrong by however long ago the test meant.

  `clock_test.exs` pins the same on v1 and the parts of `at/2` that are not about any
  contract: a zone other than UTC, nesting, and what happens outside it.
  """

  use EhOsContract.DataCase, async: false

  alias EhOsContract.{Clock, Model}
  alias ProcessShapes.Seed

  @nine ~U[2026-09-01 09:00:00.000000Z]

  @owner EhOsContract.Actor.credential("u-1", ["process_shapes.start_run"])

  # The type an event is stored under, as the model says, rather than spelled here.
  defp events(contract, name) do
    %{type: type} = Enum.find(Model.fetch(contract).events, &(&1.name == name))
    events_of(type)
  end

  defp start_run(id) do
    {:ok, _} =
      EhOsContract.dispatch(
        ProcessShapes.Next.Timed,
        %ProcessShapes.Next.Timed.Commands.StartRun{run_id: id},
        actor: @owner
      )
  end

  test "an event dispatched inside at/2 carries that time, and so does its inline policy's" do
    Clock.at(@nine, fn -> start_run("r-1") end)

    assert [%{occurred_at: @nine}] = events(ProcessShapes.Next.Timed, :run_started)
    assert [%{occurred_at: @nine}] = events(ProcessShapes.Next.Timed, :run_acknowledged)
  end

  test "a subscription drained inside at/2 stamps its events with that time too" do
    Seed.deploy(:v2)

    Clock.at(@nine, fn ->
      Seed.request(:v2, "r-1", :request_refused)
      Seed.run_queue(:v2)
    end)

    notified = events(ProcessShapes.Next.Promised, :refusal_notified)
    assert notified != [], "the fixture's subscription issued nothing"
    assert Enum.all?(notified, &(&1.occurred_at == @nine))
  end

  test "a time written to the second is stored to the microsecond, as the log keeps it" do
    Clock.at(~U[2026-07-01 09:00:00Z], fn -> start_run("r-1") end)

    assert [%{occurred_at: ~U[2026-07-01 09:00:00.000000Z]}] =
             events(ProcessShapes.Next.Timed, :run_started)
  end
end
