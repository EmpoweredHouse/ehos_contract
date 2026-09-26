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

  @lines "DispatchRig.Ledger:read_model:ledger_lines"

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
              type: "ledger.deposited",
              contract: "DispatchRig.Ledger",
              contract_version: "commits",
              process: "ledger",
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
