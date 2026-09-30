defmodule EhOsContract.Bus.Suite do
  @moduledoc """
  The tests every `EhOsContract.Bus` adapter has to pass, as a module to `use` in an
  ExUnit case:

      defmodule MyApp.BusTest do
        use ExUnit.Case, async: false

        use EhOsContract.Bus.Suite,
          bus: {MyApp.Bus, connection: :test},
          start: [{MyApp.Bus.Connection, name: :test}]
      end

  - `:bus` — the adapter and the options its callbacks get;
  - `:start` — the children the adapter needs running, started before each test
    (`EhOsContract.Bus.Local` itself, a connection to a broker); none by default;
  - `:wait` — how long a test waits for a delivery, in milliseconds, 5 000 by default.
    Redelivery after a `:nack` has to come within it, so give the adapter a short delay
    in the test.

  In `lib/` for the reason `EhOsContract.Store.Suite` is: the adapter that has to pass
  it is written in another repository.

  What it checks is what `EhOsContract.Bus` promises, and nothing it leaves open:
  every assertion about several messages compares them as a set, since no order is
  promised, and a message published twice is asserted to arrive, not to arrive once.
  Every test works under names of its own, so a transport that keeps messages between
  tests does not mix them up. Keep the case `async: false`.
  """

  @doc false
  defmacro __using__(opts) do
    bus = Keyword.fetch!(opts, :bus)
    start = Keyword.get(opts, :start, [])
    wait = Keyword.get(opts, :wait, 5_000)

    quote location: :keep do
      alias EhOsContract.Bus.Message

      @bus_suite_bus unquote(bus)
      @bus_suite_wait unquote(wait)

      setup do
        Enum.each(unquote(start), &start_supervised!/1)
        :ok
      end

      defp bus_name(tag), do: "bus-suite.#{tag}.#{System.unique_integer([:positive])}.v1"

      defp bus_message(name, payload \\ %{"n" => 1}) do
        %Message{
          id: "#{Ecto.UUID.generate()}/#{name}",
          name: name,
          correlation_id: Ecto.UUID.generate(),
          payload: payload
        }
      end

      defp bus_publish(messages) do
        {module, opts} = @bus_suite_bus
        assert :ok = module.publish(opts, messages)
      end

      # Starts a consumer whose handler reports each delivery to the test and answers
      # with `answer.(message)`.
      defp bus_consume(name, names, answer \\ fn _message -> :ack end) do
        {module, opts} = @bus_suite_bus
        test = self()

        handler = fn message ->
          send(test, {:bus_suite_delivered, name, message})
          answer.(message)
        end

        spec = module.consumer(opts, %{name: name, names: names, handler: handler})
        start_supervised!(Supervisor.child_spec(spec, id: {:bus_suite_consumer, name}))
      end

      defp bus_stop(name), do: :ok = stop_supervised({:bus_suite_consumer, name})

      defp bus_received(name, count) do
        for _ <- 1..count//1 do
          assert_receive {:bus_suite_delivered, ^name, message}, @bus_suite_wait
          message
        end
      end

      defp bus_nothing_more(name), do: refute_receive({:bus_suite_delivered, ^name, _}, 200)

      # Answers `:nack` (or does `fail`) the first time it sees a message, `:ack` after.
      defp bus_first_time(fail) do
        seen = :ets.new(:bus_suite_seen, [:public])

        fn message ->
          if :ets.insert_new(seen, {message.id}), do: fail.(), else: :ack
        end
      end

      describe "#{inspect(elem(@bus_suite_bus, 0))}: delivering" do
        test "a message published after the consumer subscribed arrives as it was sent" do
          name = bus_name("intact")
          consumer = bus_name("consumer")
          bus_consume(consumer, [name])

          payload = %{
            "visit_id" => Ecto.UUID.generate(),
            "amount" => "12.50",
            "count" => 3,
            "open" => false,
            "note" => nil,
            "lines" => [%{"code" => "A1"}, %{"code" => "é ą €"}]
          }

          sent = bus_message(name, payload)
          bus_publish([sent])

          assert [^sent] = bus_received(consumer, 1)
        end

        test "every message of a batch arrives" do
          name = bus_name("batch")
          consumer = bus_name("consumer")
          bus_consume(consumer, [name])

          sent = for n <- 1..3, do: bus_message(name, %{"n" => n})
          bus_publish(sent)

          assert MapSet.new(bus_received(consumer, 3)) == MapSet.new(sent)
        end

        test "an empty batch is accepted" do
          bus_publish([])
        end

        test "a consumer gets only the names it takes, each of them" do
          [taken, other, also] = for tag <- ~w(taken other also), do: bus_name(tag)
          consumer = bus_name("consumer")
          bus_consume(consumer, [taken, also])

          sent = [bus_message(taken), bus_message(also)]
          bus_publish([bus_message(other) | sent])

          assert MapSet.new(bus_received(consumer, 2)) == MapSet.new(sent)
          bus_nothing_more(consumer)
        end

        test "every consumer of a name gets the message" do
          name = bus_name("fan-out")
          [first, second] = for tag <- ~w(first second), do: bus_name(tag)
          bus_consume(first, [name])
          bus_consume(second, [name])

          sent = bus_message(name)
          bus_publish([sent])

          assert [^sent] = bus_received(first, 1)
          assert [^sent] = bus_received(second, 1)
        end

        test "a message published twice under one id arrives" do
          name = bus_name("twice")
          consumer = bus_name("consumer")
          bus_consume(consumer, [name])

          sent = bus_message(name)
          bus_publish([sent])
          bus_publish([sent])

          assert [^sent] = bus_received(consumer, 1)
        end
      end

      describe "#{inspect(elem(@bus_suite_bus, 0))}: delivering again" do
        test "a message the handler does not acknowledge comes again" do
          name = bus_name("nack")
          consumer = bus_name("consumer")
          bus_consume(consumer, [name], bus_first_time(fn -> :nack end))

          sent = bus_message(name)
          bus_publish([sent])

          assert [^sent, ^sent] = bus_received(consumer, 2)
        end

        test "a handler that raises gets the message again, and the consumer goes on" do
          name = bus_name("raise")
          consumer = bus_name("consumer")
          bus_consume(consumer, [name], bus_first_time(fn -> raise "handler defect" end))

          [first, second] = [bus_message(name, %{"n" => 1}), bus_message(name, %{"n" => 2})]
          bus_publish([first])
          assert [^first] = bus_received(consumer, 1)
          bus_publish([second])

          received = bus_received(consumer, 3)
          assert Enum.count(received, &(&1 == first)) == 1
          assert Enum.count(received, &(&1 == second)) == 2
        end

        test "a handler that exits or throws gets the message again" do
          for {tag, fail} <- [
                exit: fn -> exit(:handler_exit) end,
                throw: fn -> throw(:handler) end
              ] do
            name = bus_name(tag)
            consumer = bus_name("consumer")
            bus_consume(consumer, [name], bus_first_time(fail))

            sent = bus_message(name)
            bus_publish([sent])

            assert [^sent, ^sent] = bus_received(consumer, 2)
          end
        end

        test "a message a stopped consumer had in hand comes again when it is back" do
          name = bus_name("in-hand")
          consumer = bus_name("consumer")
          test = self()

          bus_consume(consumer, [name], fn _message ->
            send(test, :bus_suite_holding)
            Process.sleep(:infinity)
          end)

          sent = bus_message(name)
          bus_publish([sent])
          assert [^sent] = bus_received(consumer, 1)
          assert_receive :bus_suite_holding, @bus_suite_wait
          bus_stop(consumer)

          bus_consume(consumer, [name])
          assert [^sent] = bus_received(consumer, 1)
        end

        test "what is published while a consumer is down arrives when it is back" do
          name = bus_name("down")
          consumer = bus_name("consumer")
          bus_consume(consumer, [name])
          bus_stop(consumer)

          sent = bus_message(name)
          bus_publish([sent])
          bus_nothing_more(consumer)

          bus_consume(consumer, [name])
          assert [^sent] = bus_received(consumer, 1)
        end

        test "an acknowledged message does not come again when the consumer is back" do
          name = bus_name("acked")
          consumer = bus_name("consumer")
          bus_consume(consumer, [name])

          sent = bus_message(name)
          bus_publish([sent])
          assert [^sent] = bus_received(consumer, 1)
          bus_stop(consumer)

          bus_consume(consumer, [name])
          bus_nothing_more(consumer)
        end
      end
    end
  end
end
