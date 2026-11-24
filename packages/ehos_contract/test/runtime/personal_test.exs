defmodule EhosContract.PersonalTest do
  @moduledoc """
  v2 plan, E8a: **personal fields sealed in the log, and read back** (v2 §14), on
  the invented `ShreddingRig.Members`. A membership's events carry a member's name,
  email and contacts — each contact personal to the member it names, so one event
  can carry two subjects' data — and a rename reads the previous name back from the
  folded stream.

  `async: false`: dispatch takes the one append lock, and a sandboxed test holds it
  until the test ends.
  """

  use EhosContract.DataCase, async: false

  alias EhosContract.{Actor, Consumer, Erased, Event}
  alias ShreddingRig.Members
  alias ShreddingRig.Members.Commands.{Join, Rename}
  alias ShreddingRig.Members.Events.{Joined, Renamed}

  @clerk Actor.credential("u-clerk", ["shredding_rig.join", "shredding_rig.rename"])

  defp join!(membership, member, opts \\ []) do
    command = %Join{
      membership_id: membership,
      member_id: member,
      name: Keyword.get(opts, :name, "Anna Nowak"),
      email: Keyword.get(opts, :email, "anna@example.com"),
      contacts:
        Keyword.get(opts, :contacts, [
          %ShreddingRig.Domain.Values.Contact{member_id: member, phone: "+48 600 100 200"}
        ]),
      plan: :full
    }

    {:ok, receipt} = EhosContract.dispatch(Members, command, actor: @clerk)
    receipt
  end

  defp log, do: Repo.all(from(e in Event, order_by: e.position))

  defp keys do
    Repo.all(
      from(k in "ehos_contract_subject_keys",
        order_by: [k.subject_type, k.subject_id],
        select: {k.subject_type, k.subject_id, k.key_version, k.kek_id}
      )
    )
  end

  # What erasure leaves (E8b's `erase/3` does it in one transaction): no key, and a
  # record that the subject was erased.
  defp erase_keys!(member) do
    Repo.delete_all(from(k in "ehos_contract_subject_keys", where: k.subject_id == ^member))

    Repo.insert_all("ehos_contract_erasures", [
      %{
        subject_type: "member",
        subject_id: member,
        erased_at: DateTime.utc_now(),
        requested_by: "actor:u-officer"
      }
    ])
  end

  # The queries that read or write subjects' keys while `fun` runs.
  defp key_queries(fun) do
    handler = "key-queries-#{System.unique_integer([:positive])}"
    test = self()

    :telemetry.attach(
      handler,
      [:ehos_contract, :test_repo, :query],
      fn _event, _measurements, %{query: query}, _config ->
        if query =~ "ehos_contract_subject_keys", do: send(test, {:key_query, query})
      end,
      nil
    )

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end

    collect([])
  end

  defp collect(queries) do
    receive do
      {:key_query, query} -> collect([query | queries])
    after
      0 -> Enum.reverse(queries)
    end
  end

  describe "writing" do
    test "a personal field is sealed in the log, and every other field is not" do
      join!("membership-anna", "member-anna",
        contacts: [
          %ShreddingRig.Domain.Values.Contact{member_id: "member-anna", phone: "+48 600 100 200"},
          %ShreddingRig.Domain.Values.Contact{
            member_id: "member-bartek",
            phone: "+48 600 300 400"
          }
        ]
      )

      assert [%Event{payload: payload}] = log()

      assert %{"$eh" => "enc1", "k" => 1, "d" => _} = payload["name"]
      assert %{"$eh" => "enc1", "k" => 1, "d" => _} = payload["email"]
      assert payload["member_id"] == "member-anna"
      assert payload["membership_id"] == "membership-anna"
      assert payload["plan"] == "full"

      assert [
               %{"member_id" => "member-anna", "phone" => %{"$eh" => "enc1"}},
               %{"member_id" => "member-bartek", "phone" => %{"$eh" => "enc1"}}
             ] = payload["contacts"]

      stored = Jason.encode!(payload)

      for clear <- ["Anna", "anna@example.com", "600 100 200", "600 300 400"],
          do: refute(stored =~ clear)

      # One key for each subject the event carries, wrapped by the vault's key.
      assert keys() == [
               {"member", "member-anna", 1, "test-2026-09"},
               {"member", "member-bartek", 1, "test-2026-09"}
             ]
    end

    test "a subject keeps one key across events and streams" do
      join!("membership-anna", "member-anna")
      join!("membership-anna-2", "member-anna")

      assert keys() == [{"member", "member-anna", 1, "test-2026-09"}]
    end

    test "an optional personal field left empty is stored empty, not sealed" do
      join!("membership-anna", "member-anna", email: nil)

      assert [%Event{payload: %{"email" => nil}}] = log()
    end

    test "control: an event with no personal field reads and writes no key" do
      clerk = Actor.credential("u-1", ["dispatch_rig.open_account"])

      assert key_queries(fn ->
               {:ok, _} =
                 EhosContract.dispatch(
                   DispatchRig.Ledger,
                   %DispatchRig.Ledger.Commands.OpenAccount{
                     account_id: "account-anna",
                     branch_id: "branch-north"
                   },
                   actor: clerk
                 )
             end) == []

      assert keys() == []
    end
  end

  describe "reading" do
    test "the receipt, the folded stream and a consumer read the personal fields back" do
      receipt = join!("membership-anna", "member-anna")
      assert [%Joined{name: "Anna Nowak"}] = receipt.events

      # The decision takes the previous name from the state the stream folds to.
      assert {:ok, %{events: [%Renamed{name: "Anna Kowalska", previous: "Anna Nowak"}]}} =
               EhosContract.dispatch(
                 Members,
                 %Rename{
                   membership_id: "membership-anna",
                   member_id: "member-anna",
                   name: "Anna Kowalska"
                 },
                 actor: @clerk
               )

      assert [joined, renamed] = Enum.map(log(), &Consumer.decode!/1)

      assert %Joined{
               name: "Anna Nowak",
               email: "anna@example.com",
               contacts: [
                 %ShreddingRig.Domain.Values.Contact{
                   member_id: "member-anna",
                   phone: "+48 600 100 200"
                 }
               ],
               plan: :full
             } = joined

      assert %Renamed{name: "Anna Kowalska", previous: "Anna Nowak"} = renamed
    end

    test "a folded stream reads its keys in one query, however long it is" do
      join!("membership-anna", "member-anna")

      rename = fn name ->
        {:ok, _} =
          EhosContract.dispatch(
            Members,
            %Rename{membership_id: "membership-anna", member_id: "member-anna", name: name},
            actor: @clerk
          )
      end

      short = key_queries(fn -> rename.("Anna Kowalska") end)
      for name <- ~w(Anna-2 Anna-3 Anna-4 Anna-5), do: rename.(name)
      long = key_queries(fn -> rename.("Anna Wisniewska") end)

      # One for the key the new event is sealed with, one for the whole stream.
      assert length(short) == 2
      assert length(long) == length(short)
    end
  end

  describe "without the key" do
    test "a personal field reads back as Erased, and every other field as it was" do
      join!("membership-anna", "member-anna",
        contacts: [
          %ShreddingRig.Domain.Values.Contact{member_id: "member-anna", phone: "+48 600 100 200"},
          %ShreddingRig.Domain.Values.Contact{
            member_id: "member-bartek",
            phone: "+48 600 300 400"
          }
        ]
      )

      erase_keys!("member-anna")
      assert [row] = log()

      anna = %Erased{subject: :member, id: "member-anna"}

      assert %Joined{
               membership_id: "membership-anna",
               member_id: "member-anna",
               name: ^anna,
               email: ^anna,
               plan: :full,
               contacts: [
                 %{member_id: "member-anna", phone: ^anna},
                 # Control: the other member's key is there, so their phone reads.
                 %{member_id: "member-bartek", phone: "+48 600 300 400"}
               ]
             } = Consumer.decode!(row)
    end

    test "a key missing for a subject never erased does not read as Erased, and says so" do
      join!("membership-anna", "member-anna")
      Repo.delete_all(from(k in "ehos_contract_subject_keys"))

      assert_raise ArgumentError,
                   ~r/the data key of subject member "member-anna", version 1, is missing, and the subject was never erased/,
                   fn -> Enum.map(log(), &Consumer.decode!/1) end
    end

    test "control: a member whose key is there reads normally" do
      join!("membership-anna", "member-anna")
      join!("membership-bartek", "member-bartek", name: "Bartek Nowak")

      erase_keys!("member-anna")

      assert [%Joined{name: %Erased{}}, %Joined{name: "Bartek Nowak"}] =
               Enum.map(log(), &Consumer.decode!/1)
    end
  end

  describe "the generated structs" do
    # A person's data stays out of a value printed in a log or a failed test's message.
    test "inspect a value, an event and a command without their personal fields" do
      shown =
        inspect(%ShreddingRig.Domain.Values.Contact{
          member_id: "member-anna",
          phone: "+48 600 100 200"
        })

      assert shown =~ "member-anna"
      refute shown =~ "600 100 200"

      # The same for an event's, a command's or a state's own personal fields.
      shown =
        inspect(%Joined{
          membership_id: "membership-anna",
          member_id: "member-anna",
          name: "Anna Nowak",
          email: "anna@example.com",
          contacts: [],
          plan: :full
        })

      assert shown =~ "member-anna"
      refute shown =~ "Anna Nowak"
      refute shown =~ "anna@example.com"
    end

    test "admit Erased on a personal field, and only there" do
      {:ok, types} = Code.Typespec.fetch_types(Joined)
      [t] = for {:type, {:t, spec, []}} <- types, do: spec
      string = Macro.to_string(Code.Typespec.type_to_quoted({:t, t, []}))

      assert string =~ "name: String.t() | EhosContract.Erased.t()"
      assert string =~ "member_id: String.t(),"
      refute string =~ "member_id: String.t() | EhosContract.Erased.t()"

      # A value made of fields is its struct (#486), whose personal field admits it too.
      {:ok, types} = Code.Typespec.fetch_types(ShreddingRig.Domain.Values.Contact)
      [t] = for {:type, {:t, spec, []}} <- types, do: spec
      string = Macro.to_string(Code.Typespec.type_to_quoted({:t, t, []}))
      assert string =~ "phone: String.t() | EhosContract.Erased.t()"
    end
  end
end
