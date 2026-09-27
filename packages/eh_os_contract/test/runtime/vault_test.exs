defmodule EhOsContract.VaultTest do
  @moduledoc """
  v2 plan, E8a: **the master keys** (v2 §14, `EhOsContract.Vault`): the default
  vault's configuration, what the engine refuses at boot, and a master key's
  rotation by `mix eh_os_contract.rewrap`.

  `async: false`: tests change the vault's configuration, which is global.
  """

  use EhOsContract.DataCase, async: false

  import ExUnit.CaptureIO

  alias EhOsContract.{Actor, Consumer, Event, Model, Personal, Vault}
  alias EhOsContract.Vault.Local
  alias ShreddingRig.Members
  alias ShreddingRig.Members.Commands.Join
  alias ShreddingRig.Members.Events.Joined

  @kek Base.encode64(:binary.copy(<<1>>, 32))
  @new_kek Base.encode64(:binary.copy(<<2>>, 32))

  setup do
    configured = Application.get_env(:eh_os_contract, Vault)
    on_exit(fn -> Application.put_env(:eh_os_contract, Vault, configured) end)
  end

  defp keys(keys), do: Application.put_env(:eh_os_contract, Vault, keys: keys)

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

    test "a vault that is no EhOsContract.Vault is refused" do
      Application.put_env(:eh_os_contract, :vault, String)
      on_exit(fn -> Application.delete_env(:eh_os_contract, :vault) end)

      assert_raise ArgumentError, ~r/String does not implement EhOsContract.Vault/, fn ->
        Vault.check!([Model.fetch(Members)])
      end
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

      assert Personal.rewrap!(Repo, 1) == 2
      assert kek_ids() == ["kek-new", "kek-new", "kek-new"]
      assert Personal.rewrap!(Repo) == 0

      keys([{"kek-new", @new_kek}])
      assert [%Joined{name: "Anna Nowak"}, %Joined{name: "Anna Nowak"}, %Joined{}] = names()
    end

    test "a key whose master key left the vault before the rewrap does not read, and says so" do
      keys([{"kek-old", @kek}])
      join!("membership-anna", "member-anna")

      keys([{"kek-new", @new_kek}])

      assert_raise ArgumentError, ~r/cannot be unwrapped with master key "kek-old"/, fn ->
        names()
      end
    end

    test "the task reports how many keys it rewrapped" do
      keys([{"kek-old", @kek}])
      join!("membership-anna", "member-anna")
      keys([{"kek-new", @new_kek}, {"kek-old", @kek}])

      output = capture_io(fn -> Mix.Tasks.EhOsContract.Rewrap.run([]) end)
      assert output =~ "1 data keys rewrapped with kek-new"
    end
  end
end
