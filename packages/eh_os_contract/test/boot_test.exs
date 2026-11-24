defmodule EhOsContract.BootTest do
  @moduledoc """
  `EhOsContract` as a child of the host's supervision tree (plan E7a: the child
  becomes a supervisor). It scans the registry and records the deployment, so a host
  cannot remember one and forget the other; unless subscriptions are `:manual`, it
  registers every subscription and starts a runner for each.
  """

  use EhOsContract.DataCase, async: false

  alias DispatchRig.Ledger
  alias DispatchRig.Ledger.Commands.{Deposit, OpenAccount}
  alias EhOsContract.{Actor, Implementations, Model, SubscriptionRecord}

  @clerk Actor.credential("u-1", ["dispatch_rig.open_account", "dispatch_rig.deposit"])

  # The runners have a supervisor of their own, beside the inbox keepers.
  defp runners(supervisor) do
    for {EhOsContract.Subscription.Runners, runners, :supervisor, _} <-
          Supervisor.which_children(supervisor),
        {{EhOsContract.Subscription.Runner, key}, _pid, :worker, _} <-
          Supervisor.which_children(runners),
        do: key
  end

  test "the child is a supervisor" do
    assert %{id: EhOsContract, start: {EhOsContract, :start_link, [[]]}, type: :supervisor} =
             Supervisor.child_spec(EhOsContract, [])
  end

  test "booting loads the registry and records the deployment; :manual starts no runner" do
    assert EhOsContract.TestRepo.all(EhOsContract.Deployment) == []

    supervisor = start_supervised!(EhOsContract)

    refute EhOsContract.Registry.contracts() == []
    refute EhOsContract.TestRepo.all(EhOsContract.Deployment) == []
    assert runners(supervisor) == []
    assert Repo.all(SubscriptionRecord) == []
  end

  test "a misspelled key of the configuration stops the boot, naming the key" do
    Application.put_env(:eh_os_contract, :autorizer, EhOsContract.Authorizer.Default)
    on_exit(fn -> Application.delete_env(:eh_os_contract, :autorizer) end)

    assert {:error, {{%ArgumentError{message: message}, _}, _}} = start_supervised(EhOsContract)
    assert message =~ ":autorizer"
  end

  # Plan DD, T2a (#240). DDL is transactional, so the sandbox rolls the version back.
  test "storage at an older version than the release needs stops the boot, saying what to run" do
    Repo.query!("COMMENT ON TABLE eh_os_contract_events IS '1'")

    assert {:error, {{%ArgumentError{message: message}, _}, _}} = start_supervised(EhOsContract)

    assert message =~
             "storage is at version 1, and this release needs version 6: add a migration " <>
               "calling EhOsContract.Migrations.up(version: 6)"

    assert EhOsContract.TestRepo.all(EhOsContract.Deployment) == [],
           "refused before anything is recorded"
  end

  test "storage missing stops the boot too, saying to migrate" do
    Repo.query!("COMMENT ON TABLE eh_os_contract_events IS NULL")
    assert {:error, {{%ArgumentError{message: none}, _}, _}} = start_supervised(EhOsContract)
    assert none =~ "has no eh_os_contract storage in its current schema"
  end

  # Plan DD, P2h (#221): V03 removes columns this release no longer writes, and a newer
  # version may remove one it does, so a node of an older release stops rather than
  # failing on every append. A deploy stops the old nodes before it migrates.
  test "storage a newer release migrated stops the boot, saying it is newer" do
    Repo.query!("COMMENT ON TABLE eh_os_contract_events IS '7'")

    assert {:error, {{%ArgumentError{message: message}, _}, _}} = start_supervised(EhOsContract)

    assert message =~
             "storage is at version 7, newer than version 6, which this release of " <>
               "eh_os_contract knows"

    assert EhOsContract.TestRepo.all(EhOsContract.Deployment) == [],
           "refused before anything is recorded"
  end

  # Before 0.3.0 the versions ran to 5 with another meaning; a database that kept one
  # still has the column V03 removes, so it is not taken for this release's version 3.
  test "storage migrated before 0.3.0 stops the boot, saying it cannot be upgraded" do
    Repo.query!("ALTER TABLE eh_os_contract_events ADD COLUMN instance_id text")

    assert {:error, {{%ArgumentError{message: message}, _}, _}} = start_supervised(EhOsContract)
    assert message =~ "records version 6, and it was migrated before 0.3.0"
  end

  test "control: storage at the release's version lets the boot through" do
    Repo.query!("COMMENT ON TABLE eh_os_contract_events IS '6'")
    assert start_supervised!(EhOsContract)
  end

  defmodule UnreachableRepo do
    @moduledoc false
    def query!(_sql, _params, _opts),
      do: raise(DBConnection.ConnectionError, "too many connections")
  end

  test "a database the boot cannot ask fails as itself, never as storage to migrate" do
    assert_raise DBConnection.ConnectionError, "too many connections", fn ->
      EhOsContract.Migrations.check!(UnreachableRepo)
    end
  end

  defmodule Unforgetting do
    @moduledoc false
  end

  test "a read model that projects personal data and defines no forget/2 stops the boot" do
    # The index the boot reads, with one read model's module swapped for one without
    # forget/2 — as a host that forgot to write it would have it.
    apps = Enum.uniq(List.wrap(Application.get_env(:eh_os_contract, :applications)))
    key = {Implementations, apps}
    index = Implementations.index(nil)
    on_exit(fn -> :persistent_term.put(key, index) end)

    consumers =
      Enum.map(index.consumers, fn
        %{key: "shredding_rig.members:read_model:members"} = consumer ->
          %{consumer | module: Unforgetting}

        consumer ->
          consumer
      end)

    :persistent_term.put(key, %{index | consumers: consumers})
    # The key this test rebuilt is the one the boot reads; otherwise it tests nothing.
    assert Implementations.index(nil).consumers == consumers

    assert {:error, {{%ArgumentError{message: message}, _}, _}} = start_supervised(EhOsContract)
    assert message =~ "read model :members of ShreddingRig.Members project personal data"
  end

  # #671: the effects delivered :at_least_once and the timers wait in the queue
  # :events. The suite's Oban runs no queue (`testing: :manual`); these tests put in its
  # place one that runs what a host configured, and the suite's back after.
  describe "Oban's queues" do
    import ExUnit.CaptureLog

    defp with_oban(overrides, fun) do
      conf = Application.fetch_env!(:eh_os_contract, Oban)
      :ok = Supervisor.stop(Oban.whereis(Oban))

      on_exit(fn ->
        {:ok, pid} = Oban.start_link(conf)
        Process.unlink(pid)
      end)

      start_supervised!(
        {Oban,
         Keyword.merge(conf, [testing: :disabled, plugins: false, peer: false] ++ overrides)}
      )

      fun.()
    end

    test "a host whose Oban runs no :events is warned once, with the queue to add" do
      assert Implementations.index(nil).effects != %{},
             "the suite declares an effect delivered :at_least_once, or this tests nothing"

      log =
        with_oban([queues: [default: 10]], fn ->
          capture_log(fn -> start_supervised!(EhOsContract) end)
        end)

      assert log =~
               "Oban runs no queue :events (its queues: [:default]), so the jobs of " <>
                 "EhOsContract.EffectJob and EhOsContract.TimerJob wait in its table until a " <>
                 "node runs the queue: add it where the host configures Oban, queues: [events: 10]"

      assert [_, _] = String.split(log, "Oban runs no queue :events"), "warned once"
    end

    # `exclude:` narrows the registry's scan, not what dispatch enqueues: a contract it
    # leaves out still has its effects and timers run as jobs.
    test "a contract left out by exclude: still counts" do
      waiting =
        for contract <- EhOsContract.Registry.contracts(),
            model = Model.fetch(contract),
            Enum.any?(model.effects, &(&1.delivery == :at_least_once)) or
              Enum.any?(model.process_managers, &(&1.timers != [])),
            do: contract |> Module.split() |> hd()

      Application.put_env(:eh_os_contract, :exclude, Enum.uniq(waiting))

      on_exit(fn ->
        Application.delete_env(:eh_os_contract, :exclude)
        EhOsContract.Registry.load!()
      end)

      log =
        with_oban([queues: [default: 10]], fn ->
          capture_log(fn -> start_supervised!(EhOsContract) end)
        end)

      assert log =~ "the jobs of EhOsContract.EffectJob and EhOsContract.TimerJob wait"
      # The exclusion took effect: no contract whose jobs wait is left in the scan.
      refute waiting == []
      scanned = Enum.map(EhOsContract.Registry.contracts(), &hd(Module.split(&1)))
      assert MapSet.disjoint?(MapSet.new(waiting), MapSet.new(scanned))
    end

    test "control: a host whose Oban runs :events is not warned" do
      # Paused, so the queue is configured and runs no job of the shared database.
      log =
        with_oban([queues: [default: 10, events: [limit: 1, paused: true]]], fn ->
          capture_log(fn -> start_supervised!(EhOsContract) end)
        end)

      refute log =~ ":events"
    end

    test "under Oban's testing modes, which run no queue by design, nothing is said" do
      # The suite's own Oban: `testing: :manual`, and its queues therefore none.
      assert Oban.config(Oban).queues == []
      refute capture_log(fn -> start_supervised!(EhOsContract) end) =~ ":events"
    end
  end

  describe "without :manual" do
    setup do
      Application.put_env(:eh_os_contract, :subscriptions, :run)
      on_exit(fn -> Application.put_env(:eh_os_contract, :subscriptions, :manual) end)
    end

    # The runners are stopped with the test, possibly in the middle of a query, and the
    # pool logs the connection they held.
    @tag :capture_log
    test "registers every subscription, starts a runner for each, and they catch up" do
      {:ok, _} =
        EhOsContract.dispatch(Ledger, %OpenAccount{account_id: "a-1", branch_id: "b-7"},
          actor: @clerk
        )

      {:ok, _} =
        EhOsContract.dispatch(Ledger, %Deposit{account_id: "a-1", amount: 10}, actor: @clerk)

      supervisor = start_supervised!(EhOsContract)

      keys = Enum.map(Implementations.subscribed(), & &1.key)
      assert Enum.sort(runners(supervisor)) == Enum.sort(keys)
      assert Enum.sort(Enum.map(Repo.all(SubscriptionRecord), & &1.name)) == Enum.sort(keys)

      # The ordered read model is fed by its runner, which polls: the sandbox never
      # commits, so no notification reaches it.
      assert eventually(fn ->
               Repo.all(from(l in "dispatch_rig_lines", select: l.amount)) == [10]
             end)
    end

    test "subscription_poll: reaches the node's poll, and anything else is refused" do
      supervisor = start_supervised!({EhOsContract, subscription_poll: 5_000})

      [head] =
        for {EhOsContract.Subscription.Head, pid, :worker, _} <-
              Supervisor.which_children(supervisor),
            do: pid

      assert :sys.get_state(head).poll == 5_000
      stop_supervised!(EhOsContract)

      assert {:error, {{%ArgumentError{message: zero}, _}, _}} =
               start_supervised({EhOsContract, subscription_poll: 0})

      assert zero =~ "subscription_poll: is a number of milliseconds from 1 to 4294967295, got: 0"

      assert {:error, {{%ArgumentError{message: too_long}, _}, _}} =
               start_supervised({EhOsContract, subscription_poll: 4_294_967_296})

      assert too_long =~ "got: 4294967296"

      assert {:error, {{%ArgumentError{message: unknown}, _}, _}} =
               start_supervised({EhOsContract, poll: 5_000})

      assert unknown =~ ":poll"
    end

    # #648: the suite's Oban runs its Postgres notifier under `public`, the schema of
    # the log, so the trigger wakes the runners and the engine sends no wake of its own.
    test "the boot finds that the log's trigger reaches the node" do
      start_supervised!(EhOsContract)
      assert is_pid(Process.whereis(EhOsContract.Subscription.Wake.name()))
    end

    test "a host with no subscription starts no runner and no poll" do
      apps = Enum.uniq(List.wrap(Application.get_env(:eh_os_contract, :applications)))
      key = {Implementations, apps}
      index = Implementations.index(nil)
      on_exit(fn -> :persistent_term.put(key, index) end)
      :persistent_term.put(key, %{index | subscribed: []})

      supervisor = start_supervised!(EhOsContract)

      assert for({id, _, _, _} <- Supervisor.which_children(supervisor), do: id) == []
      assert Process.whereis(EhOsContract.Subscription.Runners) == nil
      assert Process.whereis(EhOsContract.Subscription.Wake.name()) == nil
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
