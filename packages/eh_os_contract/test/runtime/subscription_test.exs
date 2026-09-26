defmodule EhOsContract.SubscriptionTest do
  @moduledoc """
  Ordered subscriptions (v2 §12, plan E7a): a read model and a policy delivered at
  least once, fed from the log after the dispatch transaction, in order, each event
  applied once; a poison event that stops its consumer exactly at its position; and
  a rebuild that gives the rows back as they were.

  Everything runs in the test's sandbox transaction through
  `EhOsContract.Testing.drain/1`, the way a host's tests run it.
  """

  use EhOsContract.DataCase, async: false

  # A failing subscription logs an error, which is the point of two of these tests.
  @moduletag :capture_log

  alias DispatchRig.Ledger
  alias DispatchRig.Ledger.Commands.{Deposit, OpenAccount, Withdraw}
  alias EhOsContract.{Actor, Event, Implementations, Subscription, SubscriptionRecord, Testing}

  @clerk Actor.credential("u-1", [
           "dispatch_rig.open_account",
           "dispatch_rig.deposit",
           "dispatch_rig.withdraw"
         ])

  @lines "DispatchRig.Ledger:read_model:ledger_lines"
  @balances "DispatchRig.Ledger:read_model:balances"
  @movements "DispatchRig.Ledger:read_model:movements"
  @flag "DispatchRig.Ledger:policy:flag_large_withdrawal"

  defp dispatch(command), do: {:ok, _} = EhOsContract.dispatch(Ledger, command, actor: @clerk)
  defp deposit(amount), do: dispatch(%Deposit{account_id: "a-1", amount: amount})

  defp lines,
    do:
      Repo.all(
        from(l in "dispatch_rig_lines", order_by: l.position, select: {l.position, l.amount})
      )

  defp amounts, do: Enum.map(lines(), &elem(&1, 1))

  defp balances,
    do:
      Repo.all(
        from(b in "dispatch_rig_balances",
          order_by: b.account_id,
          select: {b.account_id, b.branch_id, b.balance, b.last_position}
        )
      )

  defp row(key), do: Repo.get!(SubscriptionRecord, key)
  defp position_of(amount), do: Enum.find(deposits(), &(&1.payload["amount"] == amount)).position

  defp deposits,
    do: Repo.all(from(e in Event, where: e.type == "ledger.deposited", order_by: e.position))

  defp flagged,
    do:
      Repo.all(from(e in Event, where: e.type == "ledger.account_flagged", order_by: e.position))

  setup do
    dispatch(%OpenAccount{account_id: "a-1", branch_id: "b-7"})
    :ok
  end

  describe "a read model delivered at least once" do
    test "is not projected by dispatch, and catches up in order when drained" do
      deposit(10)
      deposit(20)
      dispatch(%Withdraw{account_id: "a-1", amount: 5})

      assert lines() == []
      assert %{applied: 3, failing: []} = Testing.drain(only: @lines)
      assert amounts() == [10, 20, -5]
      assert row(@lines).position == lines() |> List.last() |> elem(0)
    end

    test "a second drain applies nothing" do
      deposit(10)
      Testing.drain(only: @lines)
      assert %{applied: 0} = Testing.drain(only: @lines)
      assert amounts() == [10]
    end
  end

  describe "a poison event" do
    test "stops the consumer exactly at its position, after three attempts" do
      deposit(10)
      deposit(31)
      deposit(20)

      assert %{failing: [@lines]} = Testing.drain(only: @lines)
      assert amounts() == [10]

      assert %SubscriptionRecord{status: "failing", attempts: 3, failure: "RuntimeError"} =
               row = row(@lines)

      assert row.failed_position == position_of(31)
      assert row.position == position_of(10)
    end

    test "control: without it every event is applied" do
      deposit(10)
      deposit(30)
      deposit(20)

      assert %{failing: []} = Testing.drain(only: @lines)
      assert amounts() == [10, 30, 20]
    end

    test "is never skipped by itself, only by a person, and then only it is" do
      deposit(10)
      deposit(31)
      deposit(20)
      Testing.drain(only: @lines)

      # More drains do not move it.
      assert %{applied: 0, failing: [@lines]} = Testing.drain(only: @lines)

      assert :ok = Subscription.skip(Repo, @lines)
      assert %{failing: []} = Testing.drain(only: @lines)
      assert amounts() == [10, 20]

      assert %SubscriptionRecord{status: "running", failed_position: nil, attempts: 0} =
               row(@lines)
    end

    test "only a failing subscription can be skipped" do
      Testing.drain(only: @lines)
      assert {:error, :not_failing} = Subscription.skip(Repo, @lines)
    end
  end

  describe "a policy delivered at least once" do
    test "reacts after the transaction, and what it issues goes on to the effect" do
      # Registered first: what is in the log when a policy is registered is history.
      Testing.drain()

      # Under 1000 each, so the policy in the transaction flags nothing.
      deposit(900)
      deposit(900)
      dispatch(%Withdraw{account_id: "a-1", amount: 1500})

      assert flagged() == []
      assert %{failing: []} = Testing.drain()

      assert [flag] = flagged()
      assert Repo.all(from(n in "dispatch_rig_notices", select: n.account_id)) == ["a-1"]

      # The chain of policies travels with the event, so a reaction to it continues it.
      assert flag.metadata["chain"] == [
               "DispatchRig.Ledger:flag_large_withdrawal:ledger.withdrawn"
             ]

      assert flag.metadata["issued_by"] == "policy:flag_large_withdrawal"
    end

    test "delivered a second time, appends nothing" do
      Testing.drain(only: @flag)

      # Under 1000 each, so the policy in the transaction flags nothing.
      deposit(900)
      deposit(900)
      dispatch(%Withdraw{account_id: "a-1", amount: 1500})
      Testing.drain(only: @flag)
      assert length(flagged()) == 1

      Repo.update_all(from(s in SubscriptionRecord, where: s.name == @flag), set: [position: 0])

      assert %{applied: applied} = Testing.drain(only: @flag)
      assert applied > 0
      assert length(flagged()) == 1
    end
  end

  describe "rebuilding" do
    test "a read model delivered at least once gives the same rows back" do
      deposit(10)
      deposit(20)
      dispatch(%Withdraw{account_id: "a-1", amount: 5})
      Testing.drain(only: @lines)
      before = lines()

      assert :ok = Subscription.rebuild(Repo, @lines)
      assert lines() == []
      assert row(@lines).position == 0

      Testing.drain(only: @lines)
      assert lines() == before
    end

    test "a read model delivered in the transaction is left to the runner, then back to dispatch" do
      dispatch(%OpenAccount{account_id: "a-2", branch_id: "b-9"})
      deposit(10)
      Testing.drain(only: @balances)
      before = balances()

      assert :ok = Subscription.rebuild(Repo, @balances)
      assert %SubscriptionRecord{status: "rebuilding", position: 0} = row(@balances)
      assert balances() == []

      # While it is rebuilt, dispatch does not project it: neither the deposit nor the
      # account opened meanwhile, which would be a row the runner then inserts again.
      deposit(5)
      dispatch(%OpenAccount{account_id: "a-3", branch_id: "b-7"})
      assert balances() == []

      Testing.drain(only: @balances)
      assert %SubscriptionRecord{status: "running"} = row(@balances)

      assert [{"a-1", "b-7", 15, p1}, {"a-2", "b-9", 0, _}, {"a-3", "b-7", 0, _}] = balances()
      assert p1 == position_of(5)
      assert Enum.map(before, &Tuple.delete_at(&1, 3)) == [{"a-1", "b-7", 10}, {"a-2", "b-9", 0}]

      # And from then on dispatch projects it again, in the transaction.
      deposit(1)
      assert [{"a-1", "b-7", 16, _}, _, _] = balances()
    end

    test "a read model without reset/0 cannot be rebuilt" do
      Testing.drain(only: @movements)
      assert {:error, :no_reset} = Subscription.rebuild(Repo, @movements)
    end

    test "a policy is moved back to the beginning, and reacts to the history it left alone" do
      # History: the policy is registered after this withdrawal, and flags nothing.
      deposit(900)
      deposit(900)
      dispatch(%Withdraw{account_id: "a-1", amount: 1500})
      Testing.drain(only: @flag)
      assert flagged() == []

      assert :ok = Subscription.rebuild(Repo, @flag)
      assert %SubscriptionRecord{position: 0, status: "running"} = row(@flag)

      Testing.drain(only: @flag)
      assert [_flag] = flagged()

      # A second time, the keys derived from the event append nothing again.
      assert :ok = Subscription.rebuild(Repo, @flag)
      Testing.drain(only: @flag)
      assert [_flag] = flagged()
    end
  end

  defp advanced(n \\ 0) do
    receive do
      :advanced -> advanced(n + 1)
    after
      0 -> n
    end
  end

  describe "an inline read model's row" do
    test "is advanced once per dispatch, to the last event it projected" do
      alias DispatchRig.Ledger.Commands.SplitDeposit

      Testing.drain(only: [@balances, @movements])

      test = self()
      id = "advance-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        id,
        [:eh_os_contract, :test_repo, :query],
        fn _, _, %{query: query}, _ ->
          if query =~ ~r/^UPDATE "eh_os_contract_subscriptions"/, do: send(test, :advanced)
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(id) end)

      {:ok, %{position: last}} =
        EhOsContract.dispatch(Ledger, %SplitDeposit{account_id: "a-1", first: 5, second: 6},
          actor: Actor.credential("u-1", ["dispatch_rig.split_deposit"])
        )

      :telemetry.detach(id)

      # Two read models, two events each: one update per read model.
      assert advanced() == 2

      assert row(@balances).position == last
      assert row(@movements).position == last
    end
  end

  describe "registration" do
    test "a read model whose declaration changed is stale, and goes on taking events" do
      Testing.drain(only: @lines)

      Repo.update_all(from(s in SubscriptionRecord, where: s.name == @lines),
        set: [version: "old"]
      )

      Subscription.register!(Repo, [Implementations.consumer(@lines)])
      assert %SubscriptionRecord{status: "stale", version: "old"} = row(@lines)

      deposit(10)
      Testing.drain(only: @lines)
      assert amounts() == [10]

      # A rebuild clears it, with the version the declaration has now.
      assert :ok = Subscription.rebuild(Repo, @lines)
      assert %SubscriptionRecord{status: "running", version: version} = row(@lines)
      assert version == Implementations.consumer(@lines).version
    end

    test "a policy whose declaration changed just takes the new version" do
      Testing.drain(only: @flag)

      Repo.update_all(from(s in SubscriptionRecord, where: s.name == @flag),
        set: [version: "old"]
      )

      Subscription.register!(Repo, [Implementations.consumer(@flag)])
      assert %SubscriptionRecord{status: "running"} = row(@flag)
      refute row(@flag).version == "old"
    end

    test "an ordered read model starts from the beginning of the log, an inline one and a policy at its head" do
      deposit(10)

      Subscription.register!(Repo, [
        Implementations.consumer(@lines),
        Implementations.consumer(@balances),
        Implementations.consumer(@flag)
      ])

      assert row(@lines).position == 0
      assert row(@balances).position == List.last(deposits()).position
      assert row(@flag).position == List.last(deposits()).position
    end

    test "a new policy leaves the history in the log alone, and reacts to what follows" do
      # Before the deploy: a withdrawal the policy would flag.
      for _ <- 1..3, do: deposit(900)
      dispatch(%Withdraw{account_id: "a-1", amount: 1500})

      # The deploy is its first registration.
      Testing.drain(only: @flag)
      assert flagged() == []

      dispatch(%Withdraw{account_id: "a-1", amount: 1100})
      Testing.drain(only: @flag)
      assert [flag] = flagged()

      [_history, withdrawn] =
        Repo.all(from(e in Event, where: e.type == "ledger.withdrawn", order_by: e.position))

      assert flag.metadata["idempotency_key"] =~ withdrawn.id
    end
  end
end
