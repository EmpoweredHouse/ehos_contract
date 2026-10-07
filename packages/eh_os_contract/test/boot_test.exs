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
  alias EhOsContract.{Actor, Implementations, SubscriptionRecord}

  @clerk Actor.credential("u-1", ["dispatch_rig.open_account", "dispatch_rig.deposit"])

  defp runners(supervisor) do
    for {{EhOsContract.Subscription.Runner, key}, _pid, :worker, _} <-
          Supervisor.which_children(supervisor),
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
             "storage is at version 1, and this release needs version 2: add a migration " <>
               "calling EhOsContract.Migrations.up(version: 2)"

    assert EhOsContract.TestRepo.all(EhOsContract.Deployment) == [],
           "refused before anything is recorded"
  end

  test "storage missing stops the boot too, saying to migrate" do
    Repo.query!("COMMENT ON TABLE eh_os_contract_events IS NULL")
    assert {:error, {{%ArgumentError{message: none}, _}, _}} = start_supervised(EhOsContract)
    assert none =~ "has no eh_os_contract storage in its current schema"
  end

  # A node of this release restarting while a newer one rolls out, or code rolled back
  # without its migration.
  test "control: storage a newer release migrated lets the boot through" do
    Repo.query!("COMMENT ON TABLE eh_os_contract_events IS '3'")
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
  end

  defp eventually(check, tries \\ 30) do
    cond do
      check.() -> true
      tries == 0 -> false
      true -> Process.sleep(100) && eventually(check, tries - 1)
    end
  end
end
