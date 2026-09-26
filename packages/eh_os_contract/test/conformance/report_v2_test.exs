defmodule EhOsContract.ReportV2Test do
  @moduledoc """
  The conformance report of a v2 contract (v2 §13, plan E7c): the four questions on
  the new log, `conformance.v2` on the wire, and the sentences that say which source
  waits and which fails.

  **Where v1 and v2 ask the same question, they give the same number** — runs,
  promise verdicts, the confirmed deadline, the confirmed declarations — and the
  first block runs those on both shapes. **Where they do not, v2 says more**: a path
  is a step, and the command is a node of its own, so the refusal branch v1 reported
  as one path is three steps here. The acceptance criterion's point survives the
  change: the steps nobody took are reported once each, whatever the number of runs.
  """

  use EhOsContract.DataCase, async: false
  use Oban.Testing, repo: EhOsContract.TestRepo

  alias EhOsContract.{Conformance, Report}
  alias ProcessShapes.Seed

  @noon ~U[2026-09-01 12:00:00.000000Z]

  defp data(shape, opts \\ []), do: Conformance.report(Seed.promised(shape), opts)
  defp text(shape, opts \\ []), do: shape |> data(opts) |> Report.render()
  defp process(report), do: report.processes |> Enum.find(&(&1.process == :handling))
  defp rules(p), do: Map.get(p, :assertions) || Map.get(p, :promises)

  defp names(steps),
    do: for(s <- steps, do: {s.from.name, s.via && s.via.name, s.to && s.to.name})

  describe "the same numbers on both shapes" do
    for shape <- [:v1, :v2] do
      @tag shape: shape
      test "#{shape}: runs, the promise's verdicts and the declarations", %{shape: shape} do
        Seed.deploy(shape)
        for n <- 1..3, do: Seed.request(shape, "r-#{n}", :request_approved)
        Seed.request(shape, "r-4", :request_refused)
        Seed.run_queue(shape)

        p = process(data(shape))

        assert p.runs == 4
        assert p.declarations == [%{key: :cadence, value: {1, :day}}]
        assert p.duration == nil

        assert [rule] = rules(p)

        assert Map.take(rule, [:instances, :satisfied, :satisfied_via_or_else, :violated]) ==
                 %{instances: 4, satisfied: 4, satisfied_via_or_else: 1, violated: 0}

        assert text(shape) =~
                 ~s(Rule: after "Request received" within 2 days, "Request completed" follows, or else "Refusal notified".)

        assert text(shape) =~ "Met in all 4 runs."
      end

      @tag shape: shape
      test "#{shape}: a confirmed deadline, measured, and its role", %{shape: shape} do
        Seed.deploy(shape)
        Seed.start_run(shape, "r-1", ~U[2026-09-01 09:00:00.000000Z])
        Seed.finish_run(shape, "r-1", ~U[2026-09-01 10:30:00.000000Z])

        [p] = Conformance.report(Seed.timed(shape), now: @noon).processes

        assert p.duration == %{
                 runs: 1,
                 within: 0,
                 exceeded: 1,
                 overdue: 0,
                 open: 0,
                 deadline: {1, :hour}
               }

        assert p.accountable == "Run owner"
      end
    end
  end

  describe "the steps of a v2 process" do
    setup do: Seed.deploy(:v2)

    test "50 runs, none refused: the refusal branch's three steps, each reported once" do
      for n <- 1..50, do: Seed.request(:v2, "r-#{n}", :request_approved)

      p = process(data(:v2))

      assert p.runs == 50

      assert names(p.untraversed) == [
               {:decide_request, nil, :request_refused},
               {:notify_refusal, nil, :refusal_notified},
               {:request_refused, :notify_on_refusal, :notify_refusal}
             ]

      assert Enum.all?(p.untraversed, &(&1.runs == 0 and &1.of_runs == 50))
    end

    test "one run through the refusal branch: nothing untraversed" do
      for n <- 1..49, do: Seed.request(:v2, "r-#{n}", :request_approved)
      Seed.request(:v2, "r-50", :request_refused)
      Seed.run_queue(:v2)

      p = process(data(:v2))
      assert p.untraversed == [] and p.in_flight == [] and p.failing == []
    end

    test "zero runs is no basis, not nine findings" do
      p = process(data(:v2))

      assert p.runs == 0
      assert p.untraversed == []
      assert text(:v2) =~ "not a single run in this period"
    end

    test "not yet is not never: the refusal's step waits, and is never untraversed while it does" do
      Seed.request(:v2, "r-1", :request_approved)
      Seed.request(:v2, "r-2", :request_refused)

      p = process(data(:v2))

      assert names(p.in_flight) == [{:request_refused, :notify_on_refusal, :notify_refusal}]
      refute {:request_refused, :notify_on_refusal, :notify_refusal} in names(p.untraversed)
      # Nor the step after it, which waits on the one before: its command has not been
      # issued yet, which is "not yet" too.
      refute {:notify_refusal, nil, :refusal_notified} in names(p.untraversed)

      t = text(:v2)

      assert t =~
               "  Agreed steps in progress:\n    · Request refused → Notify a refusal (via: Notify a refused request) — in progress: 1 event not yet taken"

      refute t =~ "All agreed steps were carried out"

      Seed.run_queue(:v2)
      p = process(data(:v2))
      assert p.in_flight == [] and p.untraversed == []
    end

    test "untaken steps read with their business labels and the consumer they run through" do
      Seed.request(:v2, "r-1", :request_approved)

      t = text(:v2)

      assert t =~ "Agreed steps that were never carried out:"
      assert t =~ "· Decide a request → Request refused"
      assert t =~ "· Request refused → Notify a refusal (via: Notify a refused request)"
      refute t =~ "request_refused"
    end
  end

  describe "failing steps" do
    @clerk EhOsContract.Actor.credential("u-1", [
             "dispatch_rig.open_account",
             "dispatch_rig.deposit"
           ])

    @tag :capture_log
    test "say what fails, apart from a step nobody took" do
      EhOsContract.Testing.drain()

      {:ok, _} =
        EhOsContract.dispatch(
          DispatchRig.Ledger,
          %DispatchRig.Ledger.Commands.OpenAccount{account_id: "a-1", branch_id: "b-7"},
          actor: @clerk
        )

      Process.put(:dispatch_rig_flag_fails, true)

      assert_raise RuntimeError, fn ->
        EhOsContract.dispatch(
          DispatchRig.Ledger,
          %DispatchRig.Ledger.Commands.Deposit{account_id: "a-1", amount: 1500},
          actor: @clerk
        )
      end

      [p] = Conformance.report(DispatchRig.Ledger).processes
      assert [failing] = p.failing
      refute failing in p.untraversed

      assert Report.render(Conformance.report(DispatchRig.Ledger)) =~
               "· Deposited → Flag the account for review (via: Flag an account on a large deposit) — failing: a command failed in 1 run"
    end
  end

  describe "drift" do
    setup do: Seed.deploy(:v2)

    test "an event written around dispatch under today's version is drift" do
      Seed.fact(:v2, :request_completed, "r-1", @noon)

      assert [%{from: nil, to: %{name: :request_completed}, count: 1}] = data(:v2).drift
      assert text(:v2) =~ "· Request completed — written outside dispatch  (1x)"
    end

    test "control: what dispatch appended is not" do
      Seed.request(:v2, "r-1", :request_approved)

      assert data(:v2).drift == []
      assert text(:v2) =~ "None: nothing happened outside the agreement"
    end
  end

  describe "on the wire" do
    setup do: Seed.deploy(:v2)

    test "a v2 contract's report is conformance.v2, and Jason takes it; a v1 one stays v1" do
      Seed.request(:v2, "r-1", :request_refused)

      wire = Conformance.as_data(ProcessShapes.Next.Promised)
      assert wire["schema"] == "eh_os_contract.conformance.v2"

      assert Conformance.as_data(ProcessShapes.Promised)["schema"] ==
               "eh_os_contract.conformance.v1"

      assert {:ok, _json} = Jason.encode(wire)

      [p] = wire["report"]["processes"]
      [step] = p["in_flight"]

      assert step["from"] == %{
               "kind" => "event",
               "name" => "request_refused",
               "label" => "Request refused"
             }

      assert step["via"]["kind"] == "policy"
      assert step["to"]["name"] == "notify_refusal"
      assert step["mode"] == "async"
      assert step["in_flight"] == %{"effects" => 0, "timers" => 0, "lag" => 1}
      assert step["failing"] == %{"commands" => 0, "subscription" => nil, "effects" => 0}
      assert [%{"promise" => "completed_or_refusal_notified"}] = p["promises"]
    end
  end
end
