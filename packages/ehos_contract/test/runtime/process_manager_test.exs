defmodule EhosContract.ProcessManagerTest do
  @moduledoc """
  Process managers and timers (v2 §12, plan E7b), on `DispatchRig`'s chase of an
  account's first deposit: a run starts when an account opens and sets a day's
  timer; a deposit cancels it; the day passing, or interest before any deposit, flags
  the account, which ends the run.

  Time moves the way a host's test moves it: events are stamped in
  `EhosContract.Clock.at/2`, and `EhosContract.Testing.drain/1` fires only the timers
  due by its own time, which `at:`, an enclosing `Clock.at/2` or the host's clock for
  tests gives.
  """

  use EhosContract.DataCase, async: false

  alias DispatchRig.Ledger
  alias DispatchRig.Ledger.Commands.{Deposit, OpenAccount}
  alias DispatchRig.Ledger.Events.InterestRecorded
  alias EhosContract.{Actor, Clock, Event, ProcessManagerRecord, Subscription, Testing, TimerJob}

  @clerk Actor.credential("u-1", ["dispatch_rig.open_account", "dispatch_rig.deposit"])
  @chase "dispatch_rig.ledger:process_manager:first_deposit_chase"

  @opened ~U[2026-09-01 09:00:00Z]

  defp at(hours, fun), do: Clock.at(DateTime.add(@opened, hours * 3600, :second), fun)

  defp dispatch(command),
    do: {:ok, _} = EhosContract.dispatch(Ledger, command, actor: @clerk)

  defp open(account \\ "a-1"),
    do: at(0, fn -> dispatch(%OpenAccount{account_id: account, branch_id: "b-7"}) end)

  defp drain_at(hours), do: at(hours, fn -> Testing.drain() end)

  # The host's clock for tests, as an MFA that gives `hours` after the opening.
  defp clock(hours) do
    Application.put_env(:ehos_contract, Testing,
      now: {DateTime, :add, [@opened, hours * 3600, :second]}
    )
  end

  defp run(account \\ "a-1"),
    do: Repo.get_by(ProcessManagerRecord, name: @chase, correlation: account)

  defp of(type), do: Repo.all(from(e in Event, where: e.type == ^type, order_by: e.position))
  defp flags, do: of("dispatch_rig.ledger.account_flagged")
  defp firings, do: of("ehos_contract.timer_elapsed")

  defp timer_jobs,
    do: Repo.all(from(j in Oban.Job, where: j.worker == "EhosContract.TimerJob", order_by: j.id))

  describe "a run" do
    test "starts on the account's opening, with a day's timer and its job" do
      open()
      drain_at(0)

      [opened] = of("dispatch_rig.ledger.account_opened")

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
                 from(c in EhosContract.CommandRecord,
                   where: c.type == "flag_account",
                   select: c.id
                 )
               )

      assert Repo.one!(
               from(c in EhosContract.CommandRecord,
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

      # The day's timer is gone; the deposit set the week's review instead.
      assert Map.keys(run().timers) == ["review"]
      assert :erlang.binary_to_term(run().state).deposits == 1

      drain_at(48)
      assert flags() == []
      assert firings() == []
    end

    test "fires a timer at a time its state holds, set from the event it just folded" do
      open()
      at(2, fn -> dispatch(%Deposit{account_id: "a-1", amount: 10}) end)
      drain_at(2)

      # A week after the deposit, which evolve/2 put in the state before the timer was set.
      assert run().timers["review"]["at"] == "2026-09-08T11:00:00.000000Z"

      drain_at(169)
      assert flags() == []

      drain_at(171)
      assert [_flag] = flags()
    end

    test "flags an account whose first money is interest, reacting with its state" do
      open()
      drain_at(0)

      at(1, fn ->
        {:ok, _} =
          EhosContract.record(Ledger, %InterestRecorded{account_id: "a-1", amount: 3},
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
          EhosContract.record(Ledger, %InterestRecorded{account_id: "a-1", amount: 3},
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
      name = "ehos_contract_never_#{System.unique_integer([:positive])}"
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

      Repo.update_all(from(s in EhosContract.SubscriptionRecord, where: s.name == @chase),
        set: [position: List.last(of("dispatch_rig.ledger.account_opened")).position]
      )

      at(2, fn -> dispatch(%Deposit{account_id: "a-9", amount: 10}) end)
      drain_at(2)
      assert run("a-9") == nil
    end
  end

  describe "the runners" do
    test "are woken once a timer's firing commits, which only its runner reads" do
      open()
      drain_at(0)
      [job] = timer_jobs()
      watch_wakes()

      at(25, fn -> assert TimerJob.perform(job) == :ok end)

      assert [_firing] = firings()
      assert_received :runners_woken
      refute_received :runners_woken
    end

    test "are woken once a step whose process manager dispatched commits" do
      open()
      drain_at(0)
      [job] = timer_jobs()
      at(25, fn -> assert TimerJob.perform(job) == :ok end)
      consumer = EhosContract.Implementations.consumer(@chase)
      watch_wakes()

      assert {:applied, 1} = at(25, fn -> Subscription.step(Repo, consumer) end)

      assert [_flag] = flags()
      assert_received :runners_woken
      refute_received :runners_woken
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
      watch_wakes()
      at(26, fn -> assert TimerJob.perform(job) == :ok end)

      assert length(firings()) == 1
      assert length(flags()) == 1
      refute_received :runners_woken
    end

    test "is cancelled when its process manager is no longer deployed" do
      open()
      drain_at(0)
      [job] = timer_jobs()
      gone = put_in(job.args["process_manager"], "dispatch_rig.ledger:process_manager:gone")

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

  describe "the drain's time" do
    setup do
      on_exit(fn -> Application.delete_env(:ehos_contract, Testing) end)
    end

    test "is at: when the test gives it, with no Clock.at/2 around the drain" do
      open()
      Testing.drain(at: @opened)

      Testing.drain(at: DateTime.add(@opened, 23 * 3600))
      assert flags() == []

      Testing.drain(at: DateTime.add(@opened, 25 * 3600))
      assert [_flag] = flags()
    end

    test "is the host's clock when the test gives no at:" do
      open()
      drain_at(0)
      clock(23)

      Testing.drain()
      assert flags() == []

      clock(25)
      Testing.drain()
      assert [_flag] = flags()
    end

    test "is at:, or a Clock.at/2 around the drain, before the host's clock" do
      open()
      drain_at(0)
      clock(25)

      Testing.drain(at: DateTime.add(@opened, 23 * 3600))
      drain_at(23)
      at(25, fn -> Testing.drain(at: DateTime.add(@opened, 23 * 3600)) end)
      assert flags() == []

      Testing.drain()
      assert [_flag] = flags()
    end

    test "is the real time without the host's clock" do
      # The account opened on 1 September 2026, so its day has passed in real time.
      open()
      drain_at(0)

      Testing.drain()
      assert [flag] = flags()

      # Each append reads the real time, so the flag comes after the firing it caused.
      assert [firing] = firings()
      assert DateTime.after?(flag.occurred_at, firing.occurred_at)
    end

    test "control: a host's clock that gives no DateTime is refused, naming the clock" do
      Application.put_env(:ehos_contract, Testing, now: {String, :upcase, ["noon"]})

      error = assert_raise ArgumentError, fn -> Testing.drain() end

      assert error.message ==
               "EhosContract.Testing.drain/1 runs timers at a DateTime in UTC, and the " <>
                 "host's clock String.upcase/1 did not give one"
    end

    test "control: a host's clock in another time zone is refused, naming the clock" do
      warsaw = %{DateTime.add(@opened, 3600) | time_zone: "Europe/Warsaw", zone_abbr: "CET"}
      Application.put_env(:ehos_contract, Testing, now: {Function, :identity, [warsaw]})

      error = assert_raise ArgumentError, fn -> Testing.drain() end

      assert error.message ==
               "EhosContract.Testing.drain/1 runs timers at a DateTime in UTC, and the " <>
                 "host's clock Function.identity/1 did not give one"
    end

    test "control: an at: that is no DateTime in UTC is refused, nil included" do
      warsaw = %{@opened | time_zone: "Europe/Warsaw", zone_abbr: "CET"}

      for at <- ["2026-09-02", nil, warsaw] do
        error = assert_raise ArgumentError, fn -> Testing.drain(at: at) end

        assert error.message ==
                 "EhosContract.Testing.drain/1 runs timers at a DateTime in UTC, and at: " <>
                   "did not give one"
      end
    end
  end

  describe "a process manager deployed onto a log with history" do
    test "learns the old runs without steering them, and steers from then on" do
      # Before the deploy: an account opened two days ago, whose day has long passed.
      open("a-old")

      # The deploy: its first registration, 47 hours later, with one more account then.
      at(47, fn -> dispatch(%OpenAccount{account_id: "a-new", branch_id: "b-7"}) end)
      drain_at(47)

      # The old run is known, but its day passed while nothing steered it.
      assert %ProcessManagerRecord{timers: %{}} = run("a-old")
      assert Map.keys(run("a-new").timers) == ["first_deposit_due"]
      assert flags() == []

      drain_at(72)
      assert [flag] = flags()
      assert flag.payload["account_id"] == "a-new"
    end
  end

  describe "an event a run both starts and ends on" do
    # `PhaseRig`'s manager starts on a close and ends on it: a close with no run open
    # starts the run and ends it in the same step, and a close during a run ends it.
    # Drained before each command too, so the manager is deployed before the first.
    @visits "phase_rig.visits:process_manager:watch"

    defp visit(command, id) do
      Testing.drain()
      clerk = Actor.credential("u-1", ~w(phase_rig.book phase_rig.close))
      command = struct(Module.concat([PhaseRig.Visits.Commands, command]), visit_id: id)
      {:ok, _} = EhosContract.dispatch(PhaseRig.Visits, command, actor: clerk)
      %{failing: []} = Testing.drain()
    end

    defp visit_run(id), do: Repo.get_by(ProcessManagerRecord, name: @visits, correlation: id)

    test "with no run yet, starts the run and ends it in one step" do
      visit(Close, "v-1")
      [closed] = of("phase_rig.visits.closed")

      assert %ProcessManagerRecord{completed_at: completed_at, timers: timers} = visit_run("v-1")
      assert completed_at == closed.occurred_at
      assert timers == %{}

      # The run ended: a booking after it starts none, and nothing is noted.
      visit(Book, "v-1")
      assert visit_run("v-1").completed_at == completed_at
      assert of("phase_rig.visits.noted") == []
    end

    test "during a run, ends it" do
      visit(Book, "v-2")
      assert %ProcessManagerRecord{completed_at: nil} = visit_run("v-2")

      visit(Close, "v-2")
      assert %ProcessManagerRecord{completed_at: %DateTime{}} = visit_run("v-2")
      assert length(of("phase_rig.visits.noted")) == 1
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
      assert %{status: "running"} = Repo.get!(EhosContract.SubscriptionRecord, @chase)
    end

    test "skipped at an event it cannot fold, goes on replaying and reacts to none of the history after it" do
      # History: interest before any deposit, which a running manager flags.
      at(0, fn ->
        dispatch(%OpenAccount{account_id: "a-1", branch_id: "b-7"})
        dispatch(%Deposit{account_id: "a-1", amount: 77})
        dispatch(%OpenAccount{account_id: "a-2", branch_id: "b-7"})

        {:ok, _} =
          EhosContract.record(Ledger, %InterestRecorded{account_id: "a-2", amount: 3},
            actor: Actor.system(:nightly_import)
          )
      end)

      # The deploy replays it, and fails on the deposit it cannot fold.
      assert %{failing: [@chase]} = drain_at(1)
      assert %{status: "failing"} = Repo.get!(EhosContract.SubscriptionRecord, @chase)

      assert :ok = Subscription.skip(Repo, @chase)
      assert %{status: "rebuilding"} = Repo.get!(EhosContract.SubscriptionRecord, @chase)

      assert %{failing: []} = drain_at(1)
      assert flags() == []
      assert %ProcessManagerRecord{completed_at: nil} = run("a-2")
      assert %{status: "running"} = Repo.get!(EhosContract.SubscriptionRecord, @chase)
    end

    test "takes events in batches, since it dispatches nothing" do
      for account <- ~w(a-1 a-2 a-3), do: open(account)
      drain_at(0)

      assert :ok = Subscription.rebuild(Repo, @chase)
      consumer = EhosContract.Implementations.consumer(@chase)

      assert {:applied, 3} = at(1, fn -> Subscription.step(Repo, consumer) end)
    end

    test "keeps a timer that came due while it was running, whose job is still queued" do
      open()
      drain_at(0)

      # Rebuilt a day and more later, before the queued job ran.
      assert :ok = Subscription.rebuild(Repo, @chase)
      drain_at(25)

      assert [_flag] = flags()
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
