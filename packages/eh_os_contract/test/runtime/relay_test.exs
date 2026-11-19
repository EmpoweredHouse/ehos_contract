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
    # `:raise`, `:throw`, `{:raise_on, total}`, which raises for a batch holding an order of that
    # total, or `{:during, fun}`, which runs `fun` and then answers `:ok`.
    @impl true
    def publish(opts, messages) do
      send(Keyword.fetch!(opts, :to), {:published, messages})

      case Process.get(:relay_test_answer, :ok) do
        :raise ->
          raise "transport defect"

        :throw ->
          throw(:transport_closed)

        {:raise_on, total} ->
          if Enum.any?(messages, &(&1.payload["total"] == total)), do: raise("defect"), else: :ok

        {:during, fun} ->
          Process.delete(:relay_test_answer) && fun.() && :ok

        answer ->
          answer
      end
    end

    @impl true
    def consumer(_opts, _consumer), do: raise("not consumed from")
  end

  @clerk Actor.credential("u-1", ["bus_rig_shop.place_order", "bus_rig_shop.cancel_order"])
  @relay "bus_rig_shop.orders:relay:order_placed"
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
    Repo.one!(
      from(e in Event,
        where: e.type == "bus_rig_shop.orders.placed" and e.payload["order_id"] == ^id
      )
    )
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
             key: message.key,
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

  # Appended inside the relay's own transaction, which the test owns: this pins that the
  # relay moves to the last event it published and not to the head. Commits in position
  # order under concurrent writers are the store's promise (`EhOsContract.Store.Suite`).
  test "the relay moves to the last event it published, so one appended meanwhile leaves next" do
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

  test "a transport that throws fails the event too, without the thrown value" do
    deploy()
    place("o-1")
    Process.put(:relay_test_answer, :throw)

    assert %{failing: [@relay]} = Testing.drain(only: @relay)
    assert %{status: "failing", failure: "ErlangError"} = row()
  end

  test "a raise in a batch is pinned on its event in one pass, not one pass per event before it" do
    deploy()

    for {id, total} <- [{"o-1", 1}, {"o-2", 2}, {"o-3", 3}, {"o-4", 4}, {"o-5", 666}],
        do: place(id, total)

    Process.put(:relay_test_answer, {:raise_on, 666})
    test = self()
    id = "relay-steps-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      id,
      [:eh_os_contract, :subscription, :step],
      fn _event, measurements, meta, _config -> send(test, {:step, measurements, meta}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)

    assert %{failing: [@relay]} = Testing.drain(only: @relay)

    # The step that pinned the raise reports the 4 events it published before it.
    assert_received {:step, %{count: 4}, %{result: :failed}}

    assert %{position: position, failed_position: failed, attempts: 3} = row()
    assert position == placed("o-4").position
    assert failed == placed("o-5").position

    # Once in the batch that raised, once alone.
    counts = Enum.frequencies(published_ids())
    for id <- ~w(o-1 o-2 o-3 o-4), do: assert(counts["#{placed(id).id}/#{@name}"] == 2)
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

  test "a field the event does not carry is nil in the message, and its key is its id" do
    event = %Event{id: Ecto.UUID.generate(), correlation_id: Ecto.UUID.generate(), payload: %{}}
    relay = EhOsContract.Implementations.consumer(@relay)

    assert %Bus.Message{id: id, key: id, payload: %{"order_id" => nil, "total" => nil}} =
             Relay.message(relay, event)
  end

  test "two events with the idempotent_on values of one fact give messages of one key" do
    relay = EhOsContract.Implementations.consumer(@relay)

    message = fn order_id, total ->
      Relay.message(relay, %Event{
        id: Ecto.UUID.generate(),
        correlation_id: Ecto.UUID.generate(),
        payload: %{"order_id" => order_id, "total" => total, "note" => "n"}
      })
    end

    first = message.("o-1", 120)
    again = message.("o-1", 90)

    assert first.id != again.id
    assert first.key == again.key
    assert first.key =~ ~r/\A[0-9a-f]{64}\z/
    assert message.("o-2", 120).key != first.key
  end

  test "values that only a delimiter tells apart give two keys, not one" do
    publication = %{as: "bus_rig_shop.pair.v1", fields: [:a, :b], idempotent_on: [:a, :b]}

    message = fn payload ->
      Relay.message(%{publication: publication}, %Event{
        id: Ecto.UUID.generate(),
        correlation_id: Ecto.UUID.generate(),
        payload: payload
      })
    end

    first = message.(%{"a" => "x),(s:b,s:y", "b" => "z"})
    second = message.(%{"a" => "x", "b" => "y),(s:b,s:z"})

    assert first.key != second.key
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
