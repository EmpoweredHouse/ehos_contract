defmodule EhosContract.ErasureTest do
  @moduledoc """
  v2 plan, E8b: **erasing a subject** (v2 §14), on the invented
  `ShreddingRig.Members`: what `EhosContract.erase/3` deletes, records and appends,
  the read models that forget — in the dispatch transaction and after it, and on a
  rebuild — dispatch refusing an erased subject's data, and conformance, which
  erasure leaves as it was.

  `async: false`: erasure and dispatch take the one append lock, and a sandboxed
  test holds it until the test ends.
  """

  use EhosContract.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias EhosContract.{Actor, CommandRecord, Consumer, Erased, Event, Implementations, Personal}
  alias EhosContract.{Subscription, Testing}
  alias ShreddingRig.Members
  alias ShreddingRig.Members.Commands.{Join, Rename}
  alias ShreddingRig.Members.Events.Joined

  @clerk Actor.credential("u-clerk", ["shredding_rig.join", "shredding_rig.rename"])
  @officer Actor.credential("u-officer", [])
  @names "shredding_rig.members:read_model:member_names"

  defp join_member(membership, member, name) do
    EhosContract.dispatch(
      Members,
      %Join{
        membership_id: membership,
        member_id: member,
        name: name,
        contacts: [
          %ShreddingRig.Domain.Values.Contact{member_id: member, phone: "+48 600 100 200"}
        ],
        plan: :basic
      },
      actor: @clerk
    )
  end

  defp rename_member(membership, member, name) do
    EhosContract.dispatch(
      Members,
      %Rename{membership_id: membership, member_id: member, name: name},
      actor: @clerk
    )
  end

  # Anna and Bartek, each with a membership; Anna renamed once.
  defp two_members! do
    {:ok, _} = join_member("membership-anna", "member-anna", "Anna Nowak")
    {:ok, _} = rename_member("membership-anna", "member-anna", "Anna Kowalska")
    {:ok, _} = join_member("membership-bartek", "member-bartek", "Bartek Nowak")
    :ok
  end

  defp log, do: Repo.all(from(e in Event, order_by: e.position))

  defp keys,
    do:
      Repo.all(
        from(k in "ehos_contract_subject_keys", order_by: k.subject_id, select: k.subject_id)
      )

  defp erasures do
    Repo.all(
      from(e in "ehos_contract_erasures",
        select: {e.subject_type, e.subject_id, e.requested_by}
      )
    )
  end

  defp members do
    Repo.all(
      from(m in "shredding_rig_members", order_by: m.membership_id, select: {m.member_id, m.name})
    )
  end

  defp names do
    Repo.all(
      from(m in "shredding_rig_member_names",
        order_by: m.membership_id,
        select: {m.member_id, m.name}
      )
    )
  end

  # The members read model, failing on Anna's rename while it was rebuilt: its key, and
  # the position it stopped at.
  defp fail_members! do
    Subscription.register!(Repo, Implementations.subscribed())
    key = "shredding_rig.members:read_model:members"
    [joined, renamed | _] = log()

    {1, _} =
      Repo.update_all(from(s in EhosContract.SubscriptionRecord, where: s.name == ^key),
        set: [
          status: "failing",
          position: joined.position,
          failed_position: renamed.position,
          resume_status: "rebuilding"
        ]
      )

    {key, joined.position}
  end

  describe "erase/3" do
    test "deletes the keys, records the erasure, appends the event, and the read model forgets" do
      two_members!()
      assert keys() == ["member-anna", "member-bartek"]

      assert EhosContract.erase(:member, "member-anna", actor: @officer) == {:ok, :erased}

      assert keys() == ["member-bartek"]
      assert erasures() == [{"member", "member-anna", "actor:u-officer"}]

      erased = List.last(log())
      assert erased.type == "ehos_contract.subject_erased"
      assert erased.payload == %{"subject_type" => "member", "subject_id" => "member-anna"}
      assert erased.actor == "actor:u-officer"
      assert erased.contract == "ehos_contract"
      assert erased.stream_id == nil

      # One moment: the erasure's record and its event say the same time.
      assert Repo.one(
               from(e in "ehos_contract_erasures", select: type(e.erased_at, :utc_datetime_usec))
             ) ==
               erased.occurred_at

      # The read model delivered in the transaction forgot Anna, and only Anna.
      assert members() == [{"member-anna", nil}, {"member-bartek", "Bartek Nowak"}]

      anna = %Erased{subject: :member, id: "member-anna"}

      assert [
               %Joined{name: ^anna, contacts: [%{phone: ^anna}], plan: :basic},
               %{name: ^anna, previous: ^anna},
               %Joined{name: "Bartek Nowak"},
               ^anna
             ] = Enum.map(log(), &Consumer.decode!/1)
    end

    test "a read model projected in the transaction that failed while it was rebuilt forgets at once" do
      two_members!()
      {key, position} = fail_members!()

      {:ok, :erased} = EhosContract.erase(:member, "member-anna", actor: @officer)

      assert members() == [{"member-anna", nil}, {"member-bartek", "Bartek Nowak"}]

      assert %{status: "failing", position: ^position} =
               Repo.get!(EhosContract.SubscriptionRecord, key)
    end

    test "a failing read model whose forget/2 raises is left to its runner, and the erasure stands" do
      two_members!()
      {key, position} = fail_members!()
      Process.put(:shredding_rig_forget_fails, true)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert EhosContract.erase(:member, "member-anna", actor: @officer) ==
                   {:ok, :erased}

          assert EhosContract.erase(:member, "member-bartek", actor: @officer) ==
                   {:ok, :erased}
        end)

      assert log =~ "subscription #{key}: it is failing, and its forget/2 raised Postgrex.Error"
      refute log =~ "member-anna"

      # What `forget/2` wrote before it raised is undone; the erasures are not.
      assert members() == [{"member-anna", "Anna Kowalska"}, {"member-bartek", "Bartek Nowak"}]
      assert keys() == []
      assert length(erasures()) == 2

      assert %{status: "failing", position: ^position} =
               Repo.get!(EhosContract.SubscriptionRecord, key)
    end

    test "a failing read model whose forget/2 raised forgets when its runner reaches the erasure after a skip" do
      two_members!()
      {key, _position} = fail_members!()
      Process.put(:shredding_rig_forget_fails, true)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          {:ok, :erased} = EhosContract.erase(:member, "member-anna", actor: @officer)
        end)

      assert log =~ "its forget/2 raised Postgrex.Error"

      assert members() == [{"member-anna", "Anna Kowalska"}, {"member-bartek", "Bartek Nowak"}]

      # The rebuild continues after the skipped rename, at Bartek's join, so his row
      # goes first: its rows are the partial ones a rebuild would have written.
      Process.delete(:shredding_rig_forget_fails)
      Repo.delete_all(from(m in "shredding_rig_members", where: m.member_id == "member-bartek"))
      assert :ok = Subscription.skip(Repo, key)
      Testing.drain(only: key)

      assert members() == [{"member-anna", nil}, {"member-bartek", "Bartek Nowak"}]
      assert %{status: "running"} = Repo.get!(EhosContract.SubscriptionRecord, key)
    end

    test "a second erasure is {:ok, :already_erased} and appends nothing" do
      two_members!()
      {:ok, :erased} = EhosContract.erase(:member, "member-anna", actor: @officer)
      count = length(log())

      assert EhosContract.erase(:member, "member-anna", actor: @clerk) == {:ok, :already_erased}
      assert length(log()) == count
      assert erasures() == [{"member", "member-anna", "actor:u-officer"}]
    end

    test "a read model forgets only subjects of the types whose data it holds" do
      two_members!()

      # `UniversalityGate` declares :patient; no read model of ShreddingRig holds a
      # patient's data, so none is asked to forget one.
      assert EhosContract.erase(:patient, "member-anna", actor: @officer) == {:ok, :no_data}
      assert members() == [{"member-anna", "Anna Kowalska"}, {"member-bartek", "Bartek Nowak"}]
    end

    test "an id nothing was held for says so, and is recorded all the same" do
      two_members!()

      # "Member-Anna" is not "member-anna": perhaps a typo, which the host can see.
      assert EhosContract.erase(:member, "Member-Anna", actor: @officer) == {:ok, :no_data}
      assert keys() == ["member-anna", "member-bartek"]

      assert {"member", "Member-Anna", "actor:u-officer"} in erasures()

      assert join_member("membership-typo", "Member-Anna", "Anna Nowak") ==
               {:error, :subject_erased}
    end

    test "a subject no domain declares, and no actor, are refused" do
      assert_raise ArgumentError,
                   ~r/no domain of the host's contracts declares subject :nobody/,
                   fn ->
                     EhosContract.erase(:nobody, "nobody-anna", actor: @officer)
                   end

      assert_raise ArgumentError, ~r/erase takes `actor:`/, fn ->
        EhosContract.erase(:member, "member-anna", [])
      end

      assert log() == []
    end
  end

  describe "after the transaction" do
    test "an ordered read model forgets when the erasure reaches it, in order" do
      two_members!()
      Testing.drain(only: @names)
      assert names() == [{"member-anna", "Anna Nowak"}, {"member-bartek", "Bartek Nowak"}]

      {:ok, :erased} = EhosContract.erase(:member, "member-anna", actor: @officer)
      assert length(names()) == 2

      Testing.drain(only: @names)
      assert names() == [{"member-bartek", "Bartek Nowak"}]
    end

    test "an erasure wakes the runners once it commits" do
      two_members!()
      watch_wakes()

      {:ok, :erased} = EhosContract.erase(:member, "member-anna", actor: @officer)
      assert_received :runners_woken
      refute_received :runners_woken
    end

    test "an erasure in a transaction the host owns wakes nothing before it commits" do
      two_members!()
      watch_wakes()

      {:ok, {:ok, :erased}} =
        Repo.transaction(fn -> EhosContract.erase(:member, "member-anna", actor: @officer) end)

      refute_received :runners_woken_in_transaction
      refute_received :runners_woken
    end

    test "control: a second erasure appends nothing and wakes nothing" do
      two_members!()
      {:ok, :erased} = EhosContract.erase(:member, "member-anna", actor: @officer)
      watch_wakes()

      {:ok, :already_erased} = EhosContract.erase(:member, "member-anna", actor: @officer)
      refute_received :runners_woken
    end

    test "a rebuilt read model replays the erasure too, and keeps nothing of the subject" do
      two_members!()
      {:ok, :erased} = EhosContract.erase(:member, "member-anna", actor: @officer)
      Testing.drain(only: @names)

      Subscription.register!(Repo, Implementations.subscribed())
      assert :ok = Subscription.rebuild(Repo, @names)
      Testing.drain(only: @names)

      assert names() == [{"member-bartek", "Bartek Nowak"}]
    end

    test "an erasure of a subject type no domain declares any more reads, and is forgotten by none" do
      type = "gone_#{System.unique_integer([:positive])}"
      erased = Personal.erased_event(%{"subject_type" => type, "subject_id" => "gone-anna"})
      assert erased == %Erased{subject: type, id: "gone-anna"}

      members =
        Implementations.subscribed()
        |> Enum.find(&(&1.key == "shredding_rig.members:read_model:members"))
        |> Implementations.taking(Personal.erased_type())

      assert Consumer.handle!(members, erased, []) == :ok
    end

    test "a read model nobody implemented has nothing to forget, and stops no erasure" do
      members =
        Implementations.subscribed()
        |> Enum.find(&(&1.key == "shredding_rig.members:read_model:members"))
        |> Implementations.taking(Personal.erased_type())

      erased = %Erased{subject: :member, id: "member-anna"}
      assert Consumer.handle!(%{members | module: nil}, erased, []) == :ok
    end

    test "control: a read model with no personal data takes no erasure" do
      balances =
        Enum.find(
          Implementations.subscribed(),
          &(&1.key == "dispatch_rig.ledger:read_model:balances")
        )

      refute Map.has_key?(balances.callbacks, Personal.erased_type())

      members =
        Enum.find(
          Implementations.subscribed(),
          &(&1.key == "shredding_rig.members:read_model:members")
        )

      assert members.callbacks[Personal.erased_type()] == :forget
    end
  end

  describe "dispatch after erasure" do
    test "refuses personal data of an erased subject, and writes nothing" do
      two_members!()
      {:ok, :erased} = EhosContract.erase(:member, "member-anna", actor: @officer)
      before = {log(), keys(), Repo.all(CommandRecord)}

      assert join_member("membership-anna-2", "member-anna", "Anna Nowak") ==
               {:error, :subject_erased}

      # The folded state holds Erased, which the decision copies into the event: refused
      # before it is sealed, rather than failing on it.
      assert rename_member("membership-anna", "member-anna", "Anna Nowak") ==
               {:error, :subject_erased}

      assert {log(), keys(), Repo.all(CommandRecord)} == before
    end

    test "a reaction's command refused for an erased subject leaves what set it off standing" do
      two_members!()
      {:ok, :erased} = EhosContract.erase(:member, "member-anna", actor: @officer)

      # Bartek's rename sets off a policy in the transaction that joins Anna again.
      assert {:ok, %{events: [%{name: "Rejoin Anna"}]}} =
               rename_member("membership-bartek", "member-bartek", "Rejoin Anna")

      refute Enum.any?(log(), &(&1.stream_id == "membership:membership-anna-rejoined"))
    end

    defmodule WrapSpy do
      @moduledoc false
      @behaviour EhosContract.Vault
      alias EhosContract.Vault.Local

      @impl true
      def wrap(key, context) do
        send(self(), :wrapped)
        Local.wrap(key, context)
      end

      @impl true
      def unwrap(id, wrapped, context), do: Local.unwrap(id, wrapped, context)

      @impl true
      def current, do: Local.current()

      @impl true
      def check, do: Local.check()
    end

    test "a refused command makes no key for the erased subject, not even before the lock" do
      two_members!()
      {:ok, :erased} = EhosContract.erase(:member, "member-anna", actor: @officer)

      Application.put_env(:ehos_contract, :vault, WrapSpy)
      on_exit(fn -> Application.delete_env(:ehos_contract, :vault) end)

      assert join_member("membership-anna-2", "member-anna", "Anna Nowak") ==
               {:error, :subject_erased}

      refute_received :wrapped

      # Control: a new member's key is made.
      {:ok, _} = join_member("membership-celina", "member-celina", "Celina Nowak")
      assert_received :wrapped
    end

    test "control: another member's command goes through" do
      two_members!()
      {:ok, :erased} = EhosContract.erase(:member, "member-anna", actor: @officer)

      assert {:ok, %{events: [%{name: "Bartek Kowalski", previous: "Bartek Nowak"}]}} =
               rename_member("membership-bartek", "member-bartek", "Bartek Kowalski")
    end

    test "over HTTP, the refusal is 410" do
      two_members!()
      {:ok, :erased} = EhosContract.erase(:member, "member-anna", actor: @officer)

      conn =
        conn(
          :post,
          "/commands/shredding_rig.rename",
          Jason.encode!(%{membership_id: "membership-anna", member_id: "member-anna", name: "A"})
        )
        |> put_req_header("content-type", "application/json")
        |> assign(:ehos_contract_actor, @clerk)
        |> EhosContract.Plug.call(EhosContract.Plug.init(contracts: [Members]))

      assert conn.status == 410
      assert Jason.decode!(conn.resp_body) == %{"error" => "subject_erased"}
    end
  end

  describe "at boot" do
    defmodule Unforgetting do
      @moduledoc false
    end

    test "a read model that projects personal data and defines no forget/2 is refused" do
      members =
        Enum.find(
          Implementations.subscribed(),
          &(&1.key == "shredding_rig.members:read_model:members")
        )

      assert_raise ArgumentError,
                   ~r/read model :members of ShreddingRig.Members project personal data and define no forget\/2/,
                   fn -> Personal.check_forgetting!([%{members | module: Unforgetting}]) end

      # Control: the host's own read models all forget.
      assert Personal.check_forgetting!(Implementations.index(nil).consumers) == :ok
    end
  end

  describe "conformance" do
    # What erasure could move is a number of the report; `generated_at` is the moment
    # it was asked, and nothing else differs.
    defp report, do: Members |> EhosContract.Conformance.as_data() |> Map.delete("generated_at")

    test "reads the same before and after an erasure" do
      two_members!()
      # Settled first, so the one difference left to see is the erasure's: what is in
      # flight — the greeting effect's jobs — is a number of the report too.
      Testing.drain()
      before = report()

      {:ok, :erased} = EhosContract.erase(:member, "member-anna", actor: @officer)
      Testing.drain()

      assert report() == before
      assert get_in(before, ["report", "paths"]) != []
    end
  end
end
