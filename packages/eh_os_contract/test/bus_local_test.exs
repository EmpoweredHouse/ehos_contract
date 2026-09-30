defmodule EhOsContract.Bus.LocalTest do
  @moduledoc """
  v2 plan, E12a: `EhOsContract.Bus.Local` against `EhOsContract.Bus.Suite`, and what
  the local adapter adds to what the suite asks.
  """

  use ExUnit.Case, async: false

  @moduletag :capture_log

  use EhOsContract.Bus.Suite,
    bus: {EhOsContract.Bus.Local, name: __MODULE__.Bus},
    start: [{EhOsContract.Bus.Local, name: __MODULE__.Bus, retry_after: 10}]

  alias EhOsContract.Bus
  alias EhOsContract.Bus.{Local, Message}

  @opts [name: __MODULE__.Bus]

  describe "the local adapter" do
    test "a payload JSON cannot carry is refused in the publisher's process" do
      message = bus_message(bus_name("tuple"), %{"at" => {2026, 10, 1}})
      assert_raise Protocol.UndefinedError, fn -> Local.publish(@opts, [message]) end
    end

    test "what arrives is what JSON decodes, not the terms that were sent" do
      name = bus_name("json")
      consumer = bus_name("consumer")
      bus_consume(consumer, [name])

      bus_publish([
        bus_message(name, %{"on" => ~D[2026-10-01], "amount" => Decimal.new("12.50")})
      ])

      assert [%Message{payload: %{"on" => "2026-10-01", "amount" => "12.50"}}] =
               bus_received(consumer, 1)
    end

    test "a consumer gets nothing published before it first subscribed" do
      name = bus_name("before")
      consumer = bus_name("consumer")
      bus_publish([bus_message(name)])

      bus_consume(consumer, [name])
      bus_nothing_more(consumer)
    end

    test "a message published twice is delivered twice" do
      name = bus_name("twice")
      consumer = bus_name("consumer")
      bus_consume(consumer, [name])

      sent = bus_message(name)
      bus_publish([sent, sent])

      assert [^sent, ^sent] = bus_received(consumer, 2)
    end

    test "a handler whose linked process crashes gets the message again, from the same consumer" do
      name = bus_name("linked")
      consumer = bus_name("consumer")

      crash_linked =
        bus_first_time(fn ->
          linked = spawn_link(fn -> raise "linked defect" end)
          ref = Process.monitor(linked)
          assert_receive {:DOWN, ^ref, :process, ^linked, _reason}
          :ack
        end)

      pid = bus_consume(consumer, [name], crash_linked)

      sent = bus_message(name)
      bus_publish([sent])

      assert [^sent, ^sent] = bus_received(consumer, 2)
      assert Process.alive?(pid)
    end

    test "a message a killed consumer had in hand waits retry_after before it comes again" do
      slow = [name: __MODULE__.Slow, retry_after: 300]
      start_supervised!({Local, slow})
      name = bus_name("slow")
      test = self()

      hold = bus_first_time(fn -> Process.sleep(:infinity) end)

      handler = fn message ->
        send(test, {:slow, message.id})
        hold.(message)
      end

      spec = Local.consumer(slow, %{name: bus_name("consumer"), names: [name], handler: handler})
      pid = start_supervised!(spec)
      %Message{id: id} = sent = bus_message(name)
      :ok = Local.publish(slow, [sent])
      assert_receive {:slow, ^id}

      Process.exit(pid, :kill)

      refute_receive {:slow, ^id}, 150
      assert_receive {:slow, ^id}, 2_000
    end

    test "what a handler leaves in the consumer's mailbox does not stop the consumer" do
      name = bus_name("stray")
      consumer = bus_name("consumer")

      pid =
        bus_consume(consumer, [name], fn _message ->
          Process.monitor(spawn(fn -> :ok end))
          send(self(), :stray)
          :ack
        end)

      bus_publish([bus_message(name)])
      assert [_first] = bus_received(consumer, 1)
      bus_publish([bus_message(name)])
      assert [_second] = bus_received(consumer, 1)

      assert Process.alive?(pid)
    end

    test "a failure's log line quotes the message's id, so a received id cannot forge a line" do
      name = bus_name("forged")
      consumer = bus_name("consumer")
      bus_consume(consumer, [name], bus_first_time(fn -> raise "handler defect" end))
      sent = %{bus_message(name) | id: "id\n[error] forged line"}

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          bus_publish([sent])
          assert [^sent, ^sent] = bus_received(consumer, 2)
        end)

      assert log =~ inspect(sent.id)
      refute log =~ "\n[error] forged line"
    end

    test "a take for a name nobody subscribed is refused, and the broker stays up" do
      broker = GenServer.whereis(__MODULE__.Bus)

      assert {:error, :unsubscribed} = GenServer.call(broker, {:take, bus_name("never")})
      assert GenServer.whereis(__MODULE__.Bus) == broker
    end

    test "the broker's status says how much it holds, never what" do
      name = bus_name("status")
      consumer = bus_name("consumer")
      bus_consume(consumer, [name])
      bus_stop(consumer)
      bus_publish([bus_message(name, %{"marker" => "held-payload-value"})])

      status = inspect(:sys.get_status(__MODULE__.Bus), limit: :infinity)

      assert status =~ "queued: 1"
      refute status =~ "held-payload-value"
    end

    test "a consumer that comes back taking fewer names gets only those" do
      [kept, dropped] = for tag <- ~w(kept dropped), do: bus_name(tag)
      consumer = bus_name("consumer")
      bus_consume(consumer, [kept, dropped])
      bus_stop(consumer)

      sent = bus_message(kept)
      bus_publish([sent, bus_message(dropped)])

      bus_consume(consumer, [kept])
      assert [^sent] = bus_received(consumer, 1)
      bus_nothing_more(consumer)
    end

    test "one consumer name on two brokers is two children of one supervisor" do
      other = [name: __MODULE__.Other]
      start_supervised!({Local, other})

      consumer = %{
        name: bus_name("consumer"),
        names: [bus_name("two")],
        handler: fn _ -> :ack end
      }

      start_supervised!(Local.consumer(@opts, consumer))
      start_supervised!(Local.consumer(other, consumer))
    end

    test "a broker's name is an atom" do
      assert_raise ArgumentError, ~r/:name must be an atom/, fn ->
        Local.child_spec(name: {:global, :bus})
      end
    end

    test "publishing to a broker that is not running is an error, not an exit" do
      assert {:error, :unavailable} =
               Local.publish([name: __MODULE__.Nowhere], [bus_message(bus_name("nowhere"))])
    end

    test "a consumer stops when the broker does" do
      consumer = %{
        name: bus_name("consumer"),
        names: [bus_name("gone")],
        handler: fn _ -> :ack end
      }

      # Temporary: restarted without a broker, it would fail in init until the test ends.
      spec = Supervisor.child_spec(Local.consumer(@opts, consumer), restart: :temporary)
      pid = start_supervised!(spec)
      ref = Process.monitor(pid)

      :ok = stop_supervised({Local, __MODULE__.Bus})

      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    end
  end

  describe "the configured adapter" do
    setup do
      previous = Application.get_env(:eh_os_contract, :bus)
      on_exit(fn -> restore(previous) end)
    end

    test "is a module or a module with options, and nil when none is configured" do
      Application.delete_env(:eh_os_contract, :bus)
      assert Bus.adapter() == nil

      Application.put_env(:eh_os_contract, :bus, Local)
      assert Bus.adapter() == {Local, []}

      Application.put_env(:eh_os_contract, :bus, {Local, @opts})
      assert Bus.adapter() == {Local, @opts}
    end

    test "publishing without one raises, naming the config" do
      Application.delete_env(:eh_os_contract, :bus)

      assert_raise ArgumentError, ~r/config :eh_os_contract, bus:/, fn ->
        Bus.publish([bus_message(bus_name("none"))])
      end
    end

    test "publishes through the adapter it names" do
      Application.put_env(:eh_os_contract, :bus, {Local, @opts})
      name = bus_name("configured")
      test = self()

      handler = fn message ->
        send(test, {:configured, message})
        :ack
      end

      spec = Bus.consumer(%{name: bus_name("consumer"), names: [name], handler: handler})
      start_supervised!(Supervisor.child_spec(spec, id: :configured))

      sent = bus_message(name)
      assert :ok = Bus.publish([sent])
      assert_receive {:configured, ^sent}
    end

    test "a value that is neither is refused, by its shape and never its value" do
      Application.put_env(:eh_os_contract, :bus, "Local")

      assert_raise ArgumentError,
                   ~r/must be a module or \{module, opts\}.*got a string/,
                   &Bus.adapter/0

      Application.put_env(:eh_os_contract, :bus, {Local, %{token: "nats-secret-token"}})
      error = assert_raise ArgumentError, &Bus.adapter/0
      assert error.message =~ "got {EhOsContract.Bus.Local, a map}"
      refute error.message =~ "nats-secret-token"
    end
  end

  defp restore(nil), do: Application.delete_env(:eh_os_contract, :bus)
  defp restore(value), do: Application.put_env(:eh_os_contract, :bus, value)
end
