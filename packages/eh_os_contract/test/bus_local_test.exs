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

    test "a consumer stops when the broker does" do
      consumer = bus_name("consumer")
      pid = bus_consume(consumer, [bus_name("gone")])
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

    test "a value that is neither is refused" do
      Application.put_env(:eh_os_contract, :bus, "Local")
      assert_raise ArgumentError, ~r/is not a module or \{module, opts\}/, &Bus.adapter/0
    end
  end

  defp restore(nil), do: Application.delete_env(:eh_os_contract, :bus)
  defp restore(value), do: Application.put_env(:eh_os_contract, :bus, value)
end
