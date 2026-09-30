defmodule EhOsContract.RelayTest do
  @moduledoc """
  v2 plan, E12b: a `publish` leaves the application through its relay, an ordered
  subscription over the log that hands what it reads to `EhOsContract.Bus` and moves
  only once the transport holds it (`EhOsContract.Relay`, v2 §16).

  Most tests publish through `RecordingBus`, an adapter in this file that reports to
  the test and answers as the test says; the last goes through
  `EhOsContract.Bus.Local` to a consumer, as another application would.
  """

  use EhOsContract.DataCase, async: false

  # A relay the transport fails logs, which is the point of some of these tests.
  @moduletag :capture_log

  alias BusRig.Orders
  alias BusRig.Orders.Commands.{CancelOrder, PlaceOrder}
  alias EhOsContract.{Actor, Bus, Event, Relay, Subscription, SubscriptionRecord, Testing}

  defmodule RecordingBus do
    @moduledoc false
    @behaviour EhOsContract.Bus

    # Runs in the process that drains, so the test steers it through its own
    # dictionary: `:relay_test_answer` is `:ok` (the default), `{:error, reason}`,
    # `:raise`, or `{:during, fun}`, which runs `fun` and then answers `:ok`.
    @impl true
    def publish(opts, messages) do
      send(Keyword.fetch!(opts, :to), {:published, messages})

      case Process.get(:relay_test_answer, :ok) do
        :raise -> raise "transport defect"
        {:during, fun} -> Process.delete(:relay_test_answer) && fun.() && :ok
        answer -> answer
      end
    end

    @impl true
    def consumer(_opts, _consumer), do: raise("not consumed from")
  end

  @clerk Actor.credential("u-1", ["bus_rig_shop.place_order", "bus_rig_shop.cancel_order"])
  @relay "BusRig.Orders:relay:order_placed"
  @name "bus_rig_shop.order.placed.v1"

  setup do
    previous = Application.get_env(:eh_os_contract, :bus)
    Application.put_env(:eh_os_contract, :bus, {RecordingBus, to: self()})

    on_exit(fn ->
      if previous,
        do: Application.put_env(:eh_os_contract, :bus, previous),
        else: Application.delete_env(:eh_os_contract, :bus)
    end)
  end

  defp place(id, total \\ 120),
    do: dispatch(%PlaceOrder{order_id: id, total: total, note: "gift wrap"})

  defp dispatch(command), do: {:ok, _} = EhOsContract.dispatch(Orders, command, actor: @clerk)

  defp placed(id) do
    Repo.one!(from(e in Event, where: e.type == "order.placed" and e.payload["order_id"] == ^id))
  end

  defp row, do: Repo.get!(SubscriptionRecord, @relay)

  # The first drain is the deploy: what is in the log by then is history.
  defp deploy, do: assert(%{failing: []} = Testing.drain(only: @relay))

  defp published_ids do
    receive do
      {:published, messages} -> Enum.map(messages, & &1.id) ++ published_ids()
    after
      0 -> []
    end
  end

  test "an event with a publish leaves as a message of its declared fields, under its id" do
    deploy()
    place("o-1")
    event = placed("o-1")

    assert %{applied: 1, failing: []} = Testing.drain(only: @relay)

    assert_received {:published, [message]}

    assert message == %Bus.Message{
             id: "#{event.id}/#{@name}",
             name: @name,
             correlation_id: event.correlation_id,
             payload: %{"order_id" => "o-1", "total" => 120}
           }

    assert row().position == event.position
  end

  test "an event without a publish does not leave" do
    deploy()
    place("o-1")
    dispatch(%CancelOrder{order_id: "o-1"})

    Testing.drain(only: @relay)

    assert published_ids() == ["#{placed("o-1").id}/#{@name}"]
  end

  test "what is in the log when the relay is first deployed is history, and does not leave" do
    place("o-1")
    deploy()
    assert published_ids() == []

    place("o-2")
    Testing.drain(only: @relay)
    assert published_ids() == ["#{placed("o-2").id}/#{@name}"]
  end

  test "a transport that does not take the batch leaves the position, counts no attempt, " <>
         "and the batch leaves later under the same ids" do
    deploy()
    before = row().position
    place("o-1")
    id = "#{placed("o-1").id}/#{@name}"

    Process.put(:relay_test_answer, {:error, :down})
    assert %{applied: 0, failing: []} = Testing.drain(only: @relay)
    assert published_ids() == [id]
    assert %{position: ^before, attempts: 0, status: "running"} = row()

    Process.put(:relay_test_answer, :ok)
    assert %{applied: 1} = Testing.drain(only: @relay)
    assert published_ids() == [id]
    assert row().position == placed("o-1").position
  end

  test "an event appended while the relay publishes is published by the next step, not skipped" do
    deploy()
    place("o-1")
    Process.put(:relay_test_answer, {:during, fn -> place("o-2") end})

    assert %{applied: 2} = Testing.drain(only: @relay)

    assert published_ids() == ["#{placed("o-1").id}/#{@name}", "#{placed("o-2").id}/#{@name}"]
    assert row().position == placed("o-2").position
  end

  test "with no bus configured a relay waits, and publishes everything since once one is" do
    Application.delete_env(:eh_os_contract, :bus)
    deploy()
    before = row().position
    place("o-1")

    assert %{applied: 0, failing: []} = Testing.drain(only: @relay)
    assert row().position == before

    Application.put_env(:eh_os_contract, :bus, {RecordingBus, to: self()})
    assert %{applied: 1} = Testing.drain(only: @relay)
    assert published_ids() == ["#{placed("o-1").id}/#{@name}"]
  end

  test "a transport that raises fails the event as a policy's would, and the relay stops there" do
    deploy()
    before = row().position
    place("o-1")
    Process.put(:relay_test_answer, :raise)

    assert %{failing: [@relay]} = Testing.drain(only: @relay)

    assert %{status: "failing", position: ^before, attempts: 3, failure: "RuntimeError"} = row()
    assert row().failed_position == placed("o-1").position
  end

  test "a rebuild publishes the log again, under the same ids" do
    deploy()
    place("o-1")
    Testing.drain(only: @relay)
    [id] = published_ids()

    assert :ok = Subscription.rebuild(Repo, @relay)
    Testing.drain(only: @relay)

    assert id in published_ids()
  end

  test "a field the event does not carry is nil in the message" do
    event = %Event{id: Ecto.UUID.generate(), correlation_id: Ecto.UUID.generate(), payload: %{}}
    relay = EhOsContract.Implementations.consumer(@relay)

    assert %Bus.Message{payload: %{"order_id" => nil, "total" => nil}} =
             Relay.message(relay, event)
  end

  describe "through the local bus" do
    setup do
      opts = [name: __MODULE__.Bus]
      start_supervised!({Bus.Local, opts})
      Application.put_env(:eh_os_contract, :bus, {Bus.Local, opts})
      %{opts: opts}
    end

    test "the message reaches another application's consumer of its name", %{opts: opts} do
      test = self()

      handler = fn message ->
        send(test, {:received, message})
        :ack
      end

      start_supervised!(
        Bus.Local.consumer(opts, %{name: "warehouse", names: [@name], handler: handler})
      )

      deploy()
      place("o-1")

      Testing.drain(only: @relay)

      event = placed("o-1")
      assert_receive {:received, %Bus.Message{id: id, payload: payload}}
      assert id == "#{event.id}/#{@name}"
      assert payload == %{"order_id" => "o-1", "total" => 120}
    end
  end
end
