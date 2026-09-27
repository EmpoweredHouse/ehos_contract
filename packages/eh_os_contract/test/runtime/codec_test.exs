defmodule EhOsContract.CodecTest do
  @moduledoc """
  Field values against declared types, and their round trip through the log's form
  (v2 §5: what stays at run time).
  """

  use ExUnit.Case, async: true

  alias EhOsContract.{Codec, Key}

  @values %{
    money: %{name: :money, type: :integer, fields: []},
    method: %{name: :method, type: {:enum, [card: "Karta", cash: "Gotówka"]}, fields: []},
    address: %{
      name: :address,
      type: nil,
      fields: [
        %{name: :city, type: :string, optional: false},
        %{name: :zip, type: :string, optional: true}
      ]
    }
  }

  @fields [
    %{name: :visit_id, type: :id, optional: false},
    %{name: :amount, type: :money, optional: false},
    %{name: :method, type: :method, optional: false},
    %{name: :rate, type: :decimal, optional: true},
    %{name: :on, type: :date, optional: true},
    %{name: :at, type: :timestamp, optional: true},
    %{name: :codes, type: {:list, {:enum, [:a, :b]}}, optional: true},
    %{name: :address, type: :address, optional: true},
    %{name: :note, type: :string, optional: true}
  ]

  @full %{
    visit_id: "w-1",
    amount: 20_000,
    method: :card,
    rate: Decimal.new("0.23"),
    on: ~D[2026-09-01],
    at: ~U[2026-09-01 09:00:00.000000Z],
    codes: [:a, :b],
    address: %{city: "Kraków", zip: nil},
    note: nil
  }

  test "values of their types have no problems, and a missing optional field is fine" do
    assert Codec.problems(@fields, @full, @values) == []
    assert Codec.problems(@fields, %{visit_id: "w-1", amount: 1, method: :cash}, @values) == []
  end

  test "a missing required field and a value of another type are named, never their values" do
    problems =
      Codec.problems(
        @fields,
        %{
          @full
          | visit_id: nil,
            amount: 1.5,
            method: :voucher,
            codes: [:c],
            address: %{zip: "1"}
        },
        @values
      )

    assert problems == [
             visit_id: :required,
             amount: :type,
             method: :type,
             codes: :type,
             address: :type
           ]
  end

  test "a timestamp outside UTC and a float for a decimal do not fit" do
    at =
      DateTime.from_naive!(~N[2026-09-01 09:00:00], "Etc/UTC")
      |> Map.put(:time_zone, "Europe/Warsaw")

    assert {:at, :type} in Codec.problems(@fields, %{@full | at: at}, @values)
    assert {:rate, :type} in Codec.problems(@fields, %{@full | rate: 0.23}, @values)
  end

  test "the log's form is JSON's, and it decodes back to the same values" do
    encoded = Codec.encode(@fields, @full, @values)

    assert encoded == %{
             "visit_id" => "w-1",
             "amount" => 20_000,
             "method" => "card",
             "rate" => "0.23",
             "on" => "2026-09-01",
             "at" => "2026-09-01T09:00:00.000000Z",
             "codes" => ["a", "b"],
             "address" => %{"city" => "Kraków", "zip" => nil},
             "note" => nil
           }

    # Through JSON, as the payload column stores it.
    assert Codec.decode(@fields, encoded |> Jason.encode!() |> Jason.decode!(), @values) ==
             {:ok, @full}
  end

  test "decoding refuses what does not fit, and never creates an atom" do
    name = "not_a_member_#{System.unique_integer([:positive])}"

    assert Codec.decode(
             @fields,
             %{"visit_id" => "w-1", "amount" => "1", "method" => name},
             @values
           ) ==
             {:error, [amount: :type, method: :type]}

    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end

    assert Codec.decode(@fields, %{"amount" => 1, "method" => "cash"}, @values) ==
             {:error, [visit_id: :required]}
  end

  test "a field typed with a value the domain does not declare fits nothing" do
    assert Codec.problems([%{name: :x, type: :unknown}], %{x: 1}, @values) == [x: :type]
  end

  describe "Key" do
    test "streams, tags and joined keys escape the separator, so two keys never merge" do
      assert Key.stream(:visit_settlement, ["w-1"]) == "visit_settlement:w-1"
      assert Key.stream(:month, ["c-1", "2026-09"]) == "month:c-1|2026-09"
      assert Key.tag(:visit_id, "w|1") == "visit_id:w%7C1"
      refute Key.join(["a|b", "c"]) == Key.join(["a", "b|c"])
      assert Key.join(["100%", "|"]) == "100%25|%7C"
      assert_raise ArgumentError, fn -> Key.join(["a", nil]) end
    end
  end

  describe "personal fields (v2 §14)" do
    alias EhOsContract.{Erased, Personal}

    @personal [
      %{name: :member_id, type: :id, optional: false, subject: :member},
      %{name: :name, type: :string, optional: false, personal: :member_id},
      %{name: :note, type: :string, optional: true}
    ]

    @key {"member", "member-anna"}
    @keys %{@key => {1, :binary.copy(<<7>>, 32)}}
    @read %{{"member", "member-anna", 1} => :binary.copy(<<7>>, 32)}

    defp sealed(type \\ "shredding_rig.joined") do
      Codec.encode(
        @personal,
        %{member_id: "member-anna", name: "Anna Nowak", note: "n"},
        %{},
        Personal.sealer(@keys, type)
      )
    end

    test "sealed with a key, opened with it" do
      stored = sealed()
      assert %{"$eh" => "enc1", "k" => 1} = stored["name"]
      assert stored["note"] == "n"

      assert Codec.subjects(@personal, stored, %{}, :stored) == [{:member, "member-anna"}]

      assert Codec.decode(@personal, stored, %{},
               open: Personal.opener(@read, "shredding_rig.joined")
             ) ==
               {:ok, %{member_id: "member-anna", name: "Anna Nowak", note: "n"}}
    end

    test "a ciphertext moved to another event type, field or subject does not open" do
      stored = sealed("shredding_rig.joined")
      open = Personal.opener(@read, "shredding_rig.renamed")
      assert Codec.decode(@personal, stored, %{}, open: open) == {:error, [name: :type]}

      moved = %{stored | "note" => stored["name"]}

      notes =
        Enum.map(
          @personal,
          &if(&1.name == :note, do: Map.put(&1, :personal, :member_id), else: &1)
        )

      open = Personal.opener(@read, "shredding_rig.joined")
      assert {:error, [note: :type]} = Codec.decode(notes, moved, %{}, open: open)

      bartek = Map.put(@read, {"member", "member-bartek", 1}, :binary.copy(<<7>>, 32))
      other = %{stored | "member_id" => "member-bartek"}

      assert Codec.decode(@personal, other, %{},
               open: Personal.opener(bartek, "shredding_rig.joined")
             ) ==
               {:error, [name: :type]}
    end

    test "without its key, an erased subject's field is Erased; without open:, it does not fit" do
      stored = sealed()
      erased = MapSet.new([{"member", "member-anna"}])

      assert Codec.decode(@personal, stored, %{},
               open: Personal.opener(%{}, "shredding_rig.joined", erased)
             ) ==
               {:ok,
                %{
                  member_id: "member-anna",
                  name: %Erased{subject: :member, id: "member-anna"},
                  note: "n"
                }}

      assert Codec.decode(@personal, stored, %{}) == {:error, [name: :type]}

      # Without its key and never erased: raised, never read as erased.
      assert_raise ArgumentError, ~r/is missing, and the subject was never erased/, fn ->
        Codec.decode(@personal, stored, %{}, open: Personal.opener(%{}, "shredding_rig.joined"))
      end
    end

    test "Erased fits a personal field and nothing else, and cannot be sealed" do
      erased = %Erased{subject: :member, id: "member-anna"}

      assert Codec.problems(@personal, %{member_id: "member-anna", name: erased}, %{}) == []

      assert Codec.problems(@personal, %{member_id: "member-anna", name: "A", note: erased}, %{}) ==
               [note: :type]

      assert_raise ArgumentError, ~r/field name holds EhOsContract.Erased/, fn ->
        Codec.encode(
          @personal,
          %{member_id: "member-anna", name: erased},
          %{},
          Personal.sealer(@keys, "t")
        )
      end
    end

    test "out of the log, Erased is written as nil" do
      erased = %Erased{subject: :member, id: "member-anna"}

      assert Codec.encode(@personal, %{member_id: "member-anna", name: erased}, %{}) ==
               %{"member_id" => "member-anna", "name" => nil, "note" => nil}
    end

    test "personal?/2 and subjects/4 look inside domain values, lists and aliases" do
      values = %{
        contact: %{
          name: :contact,
          type: nil,
          fields: [
            %{name: :member_id, type: :id, optional: false, subject: :member},
            %{name: :phone, type: :string, optional: false, personal: :member_id}
          ]
        },
        contact_ref: %{name: :contact_ref, type: :contact, fields: []}
      }

      fields = [
        %{name: :contacts, type: {:list, :contact_ref}, optional: false},
        %{name: :count, type: :integer, optional: false}
      ]

      assert Codec.personal?(fields, values)
      refute Codec.personal?([%{name: :count, type: :integer, optional: false}], values)

      data = %{
        contacts: [
          %{member_id: "member-anna", phone: "1"},
          %{member_id: "member-bartek", phone: "2"},
          %{member_id: "member-anna", phone: "3"}
        ],
        count: 3
      }

      assert Codec.subjects(fields, data, values, :value) ==
               [{:member, "member-anna"}, {:member, "member-bartek"}]

      # In the log's form only a sealed field needs a key.
      assert Codec.subjects(fields, Codec.encode(fields, data, values), values, :stored) == []
    end
  end
end
