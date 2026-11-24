defmodule EhosContract.PathsTest do
  @moduledoc """
  The steps a v2 contract declares, and what the log says about each (v2 §13, plan
  E7c): taken how many times, waiting on which of three sources, failing on which
  of three. A step counts its occurrences, not the runs they fall in, and a contract
  without a process has its steps counted too (plan DD, P1a, #183).
  """

  use EhosContract.DataCase, async: false

  # A failing dispatch logs its row's failure.
  @moduletag :capture_log

  alias DispatchRig.Ledger
  alias DispatchRig.Ledger.Commands.{Deposit, OpenAccount, Withdraw}
  alias EhosContract.{Actor, Paths, SubscriptionRecord, Testing}
  alias ProcessShapes.Seed

  defp names(step) do
    {step.from.name, step.via && step.via.name, step.to && step.to.name}
  end

  defp step(steps, from, via, to), do: Enum.find(steps, &(names(&1) == {from, via, to}))

  describe "request handling, ported" do
    setup do: Seed.deploy()

    test "declares each command's emits and each policy's issues, in declaration order" do
      assert Enum.map(Paths.declared(ProcessShapes.Promised), &names/1) == [
               {:submit_request, nil, :request_received},
               {:decide_request, nil, :request_approved},
               {:decide_request, nil, :request_refused},
               {:log_request, nil, :request_logged},
               {:complete_request, nil, :request_completed},
               {:notify_refusal, nil, :refusal_notified},
               {:request_received, :log_arrival, :log_request},
               {:request_approved, :complete_approved, :complete_request},
               {:request_refused, :notify_on_refusal, :notify_refusal}
             ]

      [emits | _] = declared = Paths.declared(ProcessShapes.Promised)

      # What it promises, and nothing `observe/2` uses to find a step's rows.
      assert Enum.all?(declared, &(Enum.sort(Map.keys(&1)) == [:from, :mode, :to, :via]))

      assert emits.from == %{kind: :command, name: :submit_request, label: "Submit a request"}
      assert emits.to == %{kind: :event, name: :request_received, label: "Request received"}
    end

    test "an approved request takes six steps, and not the refusal's three" do
      Seed.request("r-1", :request_approved)
      steps = Paths.observe(ProcessShapes.Promised)

      untaken = for %{taken: 0} = s <- steps, do: names(s)

      assert untaken == [
               {:decide_request, nil, :request_refused},
               {:notify_refusal, nil, :refusal_notified},
               {:request_refused, :notify_on_refusal, :notify_refusal}
             ]

      assert %{taken: 1, mode: :inline} =
               step(steps, :request_approved, :complete_approved, :complete_request)
    end

    test "a refusal waits in the lag of its policy until it is drained, then is taken" do
      Seed.request("r-1", :request_refused)

      waiting =
        ProcessShapes.Promised
        |> Paths.observe()
        |> step(:request_refused, :notify_on_refusal, :notify_refusal)

      assert %{taken: 0, mode: :async, in_flight: %{lag: 1, timers: 0, effects: 0}} = waiting

      Seed.run_queue()

      assert %{taken: 1, in_flight: %{lag: 0}} =
               ProcessShapes.Promised
               |> Paths.observe()
               |> step(:request_refused, :notify_on_refusal, :notify_refusal)
    end

    test "since and until bound what counts as taken" do
      EhosContract.Clock.at(~U[2026-07-01 09:00:00Z], fn ->
        Seed.request("r-1", :request_approved)
      end)

      steps = Paths.observe(ProcessShapes.Promised, since: ~U[2026-08-01 00:00:00Z])
      assert Enum.all?(steps, &(&1.taken == 0))
    end
  end

  describe "the ledger, where every source can be seen" do
    @clerk Actor.credential("u-1", [
             "dispatch_rig.open_account",
             "dispatch_rig.deposit",
             "dispatch_rig.withdraw"
           ])

    defp dispatch(command), do: EhosContract.dispatch(Ledger, command, actor: @clerk)

    setup do
      Testing.drain()
      {:ok, _} = dispatch(%OpenAccount{account_id: "a-1", branch_id: "b-7"})
      :ok
    end

    defp steps, do: Paths.observe(Ledger)

    test "a timer, a process manager's reaction and an effect are steps of their own" do
      declared = Enum.map(Paths.declared(Ledger), &names/1)

      assert {:first_deposit_due, :first_deposit_chase, :flag_account} in declared
      assert {:interest_recorded, :first_deposit_chase, :flag_account} in declared
      assert {:account_flagged, :notify_branch, nil} in declared
    end

    test "a scheduled timer is waiting, and an effect was taken nobody knows how often" do
      Testing.drain()

      assert %{in_flight: %{timers: 1}, taken: 0} =
               step(steps(), :first_deposit_due, :first_deposit_chase, :flag_account)

      assert %{taken: nil} = step(steps(), :account_flagged, :notify_branch, nil)
    end

    test "a timer's firing not yet taken waits on its own step, not on the other timer's" do
      Testing.drain()
      [job] = Repo.all(from(j in Oban.Job, where: j.worker == "EhosContract.TimerJob"))

      EhosContract.Clock.at(DateTime.add(DateTime.utc_now(), 26, :hour), fn ->
        :ok = EhosContract.TimerJob.perform(job)
      end)

      assert %{in_flight: %{lag: 1}} =
               step(steps(), :first_deposit_due, :first_deposit_chase, :flag_account)

      assert %{in_flight: %{lag: 0}} = step(steps(), :review, :first_deposit_chase, :flag_account)
    end

    test "a causing event's own field named timer does not split a reaction's count" do
      for {account, timer} <- [{"a-7", "x"}, {"a-8", "y"}] do
        event =
          record_event!(%{
            type: "dispatch_rig.ledger.deposited",
            contract: "dispatch_rig.ledger",
            contract_version: "v",
            runs: [{"dispatch_rig.ledger_run", "dispatch_rig.ledger_run|#{account}"}],
            payload: %{"account_id" => account, "amount" => 1500, "timer" => timer}
          })

        Repo.insert!(%EhosContract.CommandRecord{
          id: Ecto.UUID.generate(),
          contract: "dispatch_rig.ledger",
          type: "flag_account",
          issued_by: "policy:flag_large_deposit",
          causation_event_id: event.id,
          correlation_id: Ecto.UUID.generate(),
          outcome: "accepted"
        })
      end

      assert %{taken: 2} = step(steps(), :deposited, :flag_large_deposit, :flag_account)
    end

    test "an effect's job waits until it runs" do
      {:ok, _} = dispatch(%Deposit{account_id: "a-1", amount: 1500})

      assert %{in_flight: %{effects: 1}} = step(steps(), :account_flagged, :notify_branch, nil)

      Testing.drain()
      assert %{in_flight: %{effects: 0}} = step(steps(), :account_flagged, :notify_branch, nil)
    end

    test "an effect's job Oban discarded is failing" do
      {:ok, _} = dispatch(%Deposit{account_id: "a-1", amount: 1500})

      Repo.update_all(from(j in Oban.Job, where: j.worker == "EhosContract.EffectJob"),
        set: [state: "discarded"]
      )

      assert %{failing: %{effects: 1}, in_flight: %{effects: 0}} =
               step(steps(), :account_flagged, :notify_branch, nil)
    end

    test "a command that failed in a policy's stage fails that policy's step, not the command's emits" do
      Process.put(:dispatch_rig_flag_fails, true)

      assert_raise RuntimeError, fn -> dispatch(%Deposit{account_id: "a-1", amount: 1500}) end

      assert %{failing: %{commands: 1}} =
               step(steps(), :deposited, :flag_large_deposit, :flag_account)

      assert %{failing: %{commands: 0}} = step(steps(), :deposit, nil, :deposited)
    end

    test "a command that failed in its decision fails every step it emits" do
      Process.put(:dispatch_rig_stray, "a-2")

      assert_raise ArgumentError, fn -> dispatch(%Deposit{account_id: "a-1", amount: 10}) end

      assert %{failing: %{commands: 1}} = step(steps(), :deposit, nil, :deposited)
      assert %{failing: %{commands: 0}} = step(steps(), :withdraw, nil, :withdrawn)
    end

    test "a subscription stopped at an event it cannot apply fails the steps through it" do
      Repo.update_all(
        from(s in SubscriptionRecord,
          where: s.name == "dispatch_rig.ledger:policy:flag_large_withdrawal"
        ),
        set: [status: "failing", failed_position: 42, failure: "RuntimeError"]
      )

      assert %{failing: %{subscription: %{stopped_at: 42, failure: "RuntimeError"}}} =
               step(steps(), :withdrawn, :flag_large_withdrawal, :flag_account)

      assert %{failing: %{subscription: nil}} =
               step(steps(), :deposited, :flag_large_deposit, :flag_account)
    end

    # Plan DD, P1a (#183): one account is one run of the ledger; its two deposits are
    # two occurrences of the step, and read so.
    test "a step taken twice in one run reads 2" do
      {:ok, _} = dispatch(%Deposit{account_id: "a-1", amount: 3})
      {:ok, _} = dispatch(%Deposit{account_id: "a-1", amount: 4})

      assert %{taken: 2} = step(steps(), :deposit, nil, :deposited)
    end

    test "a step is counted whatever process modules include its event" do
      {:ok, _} = dispatch(%Deposit{account_id: "a-1", amount: 3})
      assert EhosContract.Model.process(Ledger) == nil

      assert %{taken: 1} = Ledger |> Paths.observe() |> step(:deposit, nil, :deposited)
    end

    @tag :capture_log
    test "a contract's activity counts a command that failed, as attempted" do
      before = Paths.activity(EhosContract.Model.fetch(Ledger))
      Process.put(:dispatch_rig_flag_fails, true)

      assert_raise RuntimeError, fn -> dispatch(%Deposit{account_id: "a-1", amount: 1500}) end

      after_ = Paths.activity(EhosContract.Model.fetch(Ledger))
      assert after_.commands == before.commands + 1
      assert after_.events == before.events
    end

    test "a command refused with no event recorded in the period is no basis for never" do
      # The account was opened in setup, before the period, which starts an hour ahead;
      # the refused command is recorded inside it. Times are set, not read from two
      # clocks: the database stamps a command, the engine an event.
      since = DateTime.add(DateTime.utc_now(), 3600)

      Repo.insert!(%EhosContract.CommandRecord{
        id: Ecto.UUID.generate(),
        contract: "dispatch_rig.ledger",
        type: "withdraw",
        issued_by: "actor:u-1",
        correlation_id: Ecto.UUID.generate(),
        outcome: "rejected",
        invariant: "sufficient_balance",
        recorded_at: DateTime.add(since, 60)
      })

      report = EhosContract.Conformance.report(Ledger, since: since)
      assert report.activity == %{events: 0, commands: 1}
      assert report.paths.untraversed == []
    end

    test "an ordered policy's command, once drained, took its step" do
      {:ok, _} = dispatch(%Deposit{account_id: "a-1", amount: 3})
      {:ok, _} = dispatch(%Withdraw{account_id: "a-1", amount: 3})
      Testing.drain()

      assert %{taken: 1} = step(steps(), :withdrawn, :return_small_change, :deposit)
    end
  end
end
