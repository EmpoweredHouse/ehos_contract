defmodule EhOsContract.ReportTest do
  @moduledoc """
  The conformance report of a v2 contract (v2 §13, plan E7c): the four questions on
  the new log, `conformance.v2` on the wire, and the sentences that say which source
  waits and which fails.

  The first block pins the numbers v1 and v2 had in common — runs, promise
  verdicts, the confirmed deadline, the confirmed declarations — which v2 gave the
  same as v1 on the same runs until v1 went (plan E11a). **Where the two did not ask
  the same question, v2 says more**: a path is a step, and the command is a node of
  its own, so the refusal branch v1 reported as one path is three steps here. The
  acceptance criterion's point survives the change: the steps nobody took are
  reported once each, whatever the number of runs.
  """

  use EhOsContract.DataCase, async: false
  use Oban.Testing, repo: EhOsContract.TestRepo

  alias EhOsContract.{Conformance, Report}
  alias ProcessShapes.{Promised, Timed}
  alias ProcessShapes.Seed

  @noon ~U[2026-09-01 12:00:00.000000Z]

  defp data(opts \\ []), do: Conformance.report(Promised, opts)
  defp text(opts \\ []), do: opts |> data() |> Report.render()
  defp process(report), do: report.processes |> Enum.find(&(&1.process == :handling))
  defp paths(report), do: report.paths

  defp names(steps),
    do: for(s <- steps, do: {s.from.name, s.via && s.via.name, s.to && s.to.name})

  describe "the numbers v1 and v2 had in common" do
    setup do: Seed.deploy()

    test "runs, the promise's verdicts and the declarations" do
      for n <- 1..3, do: Seed.request("r-#{n}", :request_approved)
      Seed.request("r-4", :request_refused)
      Seed.run_queue()

      p = process(data())

      assert p.runs == 4
      assert p.declarations == [%{key: :cadence, value: {1, :day}}]
      assert p.duration == nil

      assert [rule] = p.promises

      assert Map.take(rule, [:instances, :satisfied, :satisfied_via_or_else, :violated]) ==
               %{instances: 4, satisfied: 4, satisfied_via_or_else: 1, violated: 0}

      assert text() =~
               ~s(Rule: after "Request received" within 2 days, "Request completed" follows, or else "Refusal notified".)

      assert text() =~ "Met in all 4 runs."
      # The refusal is a correct ending, and says so: a report that called it a
      # problem would be switched off after the first period.
      assert text() =~ "conforms to the rule"
    end

    test "a confirmed deadline, measured, and its role" do
      Seed.start_run("r-1", ~U[2026-09-01 09:00:00.000000Z])
      Seed.finish_run("r-1", ~U[2026-09-01 10:30:00.000000Z])

      [p] = Conformance.report(Timed, now: @noon).processes

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

  describe "the steps of a contract" do
    setup do: Seed.deploy()

    test "50 runs, none refused: the refusal branch's three steps, each reported once" do
      for n <- 1..50, do: Seed.request("r-#{n}", :request_approved)

      report = data()
      assert process(report).runs == 50
      p = paths(report)

      assert names(p.untraversed) == [
               {:decide_request, nil, :request_refused},
               {:notify_refusal, nil, :refusal_notified},
               {:request_refused, :notify_on_refusal, :notify_refusal}
             ]

      assert Enum.all?(p.untraversed, &(&1.taken == 0))
    end

    test "one run through the refusal branch: nothing untraversed" do
      for n <- 1..49, do: Seed.request("r-#{n}", :request_approved)
      Seed.request("r-50", :request_refused)
      Seed.run_queue()

      p = paths(data())
      assert p.untraversed == [] and p.in_flight == [] and p.failing == []
    end

    # Plan DD, P1a (#183): the gate is the contract's activity, not its process's runs.
    test "no activity is no basis, not nine findings" do
      report = data()

      assert report.activity == %{events: 0, commands: 0}
      assert paths(report).untraversed == []
      assert text() =~ "this contract recorded no event in this period"
    end

    test "not yet is not never: the refusal's step waits, and is never untraversed while it does" do
      Seed.request("r-1", :request_approved)
      Seed.request("r-2", :request_refused)

      p = paths(data())

      assert names(p.in_flight) == [{:request_refused, :notify_on_refusal, :notify_refusal}]
      refute {:request_refused, :notify_on_refusal, :notify_refusal} in names(p.untraversed)
      # Nor the step after it, which waits on the one before: its command has not been
      # issued yet, which is "not yet" too.
      refute {:notify_refusal, nil, :refusal_notified} in names(p.untraversed)

      t = text()

      assert t =~
               "  Agreed steps in progress:\n    · Request refused → Notify a refusal (via: Notify a refused request) — in progress: 1 event not yet taken"

      refute t =~ "All agreed steps were carried out"

      Seed.run_queue()
      p = paths(data())
      assert p.in_flight == [] and p.untraversed == []
    end

    # Plan DD, P1a (#183): the steps are the contract's, in a block of their own before
    # the process, which keeps its runs and promises and no list of steps.
    test "the steps are the contract's block, with its activity, before the process" do
      Seed.request("r-1", :request_approved)

      report = data()
      assert %{events: events, commands: commands} = report.activity
      assert events > 0 and commands > 0
      refute Map.has_key?(process(report), :untraversed)

      t = text()
      [steps, process] = String.split(t, "PROCESS: ", parts: 2)

      assert steps =~
               "STEPS\n  Activity in this period: #{events} events, #{commands} commands.\n" <>
                 "  Agreed steps that were never carried out:"

      refute process =~ "Agreed steps"
    end

    test "untaken steps read with their business labels and the consumer they run through" do
      Seed.request("r-1", :request_approved)

      t = text()

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

      report = Conformance.report(DispatchRig.Ledger)
      p = report.paths
      assert [failing] = p.failing
      refute failing in p.untraversed

      # Plan DD, P1a (#183): a contract that recorded nothing still says what fails.
      idle = Report.render(%{report | activity: %{events: 0, commands: 1}})
      assert idle =~ "Agreed steps that are attempted and fail:"
      refute idle =~ "recorded no event"
      refute idle =~ "never carried out"

      # A contract that declares no step says so, not that all of them were taken.
      none = Report.render(%{report | paths: %{p | steps: [], failing: []}})
      assert none =~ "STEPS\n  Activity in this period: "
      assert none =~ "The contract declares no steps."
      refute none =~ "All agreed steps were carried out"

      assert Report.render(Conformance.report(DispatchRig.Ledger)) =~
               "· Deposited → Flag the account for review (via: Flag an account on a large deposit) — failing: 1 command failed"
    end

    @tag :capture_log
    test "count failures, not runs" do
      # Plan DD, P1a (#183): a step is the contract's and counts occurrences, so two
      # failures of one account are two. Until P1a they were one run in trouble; a
      # contract without a process has no runs to count them in.
      EhOsContract.Testing.drain()

      for account <- ["a-1", "a-2"] do
        {:ok, _} =
          EhOsContract.dispatch(
            DispatchRig.Ledger,
            %DispatchRig.Ledger.Commands.OpenAccount{account_id: account, branch_id: "b-7"},
            actor: @clerk
          )
      end

      fail = fn account ->
        Process.put(:dispatch_rig_flag_fails, true)

        assert_raise RuntimeError, fn ->
          EhOsContract.dispatch(
            DispatchRig.Ledger,
            %DispatchRig.Ledger.Commands.Deposit{account_id: account, amount: 1500},
            actor: @clerk
          )
        end
      end

      step = "· Deposited → Flag the account for review (via: Flag an account on a large deposit)"

      fail.("a-1")
      fail.("a-1")

      assert Report.render(Conformance.report(DispatchRig.Ledger)) =~
               step <> " — failing: 2 commands failed"

      fail.("a-2")

      assert Report.render(Conformance.report(DispatchRig.Ledger)) =~
               step <> " — failing: 3 commands failed"
    end
  end

  describe "drift" do
    setup do: Seed.deploy()

    test "an event written around dispatch under today's version is drift" do
      Seed.fact(:request_completed, "r-1", @noon)

      assert [%{from: nil, to: %{name: :request_completed}, count: 1}] = data().drift
      assert text() =~ "· Request completed — written outside dispatch  (1x)"
    end

    test "control: what dispatch appended is not" do
      Seed.request("r-1", :request_approved)

      assert data().drift == []
      assert text() =~ "None: nothing happened outside the agreement"
    end

    test "history under an older version of the contract is not drift" do
      # What an earlier version appended was judged against the declarations it had:
      # a command it declared then may be gone today, and reporting its events as
      # drift would put every change of a contract in front of the client as a breach
      # of the new one. The same event under today's version, in the same log, is.
      old_version(:request_completed, "r-1")
      assert data().drift == []

      Seed.fact(:request_completed, "r-2", @noon)
      assert [%{to: %{name: :request_completed}, count: 1}] = data().drift
    end
  end

  # One event of request handling written as an earlier version of the contract wrote
  # it, which `Seed.fact/3` cannot: it stamps today's version.
  defp old_version(name, request_id) do
    repo = Application.fetch_env!(:eh_os_contract, :repo)

    entry = %{
      type: "process_shapes.promised.#{name}",
      contract: EhOsContract.Model.fetch(ProcessShapes.Promised).id,
      contract_version: "gone",
      process: "handling",
      instance_id: "handling|#{request_id}",
      correlation_id: Ecto.UUID.generate(),
      actor: EhOsContract.Event.system_actor(),
      payload: %{"request_id" => request_id},
      occurred_at: @noon
    }

    {:ok, {:ok, [_event]}} =
      repo.transaction(fn -> EhOsContract.Store.append(repo, [entry], :none) end)

    :ok
  end

  describe "on the wire" do
    setup do: Seed.deploy()

    test "a v2 contract's report is conformance.v2, and Jason takes it" do
      Seed.request("r-1", :request_refused)

      wire = Conformance.as_data(ProcessShapes.Promised)
      assert wire["schema"] == "eh_os_contract.conformance.v2"

      assert {:ok, _json} = Jason.encode(wire)

      [p] = wire["report"]["processes"]
      [step] = wire["report"]["paths"]["in_flight"]

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
