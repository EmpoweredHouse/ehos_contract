defmodule EhOsContract.WakeTest do
  @moduledoc """
  One wake per commit (#648). Where the log's trigger reaches the node, it wakes the
  runners at the commit, and the engine sends nothing of its own after a transaction it
  owns; elsewhere the engine notifies through Oban, as before. An append in a
  transaction the host's code owns is woken by the trigger alone.

  The trigger notifies the database it fires in, so this runs on
  `EhOsContract.CommitRepo`, whose rows commit, with an Oban of its own listening
  there as a node's Oban listens on its repo.
  """

  use ExUnit.Case, async: false

  alias EhOsContract.CommitRepo, as: Repo
  alias EhOsContract.Store
  alias EhOsContract.Subscription.{Runner, Wake}

  @oban __MODULE__.Oban

  setup do
    start_supervised!({Oban, name: @oban, repo: Repo, testing: :manual})
    :ok = Oban.Notifier.listen(@oban, [:eh_os_contract])

    test = self()
    id = "wake-#{System.unique_integer([:positive])}"

    # The engine's own wake goes through the suite's Oban, on another database: it is
    # seen here by its telemetry, from whichever process sends it.
    :ok =
      :telemetry.attach(
        id,
        [:oban, :notifier, :notify, :start],
        fn _event, _measurements, %{channel: channel}, _config ->
          if channel == :eh_os_contract, do: send(test, :engine_woke)
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(id) end)
    :ok
  end

  test "where the trigger reaches the node, an engine commit wakes once: the trigger's" do
    wake = start_supervised!({Wake, trigger: true})

    commit_in_engine_transaction!()
    _ = :sys.get_state(wake)

    assert_receive {:notification, :eh_os_contract, %{}}, 1_000
    refute_receive {:notification, :eh_os_contract, _payload}, 200
    refute_received :engine_woke
  end

  test "where it does not, the engine notifies after its commit, as before" do
    wake = start_supervised!({Wake, trigger: false})

    commit_in_engine_transaction!()
    _ = :sys.get_state(wake)

    assert_received :engine_woke
  end

  test "without the process, the caller notifies, as a node with subscriptions: :manual does" do
    commit_in_engine_transaction!()
    assert_received :engine_woke
  end

  test "an append in a transaction the host's code owns is woken at its commit by the trigger" do
    start_supervised!({Wake, trigger: true})

    {:ok, {:ok, [_event]}} = Repo.transaction(fn -> Store.append(Repo, [entry()], :none) end)

    assert_receive {:notification, :eh_os_contract, %{}}, 1_000
    refute_received :engine_woke
  end

  test "the trigger reaches the node only with Oban's Postgres notifier under the log's schema" do
    assert Wake.reaches?(Oban.Notifiers.Postgres, "public", "public")
    assert Wake.reaches?(Oban.Notifiers.Postgres, "ledger_production", "ledger_production")
    refute Wake.reaches?(Oban.Notifiers.Postgres, "oban", "public")
    refute Wake.reaches?(Oban.Notifiers.PG, "public", "public")
    refute Wake.reaches?(Oban.Notifiers.Postgres, false, "public")
  end

  # A transaction the engine owns, as dispatch's is: it marks its append, and
  # `Runner.transaction/2` wakes the runners once it commits.
  defp commit_in_engine_transaction! do
    {:ok, {:ok, [_event]}} =
      Runner.transaction(Repo, fn ->
        appended = Store.append(Repo, [entry()], :none)
        Runner.notify_on_commit()
        appended
      end)
  end

  defp entry do
    %{
      type: "dispatch_rig.ledger.deposited",
      contract: "dispatch_rig.ledger",
      contract_version: "wake",
      actor: "system:wake",
      correlation_id: Ecto.UUID.generate(),
      occurred_at: DateTime.utc_now(),
      payload: %{"account_id" => "wake-#{System.unique_integer([:positive])}", "amount" => 1}
    }
  end
end
