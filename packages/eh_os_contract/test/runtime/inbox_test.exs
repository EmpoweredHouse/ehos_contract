defmodule EhOsContract.InboxTest do
  @moduledoc """
  v2 plan, E12c: another application's published event arrives in an inbox, which
  commits its row with what its policies dispatch and only then acknowledges
  (`EhOsContract.Inbox`, D12). Two invented applications of `BusRig`: the shop
  publishes an order's placing, the warehouse reserves stock for it.

  Most tests hand messages to `EhOsContract.Inbox.take/2` themselves, which is what a
  transport's consumer does with each delivery; the last ones go from the shop's log
  through its relay and `EhOsContract.Bus.Local` to the warehouse's consumer, as in a
  node running both.
  """

  use EhOsContract.DataCase, async: false

  # The inbox logs what it does not acknowledge, which is the point of some of these.
  @moduletag :capture_log

  import ExUnit.CaptureLog

  alias BusRig.Orders
  alias BusRig.Orders.Commands.PlaceOrder
  alias BusRig.Stock.Commands.ReserveStock

  alias EhOsContract.{
    Actor,
    Bus,
    CommandRecord,
    Conformance,
    Event,
    Implementations,
    Inbox,
    InboxRecord,
    Paths,
    Relay,
    Subscription,
    Testing
  }

  @clerk Actor.credential("u-1", ["bus_rig_shop.place_order"])
  @inbox "BusRig.Stock:inbox:order_placed"
  @relay "BusRig.Orders:relay:order_placed"
  @name "bus_rig_shop.order.placed.v1"

  defp inbox, do: Enum.find(Implementations.inboxes(), &(&1.key == @inbox))

  # A message as the shop's relay builds it, for an event that is not in this log.
  defp message(order_id, total) do
    Relay.message(Implementations.consumer(@relay), %Event{
      id: Ecto.UUID.generate(),
      correlation_id: Ecto.UUID.generate(),
      payload: %{"order_id" => order_id, "total" => total, "note" => "gift wrap"}
    })
  end

  defp reserved do
    Repo.all(
      from(e in Event,
        where: e.type == "bus_rig_warehouse.stock.reserved",
        order_by: e.position
      )
    )
  end

  test "an inbox takes what a policy handles, under the name it consumes" do
    assert %{
             contract: BusRig.Stock,
             name: :order_placed,
             from: @name,
             policies: [%{name: :reserve_for_order, module: BusRig.ReserveForOrder}]
           } = inbox()

    assert %{name: @inbox, names: [@name]} = Inbox.consumer(inbox())
  end

  test "consuming a published event asks for <name>.subscribe, the application's, no role's" do
    assert EhOsContract.Model.capabilities(BusRig.Stock) == %{
             "bus_rig_shop.order.placed.subscribe" => %{
               kind: :subscribe,
               name: :order_placed,
               roles: [],
               scope: nil
             },
             "bus_rig_warehouse.reserve_stock" => %{
               kind: :command,
               name: :reserve_stock,
               roles: ["bus_rig_warehouse.keeper"],
               scope: nil
             }
           }
  end

  test "a message reaches the policy, whose fact is caused by the inbox row and joins the run" do
    sent = message("o-1", 120)

    assert Inbox.take(inbox(), sent) == :ack

    assert [%InboxRecord{consumer: @inbox, key: key, id: row_id, message_id: message_id}] =
             Repo.all(InboxRecord)

    assert {key, message_id} == {sent.key, sent.id}

    assert [%Event{payload: %{"order_id" => "o-1", "total" => 120}} = fact] = reserved()
    assert fact.correlation_id == sent.correlation_id
    assert %CommandRecord{causation_event_id: ^row_id} = Repo.get!(CommandRecord, fact.command_id)
  end

  test "a message delivered twice is taken once, and both deliveries are acknowledged" do
    sent = message("o-1", 120)

    assert Inbox.take(inbox(), sent) == :ack
    assert Inbox.take(inbox(), sent) == :ack

    assert [_one] = reserved()
    assert [_one] = Repo.all(InboxRecord)
  end

  test "a message taken wakes the runners once what its policy appended commits" do
    watch_wakes()

    assert Inbox.take(inbox(), message("o-1", 120)) == :ack
    assert_received :runners_woken
    refute_received :runners_woken
  end

  test "a message taken in a transaction the host owns wakes nothing before it commits" do
    watch_wakes()

    {:ok, :ack} = Repo.transaction(fn -> Inbox.take(inbox(), message("o-1", 120)) end)
    refute_received :runners_woken_in_transaction
    refute_received :runners_woken
  end

  test "control: a message taken before wakes nothing" do
    sent = message("o-1", 120)
    assert Inbox.take(inbox(), sent) == :ack
    watch_wakes()

    assert Inbox.take(inbox(), sent) == :ack
    refute_received :runners_woken
  end

  test "the same fact under a new message id is taken once (eh-os FM-08)" do
    first = message("o-1", 120)
    again = message("o-1", 120)
    assert first.id != again.id

    assert Inbox.take(inbox(), first) == :ack
    assert Inbox.take(inbox(), again) == :ack

    assert [_one] = reserved()
  end

  test "control: two facts of two keys are both taken" do
    assert Inbox.take(inbox(), message("o-1", 120)) == :ack
    assert Inbox.take(inbox(), message("o-2", 80)) == :ack

    assert [%{payload: %{"order_id" => "o-1"}}, %{payload: %{"order_id" => "o-2"}}] = reserved()
  end

  # #65: a policy on another application's event is a declared path of the conformance screen,
  # untraversed until a command it issued names an inbox row of its consumer as its cause.
  test "a policy on a received event is a path the screen counts, from the inbox" do
    keeper = Actor.credential("u-2", ["bus_rig_warehouse.reserve_stock"])

    {:ok, _} =
      EhOsContract.dispatch(BusRig.Stock, %ReserveStock{order_id: "o-0", total: 5}, actor: keeper)

    assert [received] =
             for(%{from: %{name: :order_placed}} = step <- Paths.observe(BusRig.Stock), do: step)

    assert %{
             from: %{kind: :event, name: :order_placed},
             via: %{kind: :policy, name: :reserve_for_order},
             to: %{kind: :command, name: :reserve_stock},
             mode: :async,
             runs: 0,
             of_runs: 1
           } = received

    assert [%{from: %{name: :order_placed}}] =
             Conformance.report(BusRig.Stock)
             |> Map.fetch!(:processes)
             |> hd()
             |> Map.fetch!(:untraversed)

    assert "event:order_placed->policy:reserve_for_order->command:reserve_stock" in EhOsContract.Deployment.edge_labels(
             BusRig.Stock
           )

    assert Inbox.take(inbox(), message("o-1", 120)) == :ack
    assert Inbox.take(inbox(), message("o-2", 80)) == :ack

    assert [%{runs: 2, of_runs: 3}] =
             for(%{from: %{name: :order_placed}} = step <- Paths.observe(BusRig.Stock), do: step)

    assert Conformance.report(BusRig.Stock)
           |> Map.fetch!(:processes)
           |> hd()
           |> Map.fetch!(:untraversed) ==
             []

    # Bounded as every step is: by when the inbox took the fact.
    before = DateTime.add(Repo.one!(from(i in InboxRecord, select: min(i.received_at))), -1)

    assert [%{runs: 0}] =
             for(
               %{from: %{name: :order_placed}} = step <-
                 Paths.observe(BusRig.Stock, until: before),
               do: step
             )

    assert [%{runs: 2}] =
             for(
               %{from: %{name: :order_placed}} = step <-
                 Paths.observe(BusRig.Stock, since: before),
               do: step
             )
  end

  # A fact taken under `EhOsContract.Clock.at/2`, as a backfill takes it, is bounded by that
  # time, as the events its policy appends are, not by the database's clock.
  test "a received step is bounded by the engine's clock, as every other step" do
    july = ~U[2026-07-01 12:00:00.000000Z]
    EhOsContract.Clock.at(july, fn -> :ack = Inbox.take(inbox(), message("o-1", 120)) end)

    assert [%{runs: 1}] =
             for(
               %{from: %{name: :order_placed}} = step <-
                 Paths.observe(BusRig.Stock, since: july, until: DateTime.add(july, 1)),
               do: step
             )
  end

  # The inbox is not the policy's subscription: one stopped on the log is no failure of the
  # path from another application.
  test "a received step does not take on the failures of the policy's own subscription" do
    Repo.insert!(%EhOsContract.SubscriptionRecord{
      name: "BusRig.Stock:policy:reserve_for_order",
      kind: "policy",
      mode: "ordered",
      version: "v",
      updated_at: DateTime.utc_now(),
      position: 0,
      status: "failing",
      failed_position: 7,
      failure: "raised"
    })

    Repo.insert!(%CommandRecord{
      id: Ecto.UUID.generate(),
      contract: "bus_rig_warehouse.stock",
      type: "reserve_stock",
      outcome: "failed",
      failed_in: "policy:reserve_for_order",
      issued_by: "policy:reserve_for_order",
      correlation_id: Ecto.UUID.generate(),
      instance_id: "o-9",
      recorded_at: DateTime.utc_now()
    })

    assert [%{failing: %{subscription: nil, commands: 0}}] =
             for(%{from: %{name: :order_placed}} = step <- Paths.observe(BusRig.Stock), do: step)
  end

  test "a message that does not fit what the contract consumes is delivered again" do
    sent = %{message("o-1", 120) | payload: %{"order_id" => "o-1", "total" => "a lot"}}

    log = capture_log(fn -> assert Inbox.take(inbox(), sent) == :nack end)

    assert log =~ "inbox #{@inbox}: #{inspect(@name)} #{inspect(sent.id)} does not fit"
    assert log =~ "[total: :type]"
    refute log =~ "a lot"
    assert Repo.all(InboxRecord) == []
    assert reserved() == []
  end

  test "a policy that raises rolls the row back, and the message is delivered again" do
    sent = message("o-1", 13)

    log = capture_log(fn -> assert Inbox.take(inbox(), sent) == :nack end)

    assert log =~ "inbox #{@inbox}: #{inspect(@name)} #{inspect(sent.id)} failed (RuntimeError)"
    refute log =~ "the warehouse is closed"
    assert Repo.all(InboxRecord) == []

    # Taken again once the policy no longer fails, as a redelivery after a fix is.
    assert Inbox.take(inbox(), %{sent | payload: %{sent.payload | "total" => 14}}) == :ack
    assert [_one] = reserved()
  end

  describe "from the shop's log to the warehouse's policy, through the local bus" do
    setup do
      opts = [name: :"inbox_test_#{System.unique_integer([:positive])}", retry_after: 100]
      previous = Application.get_env(:eh_os_contract, :bus)
      start_supervised!({Bus.Local, opts})
      Application.put_env(:eh_os_contract, :bus, {Bus.Local, opts})

      on_exit(fn ->
        if previous,
          do: Application.put_env(:eh_os_contract, :bus, previous),
          else: Application.delete_env(:eh_os_contract, :bus)
      end)

      :ok
    end

    defp place(id) do
      {:ok, _} =
        EhOsContract.dispatch(Orders, %PlaceOrder{order_id: id, total: 120, note: "gift wrap"},
          actor: @clerk
        )

      Repo.one!(
        from(e in Event,
          where: e.type == "bus_rig_shop.orders.placed" and e.payload["order_id"] == ^id
        )
      )
    end

    test "a placed order is reserved once, also when the relay publishes it again" do
      start_supervised!(Bus.consumer(Inbox.consumer(inbox())))
      assert %{failing: []} = Testing.drain(only: @relay)

      placed = place("o-1")
      Testing.drain(only: @relay)

      assert eventually(fn -> length(reserved()) == 1 end)
      assert [%{correlation_id: correlation}] = reserved()
      assert correlation == placed.correlation_id

      assert [%{message_id: message_id}] = Repo.all(InboxRecord)
      assert message_id == "#{placed.id}/#{@name}"

      # A rebuild publishes the log again under the same ids: a second delivery.
      assert :ok = Subscription.rebuild(Repo, @relay)
      Testing.drain(only: @relay)
      second = place("o-2")
      Testing.drain(only: @relay)

      # The consumer of the local bus takes one message at a time, so once the order
      # placed after the rebuild is reserved, the one published again was taken too.
      assert eventually(fn -> length(reserved()) == 2 end)
      assert [%{payload: %{"order_id" => "o-1"}}, %{payload: %{"order_id" => "o-2"}}] = reserved()
      assert second.correlation_id == List.last(reserved()).correlation_id
    end

    @tag :capture_log
    test "the engine starts every inbox before any relay, so a relay publishes to it" do
      previous = Application.get_env(:eh_os_contract, :subscriptions)
      Application.put_env(:eh_os_contract, :subscriptions, :run)
      on_exit(fn -> Application.put_env(:eh_os_contract, :subscriptions, previous) end)

      # The relay's row is written at its first boot, and an order placed while the
      # node is down is what it publishes as soon as it starts.
      Subscription.register!(Repo, [Implementations.consumer(@relay)])
      place("o-1")

      supervisor = start_supervised!(EhOsContract)

      started =
        supervisor |> Supervisor.which_children() |> Enum.reverse() |> Enum.map(&elem(&1, 0))

      at = fn id -> Enum.find_index(started, &(&1 == id)) end
      assert at.({Inbox.Keeper, @inbox}) < at.({Subscription.Runner, @relay})

      assert eventually(fn -> length(reserved()) == 1 end)
    end
  end

  describe "with the bus down at boot" do
    setup do
      opts = [name: :"inbox_test_down_#{System.unique_integer([:positive])}", retry_after: 100]

      previous = %{
        bus: Application.get_env(:eh_os_contract, :bus),
        subscriptions: Application.get_env(:eh_os_contract, :subscriptions)
      }

      Application.put_env(:eh_os_contract, :bus, {Bus.Local, opts})
      Application.put_env(:eh_os_contract, :subscriptions, :run)

      on_exit(fn ->
        Application.put_env(:eh_os_contract, :subscriptions, previous.subscriptions)

        if previous.bus,
          do: Application.put_env(:eh_os_contract, :bus, previous.bus),
          else: Application.delete_env(:eh_os_contract, :bus)
      end)

      %{opts: opts}
    end

    # The runners are stopped with the test, possibly in the middle of a query.
    @tag :capture_log
    test "the engine boots and keeps its runners, and the inbox subscribes once the bus is up",
         %{opts: opts} do
      {supervisor, log} = with_log(fn -> start_supervised!(EhOsContract) end)
      children = Supervisor.which_children(supervisor)

      assert log =~ "inbox #{@inbox}: its consumer did not start"
      assert Enum.any?(children, &match?({{Subscription.Runner, @relay}, _, _, _}, &1))
      [keeper] = for {{Inbox.Keeper, @inbox}, pid, _, _} <- children, do: pid

      # The keeper tries again after a pause; the test does not wait it out.
      start_supervised!({Bus.Local, opts})
      send(keeper, :start)
      # Handled once the keeper answers: its consumer is subscribed before the relay
      # publishes, which a fresh broker would otherwise drop.
      assert %{child: child} = :sys.get_state(keeper)
      assert is_pid(child)

      place("o-1")
      assert eventually(fn -> length(reserved()) == 1 end)
    end
  end

  defp eventually(check, tries \\ 30) do
    cond do
      check.() -> true
      tries == 0 -> false
      true -> Process.sleep(100) && eventually(check, tries - 1)
    end
  end
end
