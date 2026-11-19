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

    start_supervised!({Registry, keys: :unique, name: Subscription.Head.registry()})
    runner = start_supervised!({Subscription.Runner, @lines})
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
        start_supervised!({Subscription.Head, repo: Repo, poll: @poll})

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
        start_supervised!({Subscription.Head, repo: Repo, poll: @poll})
        assert_receive {:lag, %{lag: 0}, _meta}, 1_000

        # Committed outside the engine's transactions, so nothing notifies: the poll
        # is what finds it, as it finds a host's own transaction.
        event = deposit!(account, 7)

        assert_receive {:step, %{count: 1}, %{result: :applied, position: position}}, 1_000
        assert position == event.position
        assert lines() == [event.position]
        # Back at the head, it stays quiet again.
        assert_receive {:lag, %{lag: 0}, _meta}, 1_000
        send(self(), {:position, event.position})
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
    start_supervised!({Subscription.Head, repo: Repo, poll: @poll})
    assert_receive {:step, _, %{result: :applied}}, 1_000
    assert_receive {:lag, %{lag: 0}, _meta}, 1_000

    :ok = Subscription.rebuild(Repo, @lines)

    # The log of this database holds other tests' events, a poison one among them, so
    # the replay may stop on a failure: either way the runner stepped.
    assert_receive {:step, _measurements, %{result: result}}
                   when result in [:applied, :failed],
                   1_000
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

  defp deposit!(account, amount) do
    {:ok, {:ok, [event]}} =
      Repo.transaction(fn ->
        Store.append(
          Repo,
          [
            %{
              type: "dispatch_rig.ledger.deposited",
              contract: "dispatch_rig.ledger",
              contract_version: "head",
              actor: "system:head",
              correlation_id: Ecto.UUID.generate(),
              occurred_at: DateTime.utc_now(),
              payload: %{"account_id" => account, "amount" => amount}
            }
          ],
          :none
        )
      end)

    event
  end

  defp lines,
    do: Repo.all(from(l in "dispatch_rig_lines", order_by: l.position, select: l.position))
end
