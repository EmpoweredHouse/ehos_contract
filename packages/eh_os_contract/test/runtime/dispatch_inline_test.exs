defmodule EhOsContract.DispatchInlineTest do
  @moduledoc """
  What runs inside the dispatch transaction (v2 §11–12): read models project the
  appended events, and policies dispatch what they issue as their own actor. It all
  commits with the append, or none of it does.
  """

  use EhOsContract.DataCase, async: false

  alias DispatchRig.Ledger
  alias DispatchRig.Ledger.Commands.{Deposit, OpenAccount}
  alias EhOsContract.{Actor, CommandRecord, Event}

  @clerk Actor.credential("u-1", ["dispatch_rig.open_account", "dispatch_rig.deposit"])

  defp log, do: Repo.all(from(e in Event, order_by: e.position))
  defp rows, do: Repo.all(from(c in CommandRecord, order_by: c.recorded_at))

  defp balance(account),
    do:
      Repo.one(
        from(b in "dispatch_rig_balances", where: b.account_id == ^account, select: b.balance)
      )

  defp movements, do: Repo.all(from(m in "dispatch_rig_movements", select: m.amount))

  defp dispatch(command), do: EhOsContract.dispatch(Ledger, command, actor: @clerk)

  setup do
    {:ok, _} = dispatch(%OpenAccount{account_id: "a-1", branch_id: "b-7"})
    :ok
  end

  describe "read models" do
    test "project every appended event in the same transaction" do
      {:ok, _} = dispatch(%Deposit{account_id: "a-1", amount: 40})
      {:ok, _} = dispatch(%Deposit{account_id: "a-1", amount: 2})

      assert balance("a-1") == 42
      assert movements() == [40, 2]
    end

    test "an exception in one rolls the append back, and every other projection with it" do
      assert_raise RuntimeError, ~r/fails on 13/, fn ->
        dispatch(%Deposit{account_id: "a-1", amount: 13})
      end

      assert Enum.map(log(), & &1.type) == ["ledger.account_opened"]
      assert balance("a-1") == 0
      assert movements() == []
      assert %{outcome: "failed", failed_in: "read_model:movements"} = List.last(rows())
    end

    @tag :capture_log
    test "when the failed row cannot be written either, the caller still gets the first exception" do
      Application.put_env(:eh_os_contract, :repo, EhOsContract.BrokenRepo)
      on_exit(fn -> Application.put_env(:eh_os_contract, :repo, EhOsContract.TestRepo) end)

      assert_raise RuntimeError, ~r/fails on 13/, fn ->
        dispatch(%Deposit{account_id: "a-1", amount: 13})
      end

      assert Enum.map(log(), & &1.type) == ["ledger.account_opened"]
    end

    test "control: the amount next to it is appended and projected" do
      {:ok, _} = dispatch(%Deposit{account_id: "a-1", amount: 12})
      assert balance("a-1") == 12
      assert movements() == [12]
    end
  end

  describe "policies" do
    test "dispatch what they issue in the same transaction, as their own actor" do
      {:ok, receipt} = dispatch(%Deposit{account_id: "a-1", amount: 1000})
      [deposited] = receipt.events

      assert [_opened, _deposited, flagged] = log()
      assert flagged.type == "ledger.account_flagged"
      assert flagged.actor == "policy:flag_large_deposit"
      assert flagged.correlation_id == deposited.__meta__.correlation_id

      flag = Enum.find(rows(), &(&1.type == "flag_account"))
      assert flag.outcome == "accepted"
      assert flag.issued_by == "policy:flag_large_deposit"
      assert flag.causation_event_id == deposited.__meta__.id
      # The contract is in the key: the index of accepted keys spans the application,
      # and two contracts may each have a policy of the same name on the same event.
      assert flag.idempotency_key ==
               "policy:DispatchRig.Ledger:flag_large_deposit:#{deposited.__meta__.id}:0"

      assert flagged.causation_id == flag.id
    end

    test "a failure in what a policy issued rolls everything back, and names the policy" do
      Process.put(:dispatch_rig_flag_fails, true)

      assert_raise RuntimeError, ~r/flagging fails/, fn ->
        dispatch(%Deposit{account_id: "a-1", amount: 1000})
      end

      assert Enum.map(log(), & &1.type) == ["ledger.account_opened"]

      # One failed row, the deposit's: its own decider ran fine, and the failure came
      # from the policy it set off.
      assert [%{type: "deposit", failed_in: "policy:flag_large_deposit"}] =
               Enum.filter(rows(), &(&1.outcome == "failed"))
    end

    test "control: a deposit below the threshold issues nothing" do
      {:ok, _} = dispatch(%Deposit{account_id: "a-1", amount: 999})
      refute Enum.any?(log(), &(&1.type == "ledger.account_flagged"))
    end

    test "a command only a policy issues is refused to the application's own actors" do
      assert EhOsContract.dispatch(
               Ledger,
               %DispatchRig.Ledger.Commands.FlagAccount{account_id: "a-1"},
               actor: Actor.system(:nightly_import)
             ) == {:error, :not_declared}
    end

    test "a policy that reacts to what it already reacted to down one chain is stopped" do
      assert_raise ArgumentError, ~r/again down one chain of dispatches/, fn ->
        dispatch(%Deposit{account_id: "a-1", amount: 777})
      end

      assert Enum.map(log(), & &1.type) == ["ledger.account_opened"]
    end
  end
end
