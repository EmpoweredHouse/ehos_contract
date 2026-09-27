defmodule EhOsContract.ErasureTest do
  @moduledoc """
  v2 plan, E8b: **erasing a subject** (v2 §14), on the invented
  `ShreddingRig.Members`: what `EhOsContract.erase/3` deletes, records and appends,
  the read models that forget — in the dispatch transaction and after it, and on a
  rebuild — dispatch refusing an erased subject's data, and conformance, which
  erasure leaves as it was.

  `async: false`: erasure and dispatch take the one append lock, and a sandboxed
  test holds it until the test ends.
  """

  use EhOsContract.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias EhOsContract.{Actor, CommandRecord, Consumer, Erased, Event, Implementations, Personal}
  alias EhOsContract.{Subscription, Testing}
  alias ShreddingRig.Members
  alias ShreddingRig.Members.Commands.{Join, Rename}
  alias ShreddingRig.Members.Events.Joined

  @clerk Actor.credential("u-clerk", ["shredding_rig.join", "shredding_rig.rename"])
  @officer Actor.credential("u-officer", [])
  @names "ShreddingRig.Members:read_model:member_names"

  defp join_member(membership, member, name) do
    EhOsContract.dispatch(
      Members,
      %Join{
        membership_id: membership,
        member_id: member,
        name: name,
        contacts: [%{member_id: member, phone: "+48 600 100 200"}],
        plan: :basic
      },
      actor: @clerk
    )
  end

  defp rename_member(membership, member, name) do
    EhOsContract.dispatch(
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
        from(k in "eh_os_contract_subject_keys", order_by: k.subject_id, select: k.subject_id)
      )

  defp erasures do
    Repo.all(
      from(e in "eh_os_contract_erasures",
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

  describe "erase/3" do
    test "deletes the keys, records the erasure, appends the event, and the read model forgets" do
      two_members!()
      assert keys() == ["member-anna", "member-bartek"]

      assert EhOsContract.erase(:member, "member-anna", actor: @officer) == :ok

      assert keys() == ["member-bartek"]
      assert erasures() == [{"member", "member-anna", "actor:u-officer"}]

      erased = List.last(log())
      assert erased.type == "eh_os_contract.subject_erased"
      assert erased.payload == %{"subject_type" => "member", "subject_id" => "member-anna"}
      assert erased.actor == "actor:u-officer"
      assert erased.contract == "EhOsContract"
      assert erased.stream_id == nil

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

    test "a second erasure is :ok and appends nothing" do
      two_members!()
      :ok = EhOsContract.erase(:member, "member-anna", actor: @officer)
      count = length(log())

      assert EhOsContract.erase(:member, "member-anna", actor: @clerk) == :ok
      assert length(log()) == count
      assert erasures() == [{"member", "member-anna", "actor:u-officer"}]
    end

    test "a read model forgets only subjects of the types whose data it holds" do
      two_members!()

      # `UniversalityGate` declares :patient; no read model of ShreddingRig holds a
      # patient's data, so none is asked to forget one.
      assert EhOsContract.erase(:patient, "member-anna", actor: @officer) == :ok
      assert members() == [{"member-anna", "Anna Kowalska"}, {"member-bartek", "Bartek Nowak"}]
    end

    test "a subject no domain declares, and no actor, are refused" do
      assert_raise ArgumentError,
                   ~r/no domain of the host's contracts declares subject :nobody/,
                   fn ->
                     EhOsContract.erase(:nobody, "nobody-anna", actor: @officer)
                   end

      assert_raise ArgumentError, ~r/erase takes `actor:`/, fn ->
        EhOsContract.erase(:member, "member-anna", [])
      end

      assert log() == []
    end
  end

  describe "after the transaction" do
    test "an ordered read model forgets when the erasure reaches it, in order" do
      two_members!()
      Testing.drain(only: @names)
      assert names() == [{"member-anna", "Anna Nowak"}, {"member-bartek", "Bartek Nowak"}]

      :ok = EhOsContract.erase(:member, "member-anna", actor: @officer)
      assert length(names()) == 2

      Testing.drain(only: @names)
      assert names() == [{"member-bartek", "Bartek Nowak"}]
    end

    test "a rebuilt read model replays the erasure too, and keeps nothing of the subject" do
      two_members!()
      :ok = EhOsContract.erase(:member, "member-anna", actor: @officer)
      Testing.drain(only: @names)

      Subscription.register!(Repo, Implementations.subscribed())
      assert :ok = Subscription.rebuild(Repo, @names)
      Testing.drain(only: @names)

      assert names() == [{"member-bartek", "Bartek Nowak"}]
    end

    test "control: a read model with no personal data takes no erasure" do
      balances =
        Enum.find(
          Implementations.subscribed(),
          &(&1.key == "DispatchRig.Ledger:read_model:balances")
        )

      refute Map.has_key?(balances.callbacks, Personal.erased_type())

      members =
        Enum.find(
          Implementations.subscribed(),
          &(&1.key == "ShreddingRig.Members:read_model:members")
        )

      assert members.callbacks[Personal.erased_type()] == :forget
    end
  end

  describe "dispatch after erasure" do
    test "refuses personal data of an erased subject, and writes nothing" do
      two_members!()
      :ok = EhOsContract.erase(:member, "member-anna", actor: @officer)
      before = {log(), keys(), Repo.all(CommandRecord)}

      assert join_member("membership-anna-2", "member-anna", "Anna Nowak") ==
               {:error, :subject_erased}

      # The folded state holds Erased, which the decision copies into the event: refused
      # before it is sealed, rather than failing on it.
      assert rename_member("membership-anna", "member-anna", "Anna Nowak") ==
               {:error, :subject_erased}

      assert {log(), keys(), Repo.all(CommandRecord)} == before
    end

    test "control: another member's command goes through" do
      two_members!()
      :ok = EhOsContract.erase(:member, "member-anna", actor: @officer)

      assert {:ok, %{events: [%{name: "Bartek Kowalski", previous: "Bartek Nowak"}]}} =
               rename_member("membership-bartek", "member-bartek", "Bartek Kowalski")
    end

    test "over HTTP, the refusal is 410" do
      two_members!()
      :ok = EhOsContract.erase(:member, "member-anna", actor: @officer)

      conn =
        conn(
          :post,
          "/commands/shredding_rig.rename",
          Jason.encode!(%{membership_id: "membership-anna", member_id: "member-anna", name: "A"})
        )
        |> put_req_header("content-type", "application/json")
        |> assign(:eh_os_contract_actor, @clerk)
        |> EhOsContract.Plug.call(EhOsContract.Plug.init(contracts: [Members]))

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
          &(&1.key == "ShreddingRig.Members:read_model:members")
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
    defp report, do: Members |> EhOsContract.Conformance.as_data() |> Map.delete("generated_at")

    test "reads the same before and after an erasure" do
      two_members!()
      before = report()

      :ok = EhOsContract.erase(:member, "member-anna", actor: @officer)
      Testing.drain()

      assert report() == before
      assert get_in(before, ["report", "paths"]) != []
    end
  end
end
