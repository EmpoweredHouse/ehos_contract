defmodule EhosContract.RelayCommitsTest do
  @moduledoc """
  v2 plan, E12b: a relay's runner on real commits, where dispatch's notifications
  arrive while it pauses. The sandbox cannot show it: a runner is another process,
  and it would not see the test's rows. So this runs on `EhosContract.CommitRepo`,
  whose rows stay, and the relay starts at the head of the log.
  """

  use ExUnit.Case, async: false

  @moduletag :capture_log

  import Ecto.Query

  alias BusRig.Orders
  alias BusRig.Orders.Commands.PlaceOrder
  alias EhosContract.CommitRepo, as: Repo
  alias EhosContract.{Actor, Implementations, Subscription, SubscriptionRecord}

  defmodule DownBus do
    @moduledoc false
    @behaviour EhosContract.Bus

    # Reports every attempt and never takes the batch: a broker that is down.
    @impl true
    def publish(opts, messages) do
      send(Keyword.fetch!(opts, :to), {:attempt, length(messages)})
      {:error, :down}
    end

    @impl true
    def consumer(_opts, _consumer), do: raise("not consumed from")
  end

  @relay "bus_rig_shop.orders:relay:order_placed"
  @clerk Actor.credential("u-1", ["bus_rig_shop.place_order"])

  setup do
    previous = %{
      repo: Application.fetch_env!(:ehos_contract, :repo),
      bus: Application.get_env(:ehos_contract, :bus)
    }

    Application.put_env(:ehos_contract, :repo, Repo)
    Application.put_env(:ehos_contract, :bus, {DownBus, to: self()})

    on_exit(fn ->
      Application.put_env(:ehos_contract, :repo, previous.repo)

      if previous.bus,
        do: Application.put_env(:ehos_contract, :bus, previous.bus),
        else: Application.delete_env(:ehos_contract, :bus)
    end)

    Repo.delete_all(from(s in SubscriptionRecord, where: s.name == @relay))
    Subscription.register!(Repo, [Implementations.consumer(@relay)])
    :ok
  end

  test "a relay whose bus is down waits its pause out, whatever dispatch notifies" do
    id = "commits-#{System.unique_integer([:positive])}"

    {:ok, _} =
      EhosContract.dispatch(Orders, %PlaceOrder{order_id: id, total: 1, note: "n"}, actor: @clerk)

    runner = start_supervised!({Subscription.Runner, @relay})
    assert_receive {:attempt, 1}, 2_000

    for _ <- 1..5, do: send(runner, {:notification, :ehos_contract, %{}})

    refute_receive {:attempt, _}, 500
  end

  # A runner catching up is sent a notification per commit, its own among them; a
  # step each would be as many transactions finding nothing. With no bus the relay's
  # step reads nothing, so only the number of steps is counted.
  test "a runner takes the notifications waiting for it in one run" do
    Application.delete_env(:ehos_contract, :bus)
    runner = start_supervised!({Subscription.Runner, @relay})
    # Its first run, at start, is over before it is held: an idle runner keeps no timer.
    wait_for_first_run(runner)
    :ok = :sys.suspend(runner)

    :erlang.trace_pattern({Subscription, :step, 2}, true, [])
    on_exit(fn -> :erlang.trace_pattern({Subscription, :step, 2}, false, []) end)
    1 = :erlang.trace(runner, true, [:call])

    for _ <- 1..5, do: send(runner, {:notification, :ehos_contract, %{}})
    :ok = :sys.resume(runner)
    _ = :sys.get_state(runner)

    ref = :erlang.trace_delivered(runner)
    assert_receive {:trace_delivered, ^runner, ^ref}
    assert steps(runner) == 1
  end

  # The first run's timer, set for 0 ms, is there until it fires.
  defp wait_for_first_run(runner) do
    if :sys.get_state(runner).timer == nil do
      :ok
    else
      Process.sleep(5)
      wait_for_first_run(runner)
    end
  end

  defp steps(runner) do
    receive do
      {:trace, ^runner, :call, {Subscription, :step, _}} -> 1 + steps(runner)
    after
      0 -> 0
    end
  end
end
