defmodule EhOsContract.VaultTest do
  @moduledoc """
  v2 plan, E8a: **the master keys** (v2 §14, `EhOsContract.Vault`): the default
  vault's configuration, what the engine refuses at boot, and a master key's
  rotation by `mix eh_os_contract.rewrap`.

  `async: false`: tests change the vault's configuration, which is global.
  """

  use EhOsContract.DataCase, async: false

  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  alias EhOsContract.{Actor, Consumer, Event, Model, Personal, Vault}
  alias EhOsContract.Vault.Local
  alias ShreddingRig.Members
  alias ShreddingRig.Members.Commands.Join
  alias ShreddingRig.Members.Events.Joined

  defmodule RewrappedRepo do
    @moduledoc false
    # The test repo, on which another node changes the data keys right after the boot
    # check samples them: each sample runs the next of the test's `:after_sample`
    # functions.
    alias EhOsContract.TestRepo, as: Repo

    def query!(sql, params, opts) do
      sampled = Repo.query!(sql, params, opts)
      run_next(Process.get(:after_sample, []))
      sampled
    end

    def one(query), do: Repo.one(query)

    defp run_next([]), do: :ok

    defp run_next([next | rest]) do
      Process.put(:after_sample, rest)
      next.()
    end
  end

  @kek Base.encode64(:binary.copy(<<1>>, 32))
  @new_kek Base.encode64(:binary.copy(<<2>>, 32))

  setup do
    configured = Application.get_env(:eh_os_contract, Vault)
    on_exit(fn -> Application.put_env(:eh_os_contract, Vault, configured) end)
  end

  defp keys(keys), do: Application.put_env(:eh_os_contract, Vault, keys: keys)

  # What a node would leave whose vault names the bytes of the old key with `kek_id`: the
  # rows under a new id, wrapped as before.
  defp relabel!(kek_id),
    do: Repo.query!("UPDATE eh_os_contract_subject_keys SET kek_id = $1", [kek_id])

  describe "the default vault" do
    test "wraps with the first key, unwraps with any, and only in the same context" do
      keys([{"kek-new", @new_kek}, {"kek-old", @kek}])
      key = :crypto.strong_rand_bytes(32)

      assert {"kek-new", wrapped} = Local.wrap(key, "member|member-anna|1")
      assert Local.unwrap("kek-new", wrapped, "member|member-anna|1") == {:ok, key}
      assert Local.current() == "kek-new"

      # A wrapped key moved to another subject's row does not unwrap.
      assert Local.unwrap("kek-new", wrapped, "member|member-bartek|1") == :error
      # Nor under another master key's name.
      assert Local.unwrap("kek-old", wrapped, "member|member-anna|1") == :error
      assert Local.unwrap("kek-gone", wrapped, "member|member-anna|1") == :error
      assert Local.unwrap("kek-new", "short", "member|member-anna|1") == :error
    end

    test "says what is wrong with its configuration, naming no key" do
      keys([])
      assert {:error, message} = Local.check()
      assert message =~ "names no master key"

      keys([{"kek-1", Base.encode64("sixteen bytes!!!")}])
      assert Local.check() == {:error, ~s(master key "kek-1" is not 32 bytes in Base64)}

      keys([{"kek-1", "not base64"}])
      assert Local.check() == {:error, ~s(master key "kek-1" is not 32 bytes in Base64)}

      keys([{"", @kek}])

      assert {:error, "a master key is configured as {id, base64}, with a non-empty id"} =
               Local.check()

      keys([{"kek-1", @kek}, {"kek-1", @new_kek}])
      assert Local.check() == {:error, "two master keys share an id"}

      keys([{"kek-1", @kek}])
      assert Local.check() == :ok
    end
  end

  describe "at boot" do
    test "a contract with personal fields and no master key does not start" do
      keys([])

      assert_raise ArgumentError,
                   ~r/ShreddingRig.Members declare personal fields, and the vault cannot encrypt them: .*names no master key/,
                   fn -> Vault.check!([Model.fetch(Members)]) end

      assert {:error, {{%ArgumentError{}, _}, _}} = start_supervised(EhOsContract)
    end

    test "control: contracts without personal fields need no master key" do
      keys([])
      assert Vault.check!([Model.fetch(DispatchRig.Ledger)]) == :ok
    end

    test "a data key whose master key left the vault does not start, and says which key" do
      keys([{"kek-old", @kek}])
      join!("membership-anna", "member-anna")
      join!("membership-bartek", "member-bartek")
      keys([{"kek-new", @new_kek}])

      assert_raise ArgumentError,
                   ~s(2 data keys are wrapped by master key "kek-old". The vault cannot unwrap ) <>
                     ~s(the data key that the engine tried, so the engine cannot read the ) <>
                     ~s(personal data of its subject. ) <>
                     ~s(Put "kek-old" back in the vault, with the bytes that wrapped its data ) <>
                     ~s(keys. Then run ) <>
                     ~s(`mix eh_os_contract.rewrap --expect "kek-new"` before you remove it),
                   fn -> Personal.check_master_keys!(Repo, [Model.fetch(Members)]) end

      assert {:error, {{%ArgumentError{message: message}, _}, _}} =
               start_supervised(EhOsContract)

      assert message =~ ~s(2 data keys are wrapped by master key "kek-old")
    end

    test "a master key whose id stays and whose bytes changed does not start" do
      keys([{"kek-1", @kek}])
      join!("membership-anna", "member-anna")
      keys([{"kek-1", @new_kek}])

      assert_raise ArgumentError,
                   ~s(1 data key is wrapped by master key "kek-1". The vault cannot unwrap ) <>
                     ~s(the data key that the engine tried, so the engine cannot read the ) <>
                     ~s(personal data of its subject. The vault wraps with "kek-1". Check that ) <>
                     ~s(its bytes are the bytes that wrapped that data key),
                   fn -> Personal.check_master_keys!(Repo, [Model.fetch(Members)]) end
    end

    test "a master key after one that unwraps is checked too" do
      keys([{"kek-old", @kek}])
      join!("membership-anna", "member-anna")
      keys([{"kek-new", @new_kek}, {"kek-old", @kek}])
      join!("membership-celina", "member-celina")
      keys([{"kek-new", @new_kek}])

      assert_raise ArgumentError, ~r/^1 data key is wrapped by master key "kek-old"/, fn ->
        Personal.check_master_keys!(Repo, [Model.fetch(Members)])
      end
    end

    test "data keys that a rewrap moved after the sample are checked under their new key" do
      keys([{"kek-old", @kek}])
      join!("membership-anna", "member-anna")
      keys([{"kek-new", @new_kek}])

      Process.put(:after_sample, [
        fn ->
          keys([{"kek-new", @new_kek}, {"kek-old", @kek}])
          Personal.rewrap!(Repo, "kek-new")
          keys([{"kek-new", @new_kek}])
        end
      ])

      assert Personal.check_master_keys!(RewrappedRepo, [Model.fetch(Members)]) == :ok
    end

    test "data keys moved after the sample to a key the vault cannot unwrap with do not start" do
      keys([{"kek-old", @kek}])
      join!("membership-anna", "member-anna")
      keys([{"kek-new", @new_kek}])
      Process.put(:after_sample, [fn -> relabel!("kek-new") end])

      assert_raise ArgumentError, ~r/^1 data key is wrapped by master key "kek-new"/, fn ->
        Personal.check_master_keys!(RewrappedRepo, [Model.fetch(Members)])
      end
    end

    test "data keys that move after each sample do not start, and say why" do
      keys([{"kek-old", @kek}])
      join!("membership-anna", "member-anna")
      keys([{"kek-new", @new_kek}])
      Process.put(:after_sample, Enum.map(["kek-a", "kek-b", "kek-c"], &fn -> relabel!(&1) end))

      assert_raise ArgumentError,
                   "The data keys moved to another master key while the engine checked them, " <>
                     "3 times. A rewrap is likely running on another node. Start the engine " <>
                     "again when the rewrap ends",
                   fn -> Personal.check_master_keys!(RewrappedRepo, [Model.fetch(Members)]) end
    end

    test "control: a vault that unwraps a data key of each master key starts" do
      keys([{"kek-old", @kek}])
      join!("membership-anna", "member-anna")
      keys([{"kek-new", @new_kek}, {"kek-old", @kek}])
      join!("membership-celina", "member-celina")

      assert Personal.check_master_keys!(Repo, [Model.fetch(Members)]) == :ok
    end

    test "control: contracts without personal fields do not read the data keys" do
      keys([{"kek-old", @kek}])
      join!("membership-anna", "member-anna")
      keys([])

      assert Personal.check_master_keys!(Repo, [Model.fetch(DispatchRig.Ledger)]) == :ok
    end

    test "a vault that is no EhOsContract.Vault is refused" do
      Application.put_env(:eh_os_contract, :vault, String)
      on_exit(fn -> Application.delete_env(:eh_os_contract, :vault) end)

      assert_raise ArgumentError, ~r/String does not implement EhOsContract.Vault/, fn ->
        Vault.check!([Model.fetch(Members)])
      end
    end
  end

  describe "the append lock" do
    # A vault that tells the test, on every call, whether the connection holds the
    # append lock at that moment.
    defmodule LockSpy do
      @moduledoc false
      @behaviour EhOsContract.Vault

      @impl true
      def wrap(key, context), do: spy(:wrap, fn -> Local.wrap(key, context) end)

      @impl true
      def unwrap(id, wrapped, context),
        do: spy(:unwrap, fn -> Local.unwrap(id, wrapped, context) end)

      @impl true
      def current, do: Local.current()

      @impl true
      def check, do: Local.check()

      defp spy(call, fun) do
        %{rows: [[held]]} =
          EhOsContract.TestRepo.query!(
            "SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND granted " <>
              "AND pid = pg_backend_pid()"
          )

        send(self(), {:vault, call, held > 0})
        fun.()
      end
    end

    test "no vault call waits under it: keys are read and wrapped before it is taken" do
      keys([{"kek-1", @kek}])
      Application.put_env(:eh_os_contract, :vault, LockSpy)
      on_exit(fn -> Application.delete_env(:eh_os_contract, :vault) end)

      # Anna's key exists already, written the way dispatch writes it, without the lock
      # that a dispatch in this sandboxed test would hold until the test ends.
      key = :crypto.strong_rand_bytes(32)
      {kek_id, wrapped} = Local.wrap(key, "eh_os_contract.subject_key|member|member-anna|1")

      Repo.insert_all("eh_os_contract_subject_keys", [
        %{
          subject_type: "member",
          subject_id: "member-anna",
          key_version: 1,
          kek_id: kek_id,
          wrapped_key: wrapped
        }
      ])

      {:ok, _} =
        EhOsContract.dispatch(
          Members,
          %Join{
            membership_id: "membership-anna",
            member_id: "member-anna",
            name: "Anna Nowak",
            contacts: [
              %ShreddingRig.Domain.Values.Contact{
                member_id: "member-bartek",
                phone: "+48 600 300 400"
              }
            ],
            plan: :basic
          },
          actor: Actor.credential("u-clerk", ["shredding_rig.join"])
        )

      calls = collect_vault([])
      assert {:unwrap, false} in calls
      assert {:wrap, false} in calls
      refute Enum.any?(calls, fn {_call, held} -> held end)
    end
  end

  defp collect_vault(calls) do
    receive do
      {:vault, call, held} -> collect_vault([{call, held} | calls])
    after
      0 -> Enum.reverse(calls)
    end
  end

  describe "rotating the master key" do
    defp join!(membership, member) do
      {:ok, _} =
        EhOsContract.dispatch(
          Members,
          %Join{
            membership_id: membership,
            member_id: member,
            name: "Anna Nowak",
            contacts: [],
            plan: :basic
          },
          actor: Actor.credential("u-clerk", ["shredding_rig.join"])
        )
    end

    defp kek_ids do
      Repo.all(from(k in "eh_os_contract_subject_keys", order_by: k.subject_id, select: k.kek_id))
    end

    defp names,
      do: Repo.all(from(e in Event, order_by: e.position)) |> Enum.map(&Consumer.decode!/1)

    test "rewraps every key the old one wraps, and the log reads the same with the old key gone" do
      keys([{"kek-old", @kek}])
      join!("membership-anna", "member-anna")
      join!("membership-bartek", "member-bartek")
      assert kek_ids() == ["kek-old", "kek-old"]

      # The new key first, the old one kept to unwrap.
      keys([{"kek-new", @new_kek}, {"kek-old", @kek}])
      join!("membership-celina", "member-celina")
      assert kek_ids() == ["kek-old", "kek-old", "kek-new"]

      assert Personal.rewrap!(Repo, "kek-new", 1) == 2
      assert kek_ids() == ["kek-new", "kek-new", "kek-new"]
      assert Personal.rewrap!(Repo, "kek-new") == 0

      keys([{"kek-new", @new_kek}])
      assert [%Joined{name: "Anna Nowak"}, %Joined{name: "Anna Nowak"}, %Joined{}] = names()
    end

    test "a rewrap whose vault wraps with another key than the expected one rewraps nothing" do
      keys([{"kek-old", @kek}])
      join!("membership-anna", "member-anna")
      keys([{"kek-new", @new_kek}, {"kek-old", @kek}])
      join!("membership-celina", "member-celina")

      # The configuration of before the rotation: the old key still first.
      keys([{"kek-old", @kek}, {"kek-new", @new_kek}])

      assert_raise ArgumentError,
                   ~r/the vault wraps with "kek-old", not with "kek-new" that was expected.*check that "kek-new" is the id of the new key$/,
                   fn -> Personal.rewrap!(Repo, "kek-new") end

      assert kek_ids() == ["kek-old", "kek-new"]
    end

    test "a rewrap called with a batch size where the key id goes does not run" do
      keys([{"kek-new", @new_kek}])

      assert_raise FunctionClauseError, fn -> Personal.rewrap!(Repo, 50) end
    end

    test "a key whose master key left the vault before the rewrap does not read, and says so" do
      keys([{"kek-old", @kek}])
      join!("membership-anna", "member-anna")

      keys([{"kek-new", @new_kek}])

      assert_raise ArgumentError, ~r/cannot be unwrapped with master key "kek-old"/, fn ->
        names()
      end
    end

    test "a stream whose key does not unwrap fails the command in evolve" do
      keys([{"kek-old", @kek}])
      join!("membership-anna", "member-anna")
      keys([{"kek-new", @new_kek}])

      assert_raise ArgumentError, ~r/cannot be unwrapped/, fn ->
        EhOsContract.dispatch(
          Members,
          %ShreddingRig.Members.Commands.Rename{
            membership_id: "membership-anna",
            member_id: "member-anna",
            name: "Anna Kowalska"
          },
          actor: Actor.credential("u-clerk", ["shredding_rig.rename"])
        )
      end

      assert %{outcome: "failed", failed_in: "evolve"} =
               Repo.one(from(c in EhOsContract.CommandRecord, where: c.type == "rename"))
    end

    test "no wrapped key reaches a log, when a key is made or rewrapped" do
      level = Logger.level()
      Logger.configure(level: :debug)
      on_exit(fn -> Logger.configure(level: level) end)

      keys([{"kek-old", @kek}])

      log =
        capture_log(fn ->
          join!("membership-anna", "member-anna")
          keys([{"kek-new", @new_kek}, {"kek-old", @kek}])
          assert Personal.rewrap!(Repo, "kek-new") == 1
        end)

      # Control: the queries around them are logged.
      assert log =~ "eh_os_contract_events"
      refute log =~ ~s(INSERT INTO "eh_os_contract_subject_keys")
      refute log =~ ~s(UPDATE "eh_os_contract_subject_keys")
    end

    test "the task reports how many keys it rewrapped" do
      keys([{"kek-old", @kek}])
      join!("membership-anna", "member-anna")
      keys([{"kek-new", @new_kek}, {"kek-old", @kek}])

      output =
        capture_io(fn -> Mix.Tasks.EhOsContract.Rewrap.run(["--expect", "kek-new"]) end)

      assert output =~ "1 data keys rewrapped with kek-new"
    end

    test "the task refuses to run without the expected key" do
      assert_raise Mix.Error, ~r/--expect/, fn -> Mix.Tasks.EhOsContract.Rewrap.run([]) end
    end

    test "the task refuses a vault that wraps with another key, and rewraps nothing" do
      keys([{"kek-old", @kek}])
      join!("membership-anna", "member-anna")

      assert_raise ArgumentError, ~r/not with "kek-new" that was expected/, fn ->
        Mix.Tasks.EhOsContract.Rewrap.run(["--expect", "kek-new"])
      end

      assert kek_ids() == ["kek-old"]
    end
  end
end
