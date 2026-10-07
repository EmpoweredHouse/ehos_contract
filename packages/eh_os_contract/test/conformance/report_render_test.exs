defmodule EhOsContract.ReportRenderTest do
  @moduledoc """
  The conformance report of a v2 contract **as a reader gets it**: what it leaves out,
  what one page holds, the period it is about, and the sentences that qualify a
  promise's count.

  `report_test.exs` pins the numbers v2 computes and the steps it names. This file
  pins what the report promises its reader, which v1's `report_test.exs` pinned on
  the v1 shape and which has to stay true when v1 goes:

  1. **it does not contain a `deadline` marked `unverified`** — a number the process
     owner never agreed to, printed next to ones they did, reads as measured;
  2. the four questions are on one page, for one period, computed by a named engine;
  3. a count is never read as saying more than it does: a breach is not excused by
     the fallback ending, a suspension is somebody else's outage, and runs judged
     under a rule that has since changed are counted apart.

  Several tests below change the report data before rendering it. Rendering is pure,
  so a branch is exercised with the shape it is contracted to accept rather than by
  bending the fixture until it produces that shape — `ProcessShapes.Promised`
  declares no external dependency, so it cannot suspend a run at all.

  Since plan DD, P2g (#228) the promise and the deadlines are process modules',
  `ProcessShapes.Handling` and `ProcessShapes.Timing`, each with a report of its own
  beside its contract's, and `mix eh_os_contract.report` prints them one after the
  other as one artifact.
  """

  use EhOsContract.DataCase, async: false

  alias EhOsContract.{Conformance, Deployment, Report}
  alias ProcessShapes.{Handling, Promised, Seed, Timing}

  setup do: Seed.deploy()

  defp data(opts \\ []), do: Conformance.report(Promised, opts)
  defp text(opts \\ []), do: opts |> data() |> Report.render()

  # The process: its runs, its promise and its deadline.
  defp handling(opts \\ []), do: Conformance.report(Handling, opts)
  defp handling_text(opts \\ []), do: opts |> handling() |> Report.render()

  # The report with its one promise replaced, rendered.
  defp render_with(report, fun) do
    [process] = report.processes
    [promise] = process.promises

    Report.render(%{report | processes: [%{process | promises: [fun.(promise)]}]})
  end

  # Every value anywhere in a nested structure, so a criterion can be stated about the
  # report rather than about one key of it.
  defp values(map) when is_map(map) and not is_struct(map),
    do: map |> Map.values() |> Enum.flat_map(&values/1)

  defp values(list) when is_list(list), do: Enum.flat_map(list, &values/1)
  defp values(other), do: [other]

  defp run_at(id, at, decision \\ :request_approved) do
    EhOsContract.Clock.at(at, fn ->
      Seed.request(id, decision)
      Seed.run_queue()
    end)
  end

  describe "acceptance criterion: no unconfirmed declarations" do
    setup do: run_at("r-1", ~U[2026-09-01 09:00:00.000000Z])

    test "a deadline marked unverified does not reach the rendered text" do
      assert EhOsContract.Model.process(Handling).deadline.unverified

      refute handling_text() =~ "Deadline"
      refute text() =~ "Deadline"

      # The control: a confirmed deadline does print, so the filter acts on
      # `unverified` rather than the renderer being unable to print a deadline.
      Seed.start_run("r-1", ~U[2026-09-01 09:00:00.000000Z])

      assert Timing |> Conformance.report() |> Report.render() =~ "Deadline:"
    end

    test "nor anywhere else in the report data, whatever key a later stage adds" do
      # A structural walk instead of a named key. v1's version of this test exists
      # because a narrower one checked `declarations` only and a later stage added
      # `duration:`, a second route by which the same unconfirmed `{3, :day}` could
      # have reached the report. v2 has more keys still.
      [process] = handling().processes

      refute {3, :day} in values(process),
             "the unconfirmed deadline reached the report through some key other than " <>
               "`declarations` — which is exactly how this criterion was escaped once"

      # A confirmed deadline is a tuple of the same kind and does reach it, so the walk
      # can see such a value at all.
      [timed] = Conformance.report(Timing).processes
      assert {1, :hour} in values(timed)
    end
  end

  describe "acceptance criterion: one artifact" do
    setup do: run_at("r-1", ~U[2026-09-01 09:00:00.000000Z])

    test "the screen's four questions are in one artifact" do
      # The contract and its process, one after the other, as the task prints them.
      t = text() <> "\n" <> handling_text()

      assert t =~ "CONTRACT"
      assert t =~ "Version"
      assert t =~ "PROCESS"
      assert t =~ "Rule: after"
      assert t =~ "DRIFT"
    end

    test "the engine version is in the data, because the data crosses boundaries too" do
      assert data().engine == EhOsContract.version()
    end

    test "and in the header, as a property of the whole artifact" do
      assert text() =~ "Computed by EhOsContract #{EhOsContract.version()}."
    end
  end

  describe "the report is for a period" do
    test "the window cuts off runs from outside the period" do
      run_at("r-1", ~U[2026-08-01 09:00:00.000000Z])
      run_at("r-2", ~U[2026-08-10 09:00:00.000000Z])
      run_at("r-3", ~U[2026-08-10 10:00:00.000000Z])

      runs = fn opts -> hd(handling(opts).processes).runs end

      assert runs.([]) == 3
      assert runs.(since: ~U[2026-08-05 00:00:00.000000Z]) == 2
      assert runs.(until: ~U[2026-08-05 00:00:00.000000Z]) == 1

      # A window in the future cannot contain anything — proof that the bound works
      # rather than being ignored.
      assert runs.(since: ~U[2027-01-01 00:00:00.000000Z]) == 0
    end

    test "the header names the period the report is about" do
      t = text(since: ~U[2026-07-01 00:00:00.000000Z], until: ~U[2026-07-31 23:59:59.000000Z])
      assert t =~ "2026-07-01 – 2026-07-31"
    end
  end

  describe "the fallback ending is named beside the count it qualifies" do
    setup do: run_at("r-1", ~U[2026-09-01 09:00:00.000000Z])

    test "a breached promise does not read as though the fallback excused a breach" do
      # The clause used to be appended to whatever the sentence said, producing
      # "BREACHED in 1 of 5 runs. (including 1 via the fallback ending, which conforms
      # to the rule)" — where "including" reads as qualifying the breaches and in fact
      # qualifies the runs that were met.
      text =
        render_with(handling(), fn promise ->
          %{
            promise
            | instances: 5,
              satisfied: 4,
              satisfied_via_eventually: 3,
              satisfied_via_or_else: 1,
              violated: 1,
              pending: 0
          }
        end)

      assert text =~ "BREACHED in 1 of 5 runs."
      assert text =~ "Of those that were met, 1 run reached the fallback ending"
      refute text =~ "including"
    end

    test "and says nothing about a fallback when nothing was met at all" do
      # There would be no count for the clause to qualify.
      text =
        render_with(handling(), fn promise ->
          %{
            promise
            | instances: 2,
              satisfied: 0,
              satisfied_via_or_else: 0,
              violated: 2,
              pending: 0
          }
        end)

      refute text =~ "fallback ending"
    end
  end

  describe "a rule that was changed does not retroactively judge older runs" do
    defp rule_changed_on(at) do
      for {digest, seen} <- [
            {"aaaaaaaaaaaa", ~U[2026-08-01 00:00:00.000000Z]},
            {"bbbbbbbbbbbb", at}
          ] do
        Repo.insert!(%Deployment{
          contract: "process:process_shapes.handling",
          contract_version: Handling.__eh_os_contract_model__().version,
          wiring_version: "wiring-#{digest}",
          events: [],
          edges: [],
          declaration_digests: %{"promise:completed_or_refusal_notified" => digest},
          first_seen_at: seen
        })
      end
    end

    defp promise do
      [process] = handling().processes
      [promise] = process.promises
      promise
    end

    test "with no change, the numbers and the text are what they were" do
      # The 99% path. A promise that never moved must render as before, or this
      # mechanism has a cost on every report rather than on the reports it is for.
      run_at("r-1", ~U[2026-08-02 09:00:00.000000Z])

      p = promise()

      assert p.under_earlier_declaration == 0
      assert p.declaration_changed_at == nil
      assert p.instances == 1
      refute handling_text() =~ "judged under a different promise"
    end

    test "the report says how many fell outside and on what date" do
      run_at("r-old", ~U[2026-08-02 09:00:00.000000Z])
      run_at("r-new", ~U[2026-08-09 09:00:00.000000Z])
      rule_changed_on(~U[2026-08-05 09:00:00.000000Z])

      t = handling_text()

      assert t =~ "1 run began before this rule was last changed (2026-08-05)"
      assert t =~ "judged under a different promise"
    end

    test "every run predating the change is not the same as nothing to judge" do
      run_at("r-old", ~U[2026-08-02 09:00:00.000000Z])
      rule_changed_on(~U[2026-08-05 09:00:00.000000Z])

      p = promise()
      assert p.instances == 0
      assert p.under_earlier_declaration == 1

      t = handling_text()
      assert t =~ "No run in this period was judged under the rule as it now stands."
      refute t =~ "There was no run in this period on which this could be judged."
    end
  end

  describe "a suspended run reads as somebody else's outage" do
    setup do: run_at("r-1", ~U[2026-09-01 09:00:00.000000Z])

    test "it is named as a suspension and kept out of the breaches" do
      text =
        render_with(handling(), fn promise ->
          %{promise | instances: 3, satisfied: 1, violated: 0, suspended: 2}
        end)

      assert text =~ "Suspended: 2 runs"
      assert text =~ "external dependency was unavailable"

      # The sentence has to say whose problem it is not. Without that clause a reader
      # sees a number next to a promise and reads it as a fault.
      assert text =~ "not a breach on the client's side"
      refute text =~ "BREACHED"
    end

    test "no suspensions means no sentence at all" do
      # The control. A report that mentions suspensions when there are none teaches a
      # reader to skip the line.
      refute handling_text() =~ "Suspended"
    end
  end

  describe "the agreed duration, measured" do
    # `ProcessShapes.Timing` confirms `deadline {1, :hour}`. These sentences are
    # the only place the report turns that declaration into a finding, and each
    # counts only what can be known: a finished run's duration, or an open run's
    # lower bound, never the two in one count.
    @nine ~U[2026-09-01 09:00:00.000000Z]
    @noon ~U[2026-09-01 12:00:00.000000Z]

    defp timed_text do
      Timing |> Conformance.report(now: @noon) |> Report.render()
    end

    test "the sentence counts only the runs that finished" do
      Seed.start_run("r-1", @nine)
      Seed.finish_run("r-1", ~U[2026-09-01 09:30:00.000000Z])
      Seed.start_run("r-2", @nine)
      Seed.finish_run("r-2", ~U[2026-09-01 10:30:00.000000Z])

      assert timed_text() =~ "The agreed duration was exceeded in 1 of 2 runs that finished."
    end

    test "a run still open past its hour gets its own line, not a place in the count" do
      Seed.start_run("r-1", @nine)
      Seed.finish_run("r-1", ~U[2026-09-01 09:30:00.000000Z])
      Seed.start_run("r-2", @nine)

      t = timed_text()

      assert t =~ "The agreed duration was kept in all 1 run that finished."
      assert t =~ "1 run still open and already past it."
    end

    test "a run still inside its time is no finding, and nothing finished cannot be judged" do
      Seed.start_run("r-1", ~U[2026-09-01 11:50:00.000000Z])

      t = timed_text()

      refute t =~ "still open and already past it"
      assert t =~ "No run finished in this period, so the agreed duration cannot be judged."
    end
  end
end
