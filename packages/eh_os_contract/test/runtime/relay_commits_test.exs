defmodule EhOsContract.RelayCommitsTest do
  @moduledoc """
  v2 plan, E12b: a relay's runner on real commits, where dispatch's notifications
  arrive while it pauses. The sandbox cannot show it: a runner is another process,
  and it would not see the test's rows. So this runs on `EhOsContract.CommitRepo`,
  whose rows stay, and the relay starts at the head of the log.
  """

  use ExUnit.Case, async: false

  @moduletag :capture_log

  import Ecto.Query

  alias BusRig.Orders
  alias BusRig.Orders.Commands.PlaceOrder
  alias EhOsContract.CommitRepo, as: Repo
  alias EhOsContract.{Actor, Implementations, Subscription, SubscriptionRecord}

  defmodule DownBus do
    @moduledoc false
    @behaviour EhOsContract.Bus

    # Reports every attempt and never takes the batch: a broker that is down.
    @impl true
    def publish(opts, messages) do
      send(Keyword.fetch!(opts, :to), {:attempt, length(messages)})
      {:error, :down}
    end

    @impl true
    def consumer(_opts, _consumer), do: raise("not consumed from")
  end

  @relay "BusRig.Orders:relay:order_placed"
  @clerk Actor.credential("u-1", ["bus_rig_shop.place_order"])

  setup do
    previous = %{
      repo: Application.fetch_env!(:eh_os_contract, :repo),
      bus: Application.get_env(:eh_os_contract, :bus)
    }

    Application.put_env(:eh_os_contract, :repo, Repo)
    Application.put_env(:eh_os_contract, :bus, {DownBus, to: self()})

    on_exit(fn ->
      Application.put_env(:eh_os_contract, :repo, previous.repo)

      if previous.bus,
        do: Application.put_env(:eh_os_contract, :bus, previous.bus),
        else: Application.delete_env(:eh_os_contract, :bus)
    end)

    Repo.delete_all(from(s in SubscriptionRecord, where: s.name == @relay))
    Subscription.register!(Repo, [Implementations.consumer(@relay)])
    :ok
  end

  test "a relay whose bus is down waits its pause out, whatever dispatch notifies" do
    id = "commits-#{System.unique_integer([:positive])}"

    {:ok, _} =
      EhOsContract.dispatch(Orders, %PlaceOrder{order_id: id, total: 1, note: "n"}, actor: @clerk)

    runner = start_supervised!({Subscription.Runner, @relay})
    assert_receive {:attempt, 1}, 2_000

    for _ <- 1..5, do: send(runner, {:notification, :eh_os_contract, %{}})

    refute_receive {:attempt, _}, 500
  end
end
