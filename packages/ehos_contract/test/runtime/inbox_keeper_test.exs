defmodule EhosContract.InboxKeeperTest do
  @moduledoc """
  v2 plan, E12c: `EhosContract.Inbox.Keeper` keeps an inbox's consumer as a supervisor
  would — waits for it when stopped, starts it again at once when it stops after
  running — and takes every answer a start may give. The adapter here is a stand-in
  whose consumer reports to the test and takes a while to stop.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias EhosContract.{Implementations, Inbox}

  defmodule SlowConsumer do
    @moduledoc false
    use GenServer

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    @impl true
    def init(opts) do
      Process.flag(:trap_exit, true)
      send(Keyword.fetch!(opts, :to), {:started, self()})
      {:ok, opts}
    end

    # Takes a while to stop, as a consumer with a delivery in hand does. Its parent's
    # exit comes here: a gen_server that traps exits stops on it by itself.
    @impl true
    def terminate(_reason, opts) do
      Process.sleep(200)
      send(Keyword.fetch!(opts, :to), {:stopped, self()})
    end
  end

  defmodule StandInBus do
    @moduledoc false
    @behaviour EhosContract.Bus

    @impl true
    def publish(_opts, _messages), do: :ok

    # `:answer` is what the start returns: the consumer's own, `{:ok, pid, info}`
    # around it, or `:ignore`.
    @impl true
    def consumer(opts, consumer) do
      %{id: consumer.name, start: {__MODULE__, :start, [opts]}}
    end

    def start(opts) do
      case Keyword.get(opts, :answer, :ok) do
        :ok ->
          SlowConsumer.start_link(opts)

        :info ->
          {:ok, pid} = SlowConsumer.start_link(opts)
          {:ok, pid, :info}

        :ignore ->
          :ignore
      end
    end
  end

  @inbox "bus_rig_warehouse.stock:inbox:order_placed"

  setup do
    previous = Application.get_env(:ehos_contract, :bus)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:ehos_contract, :bus, previous),
        else: Application.delete_env(:ehos_contract, :bus)
    end)
  end

  defp keeper(answer \\ :ok) do
    Application.put_env(:ehos_contract, :bus, {StandInBus, to: self(), answer: answer})
    inbox = Enum.find(Implementations.inboxes(), &(&1.key == @inbox))
    start_supervised!({Inbox.Keeper, inbox})
  end

  test "stopped, it waits for its consumer to stop" do
    keeper()
    assert_receive {:started, child}

    assert :ok = stop_supervised({Inbox.Keeper, @inbox})
    assert_received {:stopped, ^child}
  end

  test "a consumer that stops after running is started again at once" do
    keeper = keeper()
    assert_receive {:started, child}

    # As if it had run longer than the pause.
    :sys.replace_state(keeper, &%{&1 | started_at: &1.started_at - 10_000})
    Process.exit(child, :kill)

    assert_receive {:started, again}, 1_000
    assert again != child
  end

  test "a consumer started with {:ok, pid, info} is its child" do
    keeper = keeper(:info)
    assert_receive {:started, child}

    assert %{child: ^child} = :sys.get_state(keeper)
  end

  test "a consumer that answers :ignore is left alone, and nothing is logged" do
    log =
      capture_log(fn ->
        keeper = keeper(:ignore)
        assert %{child: nil} = :sys.get_state(keeper)
      end)

    refute log =~ "did not start"
  end
end
