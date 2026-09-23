defmodule EhOsContract.RunTest do
  @moduledoc """
  Stage 5.4: **the process `deadline`, read at last.**

  It has been declarable since the first commit and nothing ever computed it — the
  only two readers were a filter that dropped it when unconfirmed and a renderer
  that printed the declaration back. Stage 2 existed to delete declarations nobody
  reads; this was the one it missed.

  The sharp test in this file is not any of the four outcomes. It is the one about
  a run that started before the reported period: the period selects runs by when
  they *started*, and measures them over their whole history, and getting that
  backwards makes a run that blew its deadline report as having kept it.
  """

  use EhOsContract.DataCase, async: false

  alias ProcessShapes.Timed, as: Contract

  @nine ~U[2026-09-01 09:00:00.000000Z]
  @noon ~U[2026-09-01 12:00:00.000000Z]

  defp set_time(id, types, at) do
    Repo.update_all(
      from(e in EhOsContract.Event,
        where: e.instance_id == ^"timed_run|#{id}" and e.type in ^types
      ),
      set: [occurred_at: at]
    )
  end

  defp start_run(id, at) do
    EhOsContract.emit!(Contract, :run_started, %{run_id: id})
    set_time(id, ["run_started", "run_acknowledged"], at)
  end

  defp finish_run(id, at) do
    EhOsContract.emit!(Contract, :run_finished, %{run_id: id})
    set_time(id, ["run_finished"], at)
  end

  defp outcomes(opts \\ []) do
    Contract
    |> EhOsContract.Run.evaluate(:timed_run, Keyword.put_new(opts, :now, @noon))
    |> Map.new(&{&1.instance_id, &1.outcome})
  end

  describe "the four outcomes" do
    test "a run that ended inside the declared hour kept it" do
      start_run("r-1", @nine)
      finish_run("r-1", ~U[2026-09-01 09:30:00.000000Z])

      assert outcomes() == %{"timed_run|r-1" => :within}
    end

    test "a run that ended outside it exceeded it" do
      start_run("r-1", @nine)
      finish_run("r-1", ~U[2026-09-01 10:30:00.000000Z])

      assert outcomes() == %{"timed_run|r-1" => :exceeded}
    end

    test "a run still open past its hour is overdue, which is a finding" do
      # Not `:exceeded`: the duration is not known, only a lower bound on it. And
      # not silence either — the run has already taken longer than agreed whatever
      # it does next.
      start_run("r-1", @nine)

      assert outcomes() == %{"timed_run|r-1" => :overdue}
    end

    test "a run still open and still inside its hour is not a finding at all" do
      # The case the standing rule is about: a run inside its time is the normal
      # state, and reporting it as anything would turn an absence of an answer into
      # an answer.
      start_run("r-1", ~U[2026-09-01 11:50:00.000000Z])

      assert outcomes() == %{"timed_run|r-1" => :open}
    end

    test "the four outcomes account for every run" do
      start_run("r-within", @nine)
      finish_run("r-within", ~U[2026-09-01 09:30:00.000000Z])
      start_run("r-exceeded", @nine)
      finish_run("r-exceeded", ~U[2026-09-01 10:30:00.000000Z])
      start_run("r-overdue", @nine)
      start_run("r-open", ~U[2026-09-01 11:50:00.000000Z])

      s =
        Contract
        |> EhOsContract.Run.evaluate(:timed_run, now: @noon)
        |> EhOsContract.Run.summary()

      assert s == %{runs: 4, within: 1, exceeded: 1, overdue: 1, open: 1}
      assert s.within + s.exceeded + s.overdue + s.open == s.runs
    end
  end

  describe "the period selects runs by when they started, and measures the whole run" do
    setup do
      # Started before the window, ended inside it, and it blew the hour.
      start_run("r-1", ~U[2026-08-31 23:00:00.000000Z])
      finish_run("r-1", ~U[2026-09-01 09:30:00.000000Z])
      :ok
    end

    test "a run that started before the period is not in it" do
      # **The test that earns this file**, and the only one that separates `having`
      # from `where`. `since` falls between this run's start and its end, so a
      # `where` on `occurred_at` drops the early rows, the run looks as though it
      # started at 09:30, it ends at 09:30 — and a ten-and-a-half-hour run reports
      # as having kept a one-hour promise. With `having` on the run's minimum it is
      # simply not a run of this period, which is the honest answer.
      assert outcomes(since: @nine) == %{}
    end

    test "and when it is in the period, it is measured over its whole history" do
      # Weaker than its neighbour on purpose, and worth saying so: with `since`
      # before the start, `where` and `having` agree, so this does not distinguish
      # them. What it does pin is that the duration comes from start to terminal
      # event — ten and a half hours against a one-hour promise — rather than from
      # anything narrower.
      assert outcomes(since: ~U[2026-08-31 00:00:00.000000Z]) ==
               %{"timed_run|r-1" => :exceeded}
    end
  end

  describe "in the report" do
    defp duration(contract \\ Contract) do
      [process] = EhOsContract.Conformance.report(contract, now: @noon).processes
      process.duration
    end

    defp text(contract \\ Contract) do
      contract |> EhOsContract.Conformance.report(now: @noon) |> EhOsContract.Report.render()
    end

    test "the numbers reach the report data" do
      start_run("r-1", @nine)
      finish_run("r-1", ~U[2026-09-01 09:30:00.000000Z])
      start_run("r-2", @nine)
      finish_run("r-2", ~U[2026-09-01 10:30:00.000000Z])
      start_run("r-3", @nine)

      assert duration() ==
               %{runs: 3, within: 1, exceeded: 1, overdue: 1, open: 0, deadline: {1, :hour}}
    end

    test "the sentence names the agreed duration and counts only finished runs" do
      start_run("r-1", @nine)
      finish_run("r-1", ~U[2026-09-01 09:30:00.000000Z])
      start_run("r-2", @nine)
      finish_run("r-2", ~U[2026-09-01 10:30:00.000000Z])

      assert text() =~ "The agreed duration was exceeded in 1 of 2 runs that finished."
    end

    test "a run still open past its hour gets its own line, not a place in the count" do
      start_run("r-1", @nine)
      finish_run("r-1", ~U[2026-09-01 09:30:00.000000Z])
      start_run("r-2", @nine)

      t = text()

      assert t =~ "The agreed duration was kept in all 1 run that finished."
      assert t =~ "1 run still open and already past it."
    end

    test "a run inside its time produces no sentence at all" do
      start_run("r-1", ~U[2026-09-01 11:50:00.000000Z])

      t = text()

      refute t =~ "still open and already past it"
      assert t =~ "No run finished in this period, so the agreed duration cannot be judged."
    end

    test "an unconfirmed deadline is still absent from the report" do
      # The control that matters most, and it is free: `ProcessShapes.Promised`
      # declares `deadline: {3, :day}` with `unverified: [:deadline]`. If this
      # aggregate reached the report, stage 1.7's acceptance criterion would have
      # been quietly broken by stage 5.4.
      assert ProcessShapes.Promised.process(:handling).deadline == {3, :day}
      assert duration(ProcessShapes.Promised) == nil
      refute text(ProcessShapes.Promised) =~ "agreed duration"
    end
  end

  describe "what the aggregate declines to answer" do
    test "a process that declares no deadline has no outcomes, not zero runs" do
      # `ProcessShapes.Promised` has runs and declares a deadline it has not
      # confirmed; `Rig` declares none at all. Neither can be measured, and the
      # difference between "measured as zero" and "not measured" is the whole
      # subject of this stage.
      assert EhOsContract.Run.evaluate(ProcessShapes.Rig, :pairing, now: @noon) == []
    end

    test "an unknown process name is empty rather than an exception" do
      assert EhOsContract.Run.evaluate(Contract, :no_such_process, now: @noon) == []
    end
  end
end
