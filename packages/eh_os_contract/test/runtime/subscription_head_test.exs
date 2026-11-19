defmodule EhOsContract.SubscriptionHeadTest do
  @moduledoc """
  The node's poll (`EhOsContract.Subscription.Head`, #635): an idle runner starts no
  transaction and logs nothing however often the node polls, and a runner whose row
  is behind the head of the log, or was changed by a person, is woken.

  A runner is another process, and would not see the sandbox's rows, so this runs on
  `EhOsContract.CommitRepo`, as `SubscriptionCommitsTest` does, with the read model
  starting at the head of the log.
  """

  use ExUnit.Case, async: false

  import Ecto.Query
  import ExUnit.CaptureLog

  alias EhOsContract.CommitRepo, as: Repo
  alias EhOsContract.{Implementations, Store, Subscription, SubscriptionRecord}

  @lines "dispatch_rig.ledger:read_model:ledger_lines"
  @poll 50
  @runners __MODULE__.Runners

  setup do
    previous = %{
      repo: Application.fetch_env!(:eh_os_contract, :repo),
      level: Logger.level()
    }

    Application.put_env(:eh_os_contract, :repo, Repo)
    # What a host's development logger shows, which is where the polling was seen.
    Logger.configure(level: :debug)

    on_exit(fn ->
      Logger.configure(level: previous.level)
      Application.put_env(:eh_os_contract, :repo, previous.repo)
    end)

    Repo.delete_all(from(s in SubscriptionRecord, where: s.name == @lines))
    Repo.delete_all("dispatch_rig_lines")

    Subscription.register!(Repo, [Implementations.consumer(@lines)])
    head = Repo.one(from(e in EhOsContract.Event, select: coalesce(max(e.position), 0)))
    Repo.update_all(from(s in SubscriptionRecord, where: s.name == @lines), set: [position: head])

    start_supervised!(%{
      id: @runners,
      start:
        {Supervisor, :start_link,
         [[{Subscription.Runner, @lines}], [strategy: :one_for_one, name: @runners]]},
      type: :supervisor
    })

    [{_id, runner, :worker, _modules}] = Supervisor.which_children(@runners)
    wait_for_first_run(runner)

    test = self()
    id = "head-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        id,
        [
          [:eh_os_contract, :commit_repo, :query],
          [:eh_os_contract, :subscription, :lag],
          [:eh_os_contract, :subscription, :step]
        ],
        &__MODULE__.observed/4,
        %{test: test, runner: runner}
      )

    on_exit(fn -> :telemetry.detach(id) end)
    %{runner: runner, account: "head-#{System.unique_integer([:positive])}"}
  end

  @doc false
  def observed([_, _, :query], _measurements, _metadata, %{test: test, runner: runner}) do
    if self() == runner, do: send(test, :runner_queried)
  end

  def observed([_, :subscription, :lag], measurements, %{subscription: @lines} = meta, config),
    do: send(config.test, {:lag, measurements, meta})

  def observed([_, :subscription, :step], measurements, %{subscription: @lines} = meta, config),
    do: send(config.test, {:step, measurements, meta})

  def observed(_event, _measurements, _metadata, _config), do: :ok

  test "an idle runner starts no transaction and logs nothing while the node polls" do
    log =
      capture_log([level: :debug], fn ->
        start_supervised!({Subscription.Head, repo: Repo, poll: @poll, runners: @runners})

        # Polls for longer than a runner's own poll took before #635 (1 s), all of
        # them finding the read model at the head.
        for _ <- 1..30, do: assert_receive({:lag, %{lag: 0}, %{status: "running"}}, 1_000)
      end)

    refute_received :runner_queried
    refute_received {:step, _, _}
    assert log == ""
  end

  test "a runner behind the head is woken and says in one line what it applied", %{
    account: account
  } do
    log =
      capture_log([level: :debug], fn ->
        start_supervised!({Subscription.Head, repo: Repo, poll: @poll, runners: @runners})
        assert_receive {:lag, %{lag: 0}, _meta}, 1_000

        # Committed outside the engine's transactions, so nothing notifies: the poll
        # is what finds it, as it finds a host's own transaction.
        event = deposit!(account, 7)

        assert_receive {:step, %{count: 1}, %{result: :applied, position: position}}, 1_000
        assert position == event
        assert lines() == [event]
        # Back at the head of the log it just read.
        assert_receive {:lag, %{lag: 0, head: ^position}, _meta}, 1_000
        send(self(), {:position, event})
      end)

    assert_received {:position, position}

    assert log =~
             "subscription #{@lines}: applied 1 event(s), now at position #{position}"

    refute log =~ "eh_os_contract_subscriptions"
    refute log =~ "FOR UPDATE"
  end

  # A person's rebuild moves the row and appends nothing: the head does not move, and
  # only the row's change tells the poll to wake the runner.
  @tag :capture_log
  test "a rebuild wakes the runner with nothing new in the log", %{account: account} do
    deposit!(account, 3)
    start_supervised!({Subscription.Head, repo: Repo, poll: @poll, runners: @runners})
    assert_receive {:step, _, %{result: :applied}}, 1_000
    assert_receive {:lag, %{lag: 0}, _meta}, 1_000

    :ok = Subscription.rebuild(Repo, @lines)

    # The log of this database holds other tests' events, a poison one among them, so
    # the replay may stop on a failure: either way the runner stepped.
    assert_receive {:step, _measurements, %{result: result}}
                   when result in [:applied, :failed],
                   1_000
  end

  # A consumer of few types stays behind the head of the whole log between its events.
  # The poll wakes it once to look at what was appended, not at every poll after.
  test "a runner behind the head on events it does not take steps once, not at every poll" do
    start_supervised!({Subscription.Head, repo: Repo, poll: @poll, runners: @runners})
    assert_receive {:lag, %{lag: 0}, _meta}, 1_000

    other = append!("dispatch_rig.ledger.audited", %{})

    assert_receive {:step, _measurements, %{result: :idle}}, 1_000
    assert_receive {:lag, %{head: ^other}, _meta}, 1_000
    refute_receive {:step, _measurements, _meta}, 20 * @poll
  end

  # Another runner holds the row, and its step writes nothing: here a transaction that
  # takes the row and rolls back. Neither the head nor the row moves after the wake,
  # so only the held runner's own retry applies the event.
  @tag :capture_log
  test "a runner that finds its row held by another tries again by itself", %{
    account: account
  } do
    test = self()

    holder =
      Task.async(fn ->
        Repo.transaction(fn ->
          Repo.one(from(s in SubscriptionRecord, where: s.name == @lines, lock: "FOR UPDATE"))

          send(test, :held)
          receive do: (:release -> Repo.rollback(:released))
        end)
      end)

    assert_receive :held, 1_000
    start_supervised!({Subscription.Head, repo: Repo, poll: @poll, runners: @runners})
    event = deposit!(account, 9)

    assert_receive {:step, _measurements, %{result: :held}}, 1_000
    send(holder.pid, :release)
    assert Task.await(holder) == {:error, :released}

    assert_receive {:step, %{count: 1}, %{result: :applied, position: position}}, 3_000
    assert position == event
  end

  # The runners' supervisor stops between the lookup of its name and the call, as when
  # its parent restarts it: the poll read the head, so it still reports, and says
  # nothing of the head of the log.
  test "a runners' supervisor that stops during the poll loses no lag and logs nothing" do
    gone = :"#{__MODULE__}.Gone"
    pid = spawn(fn -> receive do: (_call -> exit(:restarting)) end)
    Process.register(pid, gone)

    log =
      capture_log(fn ->
        start_supervised!({Subscription.Head, repo: Repo, poll: @poll, runners: gone})
        # The second poll's lag comes after the first poll ended.
        assert_receive {:lag, _measurements, _meta}, 1_000
        assert_receive {:lag, _measurements, _meta}, 1_000
      end)

    refute log =~ "could not read the head"
  end

  # An append in a transaction the host owns wakes the runners when it commits (#635):
  # the log's trigger notifies the channel on which Oban's Postgres notifier hands
  # `{:notification, :eh_os_contract, %{}}` to each runner, and only at commit.
  test "an append notifies the runners' channel once, when its transaction commits", %{
    account: account
  } do
    listener = start_supervised!({Postgrex.Notifications, Repo.config()})
    {:ok, _ref} = Postgrex.Notifications.listen(listener, "public.oban_eh_os_contract")
    test = self()

    appender =
      Task.async(fn ->
        Repo.transaction(fn ->
          for amount <- [1, 2] do
            {:ok, [_event]} = Store.append(Repo, [entry(deposited(account, amount))], :none)
          end

          send(test, :appended)
          receive do: (:commit -> :ok)
        end)
      end)

    assert_receive :appended, 1_000
    refute_receive {:notification, _pid, _ref, _channel, _payload}, 200

    send(appender.pid, :commit)
    assert Task.await(appender) == {:ok, :ok}

    assert_receive {:notification, ^listener, _ref, "public.oban_eh_os_contract", "{}"}, 1_000
    # Two appends, one transaction: Postgres sends one notification.
    refute_receive {:notification, _pid, _ref, _channel, _payload}, 200
  end

  defmodule SlowRepo do
    @moduledoc false
    # A database that answers each poll after 100 ms, and says when each poll started.
    def one(_query, _opts) do
      send(:persistent_term.get(__MODULE__), {:polled, System.monotonic_time(:millisecond)})
      Process.sleep(100)
      0
    end

    def all(_query, _opts), do: []
  end

  # A timer set before the poll fires while a slow poll runs, and the polls then hold a
  # connection back to back on a database that is already slow.
  test "on a slow database the next poll waits its pause after the last one ends" do
    :persistent_term.put(SlowRepo, self())
    on_exit(fn -> :persistent_term.erase(SlowRepo) end)
    start_supervised!({Subscription.Head, repo: SlowRepo, poll: 100})

    assert_receive {:polled, first}, 1_000
    assert_receive {:polled, second}, 1_000
    assert second - first >= 200
  end

  # The first run's timer, set for 0 ms, is there until it fires; an idle runner then
  # keeps no timer.
  defp wait_for_first_run(runner) do
    if :sys.get_state(runner).timer == nil do
      :ok
    else
      Process.sleep(5)
      wait_for_first_run(runner)
    end
  end

  defp deposit!(account, amount),
    do: append!("dispatch_rig.ledger.deposited", deposited(account, amount))

  defp deposited(account, amount), do: %{"account_id" => account, "amount" => amount}

  # Committed in a transaction of its own, outside the engine's, so no runner is told
  # by dispatch.
  defp append!(type, payload) do
    {:ok, {:ok, [event]}} =
      Repo.transaction(fn -> Store.append(Repo, [entry(payload, type)], :none) end)

    event.position
  end

  defp entry(payload, type \\ "dispatch_rig.ledger.deposited") do
    %{
      type: type,
      contract: "dispatch_rig.ledger",
      contract_version: "head",
      actor: "system:head",
      correlation_id: Ecto.UUID.generate(),
      occurred_at: DateTime.utc_now(),
      payload: payload
    }
  end

  defp lines,
    do: Repo.all(from(l in "dispatch_rig_lines", order_by: l.position, select: l.position))
end
