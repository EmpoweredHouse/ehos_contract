defmodule EhOsContract.SubscriptionCommitsTest do
  @moduledoc """
  Subscriptions on real commits (plan E7a): **two runners never take the same
  batch**, and a poison event stops the consumer at its position with the failure
  committed, not just rolled back with the test.

  The sandbox cannot show either: its one connection serialises everything, and it
  never commits. So this runs on `EhOsContract.CommitRepo`, with `:repo` pointed at
  it for the test. Rows of the log written here stay for the rest of the run, so the
  subscription starts at the head of the log and the test clears its own lines.
  """

  use ExUnit.Case, async: false

  import Ecto.Query

  alias EhOsContract.CommitRepo, as: Repo
  alias EhOsContract.{Implementations, Store, Subscription, SubscriptionRecord}

  @lines "dispatch_rig.ledger:read_model:ledger_lines"

  setup do
    previous = Application.fetch_env!(:eh_os_contract, :repo)
    Application.put_env(:eh_os_contract, :repo, Repo)
    on_exit(fn -> Application.put_env(:eh_os_contract, :repo, previous) end)

    Repo.delete_all(from(s in SubscriptionRecord, where: s.name == @lines))
    Repo.delete_all("dispatch_rig_lines")

    consumer = Implementations.consumer(@lines)
    Subscription.register!(Repo, [consumer])
    head = Repo.one(from(e in EhOsContract.Event, select: coalesce(max(e.position), 0)))
    Repo.update_all(from(s in SubscriptionRecord, where: s.name == @lines), set: [position: head])

    %{consumer: consumer, account: "commits-#{System.unique_integer([:positive])}"}
  end

  # Deposits appended and committed one transaction each, the way dispatch leaves them.
  defp deposit!(account, amount) do
    {:ok, {:ok, [event]}} =
      Repo.transaction(fn ->
        Store.append(
          Repo,
          [
            %{
              type: "dispatch_rig.ledger.deposited",
              contract: "dispatch_rig.ledger",
              contract_version: "commits",
              actor: "system:commits",
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

  defp row, do: Repo.get!(SubscriptionRecord, @lines)

  test "a second runner gets nothing while the first holds the batch", %{consumer: c, account: a} do
    # The first deposit takes the ledger lines 200 ms, which is how long the first
    # runner holds the row.
    events = [deposit!(a, 500) | for(n <- 1..20, do: deposit!(a, n))]

    first = Task.async(fn -> Subscription.step(Repo, c) end)
    Process.sleep(50)
    second = Task.async(fn -> Subscription.step(Repo, c) end)

    assert Task.await(second) == :idle
    assert Task.await(first) == {:applied, 21}

    assert lines() == Enum.map(events, & &1.position)
    assert row().position == List.last(events).position
    assert Subscription.step(Repo, c) == :idle
  end

  test "many runners at once apply every event exactly once", %{consumer: c, account: a} do
    # Not 31, the ledger lines' poison.
    events = for n <- 1..40, n != 31, do: deposit!(a, n)

    # Each keeps stepping until it finds nothing; a batch applied twice would fail on
    # the lines' key and leave a failure on the row.
    runners =
      for _ <- 1..4 do
        Task.async(fn ->
          Stream.repeatedly(fn -> Subscription.step(Repo, c) end)
          |> Enum.take_while(&match?({:applied, _}, &1))
        end)
      end

    Enum.each(runners, &Task.await/1)

    assert lines() == Enum.map(events, & &1.position)
    assert %SubscriptionRecord{attempts: 0, failed_position: nil, status: "running"} = row()
  end

  describe "an ordered policy" do
    alias DispatchRig.Ledger
    alias DispatchRig.Ledger.Commands.{Deposit, OpenAccount, Withdraw}

    @change "dispatch_rig.ledger:policy:return_small_change"
    @clerk EhOsContract.Actor.credential("u-1", [
             "dispatch_rig.open_account",
             "dispatch_rig.deposit",
             "dispatch_rig.withdraw"
           ])

    defp dispatch!(command), do: {:ok, _} = EhOsContract.dispatch(Ledger, command, actor: @clerk)

    # The notification after each commit goes through Oban, which runs on TestRepo.
    @tag :capture_log
    test "is not failed by another writer of the stream it dispatches to", %{account: a} do
      dispatch!(%OpenAccount{account_id: a, branch_id: "b-commits"})
      dispatch!(%Deposit{account_id: a, amount: 10})
      head = Repo.one(from(e in EhOsContract.Event, select: max(e.position)))
      dispatch!(%Withdraw{account_id: a, amount: 3})

      policy = Implementations.consumer(@change)
      Repo.delete_all(from(s in SubscriptionRecord, where: s.name == @change))
      Subscription.register!(Repo, [policy])

      Repo.update_all(from(s in SubscriptionRecord, where: s.name == @change),
        set: [position: head]
      )

      # Another writer takes the append lock, and appends to the account while the
      # policy's command is being decided.
      stream = EhOsContract.Key.stream(:account, [a])
      parent = self()

      writer =
        Task.async(fn ->
          Repo.transaction(fn ->
            :ok = Store.lock(Repo)
            send(parent, :locked)
            Process.sleep(300)
            version = length(Store.read_stream(Repo, stream, 0))

            {:ok, _} =
              Store.append(
                Repo,
                [
                  %{
                    type: "dispatch_rig.ledger.deposited",
                    contract: "dispatch_rig.ledger",
                    contract_version: "commits",
                    correlation_id: Ecto.UUID.generate(),
                    actor: "system:commits",
                    occurred_at: DateTime.utc_now(),
                    payload: %{"account_id" => a, "amount" => 2}
                  }
                ],
                {:stream, stream, version}
              )
          end)
        end)

      assert_receive :locked
      assert Subscription.step(Repo, policy) == {:applied, 1}
      Task.await(writer)

      assert %SubscriptionRecord{attempts: 0, failed_position: nil} =
               Repo.get!(SubscriptionRecord, @change)

      amounts =
        Repo.all(
          from(e in EhOsContract.Event,
            where: e.stream_id == ^stream and e.type == "dispatch_rig.ledger.deposited",
            order_by: e.stream_version,
            select: e.payload["amount"]
          )
        )

      assert amounts == [10, 2, 1]
    end
  end

  describe "a rebuilt inline read model" do
    @balances "dispatch_rig.ledger:read_model:balances"

    test "goes back to dispatch while a person resets it again, without a deadlock" do
      balances = Implementations.consumer(@balances)
      Repo.delete_all(from(s in SubscriptionRecord, where: s.name == @balances))
      Subscription.register!(Repo, [balances])
      :ok = Subscription.rebuild(Repo, @balances)

      # At the head, so the next step is the one that hands it back to dispatch. Set
      # rather than stepped to: how many steps that takes depends on what earlier
      # tests left in this log.
      head = Repo.one(from(e in EhOsContract.Event, select: coalesce(max(e.position), 0)))

      Repo.update_all(from(s in SubscriptionRecord, where: s.name == @balances),
        set: [position: head]
      )

      parent = self()

      reset =
        Task.async(fn ->
          Repo.transaction(fn ->
            :ok = Store.lock(Repo)
            send(parent, :locked)
            Process.sleep(300)
            Subscription.rebuild(Repo, @balances)
          end)
        end)

      assert_receive :locked
      assert {:applied, _} = Subscription.step(Repo, balances)
      assert Task.await(reset) == {:ok, :ok}
      assert %SubscriptionRecord{status: "running"} = Repo.get!(SubscriptionRecord, @balances)
    end
  end

  @tag :capture_log
  test "a poison event stops it at its position, and the failure is committed", %{
    consumer: c,
    account: a
  } do
    before = deposit!(a, 10)
    poison = deposit!(a, 31)
    _after = deposit!(a, 20)

    # Each attempt is its own transaction: the step rolls back, the failure commits.
    assert Subscription.step(Repo, c) == {:failed, poison.position}
    assert row().attempts == 1
    assert Subscription.step(Repo, c) == {:applied, 1}
    assert Subscription.step(Repo, c) == {:failed, poison.position}
    assert Subscription.step(Repo, c) == {:failed, poison.position}

    assert %SubscriptionRecord{status: "failing", attempts: 3} = row = row()
    assert row.failed_position == poison.position
    assert row.position == before.position
    assert lines() == [before.position]
    assert Subscription.step(Repo, c) == :idle
  end
end
