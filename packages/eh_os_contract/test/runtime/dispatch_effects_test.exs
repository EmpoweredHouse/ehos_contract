defmodule EhOsContract.DispatchEffectsTest do
  @moduledoc """
  Effects (v2 §12, plan E7a). One delivered at least once is an Oban job that holds
  the effect's key and the event's id and nothing else, inserted with the event and
  run after it; one delivered in the transaction acts before the dispatch commits,
  and its error rolls the append back.
  """

  use EhOsContract.DataCase, async: false

  alias DispatchRig.Ledger
  alias DispatchRig.Ledger.Commands.{Deposit, OpenAccount, Withdraw}
  alias EhOsContract.{Actor, CommandRecord, EffectJob, Event}

  @clerk Actor.credential("u-1", [
           "dispatch_rig.open_account",
           "dispatch_rig.deposit",
           "dispatch_rig.withdraw"
         ])

  @notify "dispatch_rig.ledger:effect:notify_branch"

  defp dispatch(command), do: EhOsContract.dispatch(Ledger, command, actor: @clerk)
  defp jobs, do: Repo.all(from(j in Oban.Job, order_by: j.id))
  defp notices, do: Repo.all(from(n in "dispatch_rig_notices", select: n.account_id))
  defp types, do: Repo.all(from(e in Event, order_by: e.position, select: e.type))

  defp flagged(account),
    do:
      Repo.one!(
        from(e in Event,
          where:
            e.type == "dispatch_rig.ledger.account_flagged" and
              fragment("? @> ?", e.tags, ^["account_id:#{account}"])
        )
      )

  setup do
    {:ok, _} = dispatch(%OpenAccount{account_id: "a-1", branch_id: "b-7"})
    {:ok, _} = dispatch(%OpenAccount{account_id: "a-down", branch_id: "b-7"})
    :ok
  end

  describe "an effect delivered at least once" do
    test "is a job holding the effect's key, the event's id and the application, and no payload" do
      {:ok, _} = dispatch(%Deposit{account_id: "a-1", amount: 1000})

      event = flagged("a-1")

      assert [%Oban.Job{worker: "EhOsContract.EffectJob", queue: "events", args: args}] = jobs()

      assert args == %{
               "effect" => @notify,
               "event_id" => event.id,
               "application" => "eh_os_contract"
             }

      assert notices() == []
    end

    test "is inserted with the event, so a dispatch rolled back leaves no job" do
      Repo.transaction(fn ->
        {:ok, _} = dispatch(%Deposit{account_id: "a-1", amount: 1000})
        Repo.rollback(:caller_changed_its_mind)
      end)

      assert jobs() == []
      refute "dispatch_rig.ledger.account_flagged" in types()
    end

    test "control: a deposit that flags nothing inserts no job" do
      {:ok, _} = dispatch(%Deposit{account_id: "a-1", amount: 999})
      assert jobs() == []
    end

    test "runs on the event read back from the log" do
      {:ok, _} = dispatch(%Deposit{account_id: "a-1", amount: 1000})

      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :events)
      assert notices() == ["a-1"]
    end

    test "runs when the contract's application is not among the configured ones" do
      # Dispatch finds a contract's consumers in its own application too; so does the job.
      Application.put_env(:eh_os_contract, :applications, [])
      on_exit(fn -> Application.put_env(:eh_os_contract, :applications, [:eh_os_contract]) end)

      {:ok, _} = dispatch(%Deposit{account_id: "a-1", amount: 1000})

      assert %{success: 1, cancelled: 0} = Oban.drain_queue(queue: :events)
      assert notices() == ["a-1"]
    end

    test "is cancelled when the effect no longer takes the event's type" do
      {:ok, receipt} = dispatch(%Deposit{account_id: "a-1", amount: 5})
      [deposited] = receipt.events

      # The effect handles account_flagged only: a job for a deposit is a wiring that
      # is no longer deployed.
      assert {:cancel, reason} =
               EffectJob.perform(%Oban.Job{
                 args: %{"effect" => @notify, "event_id" => deposited.__meta__.id}
               })

      assert reason =~ "no longer takes dispatch_rig.ledger.deposited"
    end

    test "is retried when it answers {:error, reason}" do
      {:ok, _} = dispatch(%Deposit{account_id: "a-down", amount: 1000})

      assert %{success: 0, failure: 1} = Oban.drain_queue(queue: :events)
      assert [%Oban.Job{state: "retryable", attempt: 1}] = jobs()
      assert notices() == []
    end

    test "is cancelled, not retried, when no module implements the effect any more" do
      {:ok, _} = dispatch(%Deposit{account_id: "a-1", amount: 1000})
      event = flagged("a-1")

      assert {:cancel, reason} =
               EffectJob.perform(%Oban.Job{
                 args: %{"effect" => "dispatch_rig.ledger:effect:gone", "event_id" => event.id}
               })

      assert reason =~ "no module implements effect dispatch_rig.ledger:effect:gone"
    end
  end

  describe "the notification after a commit" do
    setup do
      watch_wakes()
    end

    test "wakes the runners when a command appended something" do
      {:ok, _} = dispatch(%Deposit{account_id: "a-1", amount: 5})
      assert_received :runners_woken
      refute_received :runners_woken
    end

    test "is not sent for a command that appended nothing" do
      {:error, _rejection} = dispatch(%Withdraw{account_id: "a-1", amount: 5})
      refute_received :runners_woken
    end

    test "waits for the commit of a transaction the host owns, which it leaves to the poll" do
      {:ok, _} = Repo.transaction(fn -> dispatch(%Deposit{account_id: "a-1", amount: 5}) end)
      refute_received :runners_woken_in_transaction
      refute_received :runners_woken
    end
  end

  describe "an effect delivered in the transaction" do
    setup do
      {:ok, _} = dispatch(%Deposit{account_id: "a-1", amount: 500})
      :ok
    end

    test "answering {:error, reason} rolls the append back" do
      assert_raise ArgumentError,
                   ~r/effect :audit_withdrawal .* answered \{:error, :audit_unavailable\}/,
                   fn ->
                     dispatch(%Withdraw{account_id: "a-1", amount: 99})
                   end

      refute "dispatch_rig.ledger.withdrawn" in types()

      assert %{outcome: "failed", failed_in: "effect:audit_withdrawal"} =
               Repo.one!(from(c in CommandRecord, where: c.type == "withdraw"))
    end

    test "control: the amount next to it is appended" do
      {:ok, _} = dispatch(%Withdraw{account_id: "a-1", amount: 98})
      assert "dispatch_rig.ledger.withdrawn" in types()
    end
  end
end
