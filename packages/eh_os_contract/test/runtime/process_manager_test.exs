defmodule EhOsContract.ProcessManagerTest do
  @moduledoc """
  Process managers and timers (v2 §12, plan E7b), on `DispatchRig`'s chase of an
  account's first deposit: a run starts when an account opens and sets a day's
  timer; a deposit cancels it; the day passing, or interest before any deposit, flags
  the account, which ends the run.

  Time moves the way a host's test moves it: `EhOsContract.Clock.at/2` around
  `EhOsContract.Testing.drain/1`, which fires only the timers due by then.
  """

  use EhOsContract.DataCase, async: false

  alias DispatchRig.Ledger
  alias DispatchRig.Ledger.Commands.{Deposit, OpenAccount}
  alias DispatchRig.Ledger.Events.InterestRecorded
  alias EhOsContract.{Actor, Clock, Event, ProcessManagerRecord, Subscription, Testing, TimerJob}

  @clerk Actor.credential("u-1", ["dispatch_rig.open_account", "dispatch_rig.deposit"])
  @chase "DispatchRig.Ledger:process_manager:first_deposit_chase"

  @opened ~U[2026-09-01 09:00:00Z]

  defp at(hours, fun), do: Clock.at(DateTime.add(@opened, hours * 3600, :second), fun)

  defp dispatch(command),
    do: {:ok, _} = EhOsContract.dispatch(Ledger, command, actor: @clerk)

  defp open(account \\ "a-1"),
    do: at(0, fn -> dispatch(%OpenAccount{account_id: account, branch_id: "b-7"}) end)

  defp drain_at(hours), do: at(hours, fn -> Testing.drain() end)

  defp run(account \\ "a-1"),
    do: Repo.get_by(ProcessManagerRecord, name: @chase, correlation: account)

  defp of(type), do: Repo.all(from(e in Event, where: e.type == ^type, order_by: e.position))
  defp flags, do: of("ledger.account_flagged")
  defp firings, do: of("eh_os_contract.timer_elapsed")

  defp timer_jobs,
    do: Repo.all(from(j in Oban.Job, where: j.worker == "EhOsContract.TimerJob", order_by: j.id))

  describe "a run" do
    test "starts on the account's opening, with a day's timer and its job" do
      open()
      drain_at(0)

      [opened] = of("ledger.account_opened")

      assert %ProcessManagerRecord{completed_at: nil, timers: %{"first_deposit_due" => timer}} =
               run()

      assert timer["token"] == opened.id
      assert timer["at"] == "2026-09-02T09:00:00.000000Z"
      assert [%Oban.Job{args: %{"timer" => "first_deposit_due", "token" => token}}] = timer_jobs()
      assert token == opened.id
    end

    test "flags the account once the day has passed, and not before" do
      open()
      drain_at(0)

      drain_at(23)
      assert flags() == []

      drain_at(25)
      assert [flag] = flags()
      assert [firing] = firings()

      # The command came from the timer: its cause is the firing, its actor the manager.
      assert flag.metadata["issued_by"] == "pm:first_deposit_chase"

      assert flag.causation_id ==
               Repo.one!(
                 from(c in EhOsContract.CommandRecord,
                   where: c.type == "flag_account",
                   select: c.id
                 )
               )

      assert Repo.one!(
               from(c in EhOsContract.CommandRecord,
                 where: c.type == "flag_account",
                 select: c.causation_event_id
               )
             ) == firing.id

      # The flag ends the run.
      assert %ProcessManagerRecord{completed_at: %DateTime{}, timers: timers} = run()
      assert timers == %{}
    end

    test "is left alone by a deposit within the day, which cancels the timer" do
      open()
      drain_at(0)
      at(2, fn -> dispatch(%Deposit{account_id: "a-1", amount: 10}) end)
      drain_at(2)

      assert %ProcessManagerRecord{timers: %{}} = run()
      assert :erlang.binary_to_term(run().state).deposits == 1

      drain_at(48)
      assert flags() == []
      assert firings() == []
    end

    test "flags an account whose first money is interest, reacting with its state" do
      open()
      drain_at(0)

      at(1, fn ->
        {:ok, _} =
          EhOsContract.record(Ledger, %InterestRecorded{account_id: "a-1", amount: 3},
            actor: Actor.system(:nightly_import)
          )
      end)

      drain_at(1)
      assert [_flag] = flags()
    end

    test "control: interest after a deposit flags nothing" do
      open()
      at(1, fn -> dispatch(%Deposit{account_id: "a-1", amount: 10}) end)

      at(2, fn ->
        {:ok, _} =
          EhOsContract.record(Ledger, %InterestRecorded{account_id: "a-1", amount: 3},
            actor: Actor.system(:nightly_import)
          )
      end)

      drain_at(2)
      assert flags() == []
    end

    @tag :capture_log
    test "reads its state back without creating an atom it does not know" do
      open()
      drain_at(0)

      # A state written by something else than the engine, naming an atom nothing has
      # ever created: the external term format of a small UTF-8 atom.
      name = "eh_os_contract_never_#{System.unique_integer([:positive])}"
      forged = <<131, 119, byte_size(name)>> <> name

      Repo.update_all(from(r in ProcessManagerRecord, where: r.name == @chase),
        set: [state: forged]
      )

      at(1, fn -> dispatch(%Deposit{account_id: "a-1", amount: 10}) end)
      drain_at(1)

      assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
    end

    test "control: events of an account whose run never started change nothing" do
      Testing.drain()
      at(1, fn -> dispatch(%OpenAccount{account_id: "a-9", branch_id: "b-7"}) end)
      Repo.delete_all(from(r in ProcessManagerRecord, where: r.correlation == "a-9"))

      Repo.update_all(from(s in EhOsContract.SubscriptionRecord, where: s.name == @chase),
        set: [position: List.last(of("ledger.account_opened")).position]
      )

      at(2, fn -> dispatch(%Deposit{account_id: "a-9", amount: 10}) end)
      drain_at(2)
      assert run("a-9") == nil
    end
  end

  describe "a timer fired twice" do
    test "dispatches once" do
      open()
      drain_at(0)
      [job] = timer_jobs()

      # Oban delivers at least once: the same job runs twice before the manager
      # takes either firing.
      at(25, fn ->
        assert TimerJob.perform(job) == :ok
        assert TimerJob.perform(job) == :ok
      end)

      assert length(firings()) == 2

      drain_at(25)
      assert length(flags()) == 1
    end

    test "after the manager took the first firing, appends nothing" do
      open()
      drain_at(0)
      [job] = timer_jobs()

      drain_at(25)
      at(26, fn -> assert TimerJob.perform(job) == :ok end)

      assert length(firings()) == 1
      assert length(flags()) == 1
    end

    test "is cancelled when its process manager is no longer deployed" do
      open()
      drain_at(0)
      [job] = timer_jobs()
      gone = put_in(job.args["process_manager"], "DispatchRig.Ledger:process_manager:gone")

      Repo.update_all(from(r in ProcessManagerRecord, where: r.name == @chase),
        set: [name: gone.args["process_manager"]]
      )

      at(25, fn ->
        assert {:cancel, reason} = TimerJob.perform(gone)
        assert reason =~ "no longer deployed"
      end)

      assert firings() == []
    end

    test "control: a job run before its time snoozes and appends nothing" do
      open()
      drain_at(0)
      [job] = timer_jobs()

      # Due at 24 h: an hour early, it snoozes for that hour.
      at(23, fn -> assert TimerJob.perform(job) == {:snooze, 3600} end)

      assert firings() == []
    end
  end

  describe "a replay" do
    test "rebuilds the runs without dispatching, and schedules no timer twice" do
      open()
      open("a-2")
      drain_at(0)
      at(2, fn -> dispatch(%Deposit{account_id: "a-2", amount: 10}) end)
      drain_at(25)

      # a-1 was flagged by its timer and ended; a-2 has a deposit and no timer.
      before = Repo.all(from(r in ProcessManagerRecord, order_by: r.correlation))
      jobs = length(timer_jobs())
      assert length(flags()) == 1

      assert :ok = Subscription.rebuild(Repo, @chase)
      assert Repo.all(ProcessManagerRecord) == []

      drain_at(26)

      after_replay = Repo.all(from(r in ProcessManagerRecord, order_by: r.correlation))

      assert Enum.map(after_replay, &{&1.correlation, &1.state, &1.timers, &1.completed_at}) ==
               Enum.map(before, &{&1.correlation, &1.state, &1.timers, &1.completed_at})

      assert length(flags()) == 1
      assert length(timer_jobs()) == jobs
      assert %{status: "running"} = Repo.get!(EhOsContract.SubscriptionRecord, @chase)
    end

    test "schedules a timer still pending again, once" do
      open()
      drain_at(0)
      assert [_job] = timer_jobs()

      assert :ok = Subscription.rebuild(Repo, @chase)
      drain_at(1)

      assert %ProcessManagerRecord{timers: %{"first_deposit_due" => _}} = run()
      assert [_job] = timer_jobs()

      drain_at(25)
      assert length(flags()) == 1
    end
  end
end
